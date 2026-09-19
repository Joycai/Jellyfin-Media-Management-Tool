import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';
import 'thinking_dialect.dart';

/// How a request asks for JSON, most to least constrained. [OpenAiProvider]
/// steps down this list when a server rejects the current form.
enum _JsonMode { object, schema, none }

/// A way of asking a hybrid model for no reasoning, in the order they are
/// tried. No one way works on every server, and several are silently ignored
/// rather than rejected, so each is judged by what comes back: a reply that
/// still reasons moves the next request on to the next way.
enum _ThinkingOff {
  /// `chat_template_kwargs.enable_thinking = false`, which llama.cpp and vLLM
  /// hand to the chat template.
  templateKwargs,

  /// `reasoning_effort: "none"` — Ollama's `/v1`, and llama.cpp and vLLM too.
  effortNone,

  /// Qwen3's `/no_think` soft switch. Prompt text, so it reaches the model
  /// through any server, including one with no documented reasoning control.
  softSwitch,
}

/// Talks to any OpenAI-compatible `/chat/completions` endpoint.
class OpenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  /// Replaces the transport in tests. Left null, a request goes through its
  /// cancel token's client (so cancelling closes the socket) or the shared
  /// pooled one.
  final http.Client? _client;

  /// How long to wait for the first streamed event. Covers what a local
  /// server does before it says anything: loading the model and reading the
  /// whole prompt.
  final Duration firstEventTimeout;

  /// How long the stream may fall silent once it has started.
  final Duration idleTimeout;

  OpenAiProvider(
    this.config, {
    http.Client? client,
    this.firstEventTimeout = const Duration(minutes: 10),
    this.idleTimeout = const Duration(minutes: 2),
  }) : _client = client;

  /// The JSON mode each server + model last accepted, remembered for the
  /// process so only the first request of a session pays for a rejection.
  static final Map<String, _JsonMode> _acceptedJsonModes = {};

  /// Server + model pairs that refused `max_tokens` in favour of
  /// `max_completion_tokens`, as OpenAI's reasoning models do.
  static final Set<String> _wantsMaxCompletionTokens = {};

  /// Optional fields each server + model refused by name: sampling fields the
  /// server does not know (`top_k` on OpenAI's own API), fields a reasoning
  /// model will not take (`temperature`), `stream_options`.
  static final Map<String, Set<String>> _rejectedFields = {};

  /// Which [_ThinkingOff] way each server + model is on.
  static final Map<String, int> _thinkingOffAttempts = {};

  /// The server kind behind each API root, detected once per session.
  static final Map<String, Future<ServerKind>> _serverKinds = {};

  /// Normalized base URL. Used to derive `/chat/completions` and `/models`.
  ///
  /// `/v1` is appended only to a bare origin — `http://localhost:1234`, which
  /// is what LM Studio, Ollama and llama.cpp print at startup and what users
  /// paste. A URL that already carries a path is left exactly as typed: a
  /// relay or gateway routes below its own prefix (`…/api/openai`, Azure's
  /// `…/openai/deployments/<name>`), and "helpfully" appending a version
  /// segment there produces a 404 the user cannot see the cause of, on the one
  /// kind of endpoint where they were most careful about the URL.
  String get _base {
    var base = config.endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final path = Uri.tryParse(base)?.path ?? '';
    return path.isEmpty ? '$base/v1' : base;
  }

  /// [_base] without its `/v1` — where LM Studio, Ollama and llama.cpp serve
  /// their native endpoints beside the compatible API.
  String get _root {
    final base = _base;
    return base.endsWith('/v1') ? base.substring(0, base.length - 3) : base;
  }

  /// What the per-server memories below are keyed by.
  ///
  /// The key includes the credential, not just the URL and model: two profiles
  /// can point at one endpoint through different keys — a personal and a work
  /// account, a gateway that routes by token — and what one of them was
  /// refused says nothing about the other. The key itself is never stored,
  /// only its hash, so none of these process-lifetime maps holds a secret.
  String get _cacheKey =>
      '${config.provider.id}|$_base|${config.model}|'
      '${config.apiKey.trim().hashCode}';

  Uri get _chatUri => Uri.parse('$_base/chat/completions');

  Map<String, String> get _headers {
    final key = config.apiKey.trim();
    return {
      'Content-Type': 'application/json',
      // A keyless local server gets no Authorization header rather than an
      // empty `Bearer `.
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
    };
  }

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) async => AiResponse.fromChat(
    await _exchange(
      messages: [SystemMessage(systemPrompt), UserMessage(userPrompt)],
      tools: const [],
      jsonMode: true,
      cancelToken: cancelToken,
    ),
  );

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) => _exchange(
    messages: messages,
    tools: tools,
    jsonMode: false,
    cancelToken: cancelToken,
  );

  /// Performs one streamed request.
  ///
  /// **Why a stream.** A plan is long and a local model writes it slowly: a
  /// 27B model on LM Studio took 88 s for thirty episodes, much of it
  /// reasoning. The request used to have 120 s in total, so any real folder
  /// timed out, and the retry that followed made the server start the same
  /// generation again while the abandoned one was still running. A stream is
  /// timed on silence instead — [firstEventTimeout] for loading and reading
  /// the prompt, [idleTimeout] for any later gap. Closing the stream, on
  /// timeout or cancel, is also what makes the server stop generating. A
  /// timeout is never retried.
  ///
  /// **Sampling.** Every value the resolved preset holds is sent explicitly,
  /// neutral ones included: servers fill gaps with their own defaults
  /// (llama.cpp `min_p 0.05`; Ollama forces `temperature` and `top_p` to 1.0
  /// when missing), so an omitted `min_p: 0` is not a preset at all. A field
  /// a server rejects by name is dropped and remembered.
  ///
  /// **Reasoning.** A cloud platform with a documented switch gets that
  /// switch, both ways, and nothing else — see [ThinkingDialect]. Anywhere
  /// else, with thinking off, a hybrid family is asked for no reasoning in the
  /// way its server understands — see [_ThinkingOff].
  ///
  /// **JSON mode** ([jsonMode], never together with tools).
  /// `response_format: json_object` is OpenAI's form and most servers take it,
  /// but not all: LM Studio answers it with a 400 ("'response_format.type'
  /// must be 'json_schema' or 'text'"). A rejection naming the parameter
  /// retries with a permissive `json_schema`, then with no constraint at all.
  /// The mode that worked is remembered.
  Future<ChatResult> _exchange({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    required bool jsonMode,
    AiCancelToken? cancelToken,
  }) async {
    // A cancellable call goes through the token's own client so cancelling can
    // close the socket; otherwise reuse the shared pooled client.
    final client = _client ?? cancelToken?.client ?? AiHttp.client;
    final sampling = config.sampling;
    final values = sampling.values;
    final control = sampling.preset?.thinkingControl ?? ThinkingControl.none;
    final dialect = ThinkingDialect.forEndpoint(config.endpoint);
    final dialectField = dialect?.field(thinking: sampling.thinking);
    final offWays =
        dialect == null &&
            !sampling.thinking &&
            (control == ThinkingControl.templateSwitch ||
                control == ThinkingControl.softSwitch)
        ? _thinkingOffWays(control, await detectServerKind())
        : const <_ThinkingOff>[];
    final rejected = _rejectedFields.putIfAbsent(_cacheKey, () => <String>{});
    final maxTokens = config.maxOutputTokens;
    var mode = _acceptedJsonModes[_cacheKey] ?? _JsonMode.object;
    var maxCompletionTokens = _wantsMaxCompletionTokens.contains(_cacheKey);

    while (true) {
      final attempt = _thinkingOffAttempts[_cacheKey] ?? 0;
      final off = attempt < offWays.length ? offWays[attempt] : null;

      final optional = <String, Object>{
        'temperature': ?values.temperature,
        'top_p': ?values.topP,
        'top_k': ?values.topK,
        'min_p': ?values.minP,
        'presence_penalty': ?values.presencePenalty,
        'repeat_penalty': ?values.repeatPenalty,
        // gpt-oss cannot stop reasoning; asked for none, it gets the least.
        if (control == ThinkingControl.effortOnly &&
            !config.thinkingEnabled &&
            dialect == null)
          'reasoning_effort': 'low',
        if (dialectField != null) dialectField.key: dialectField.value,
        if (off == _ThinkingOff.templateKwargs)
          'chat_template_kwargs': const {'enable_thinking': false},
        if (off == _ThinkingOff.effortNone) 'reasoning_effort': 'none',
        // Asks for token usage in the final chunk; a stream omits it otherwise.
        'stream_options': const {'include_usage': true},
      }..removeWhere((key, _) => rejected.contains(key));

      String editSystem(String prompt) => switch ((off, control)) {
        (_ThinkingOff.softSwitch, _) => '$prompt\n\n/no_think',
        // Gemma 4 reasons only when the system prompt opens with this token.
        (_, ThinkingControl.promptToken) when config.thinkingEnabled =>
          '<|think|>\n$prompt',
        _ => prompt,
      };

      var systemSeen = false;
      final wire = [
        for (final message in messages)
          if (message is SystemMessage && !systemSeen)
            (() {
              systemSeen = true;
              return {'role': 'system', 'content': editSystem(message.content)};
            })()
          else
            _wire(message),
      ];

      final body = jsonEncode({
        'model': config.model,
        ...optional,
        (maxCompletionTokens ? 'max_completion_tokens' : 'max_tokens'):
            ?maxTokens,
        if (jsonMode) ...?_responseFormat(mode),
        if (tools.isNotEmpty) 'tools': [for (final tool in tools) _tool(tool)],
        'stream': true,
        'messages': wire,
      });

      http.StreamedResponse res;
      try {
        res = await AiHttp.withRetry(
          () => client
              .send(
                http.Request('POST', _chatUri)
                  ..headers.addAll(_headers)
                  ..body = body,
              )
              .timeout(firstEventTimeout),
          cancelToken: cancelToken,
          retryTimeouts: false,
        );
      } on AiCancelled {
        rethrow;
      } on TimeoutException {
        if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
        throw AiNetworkException(_noResponse(firstEventTimeout));
      } catch (e) {
        // Closing the client to cancel surfaces as a generic ClientException;
        // report it as a cancellation, not a network failure.
        if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
        throw AiNetworkException(AiHttp.describeTransportError(e));
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (jsonMode) _acceptedJsonModes[_cacheKey] = mode;
        final result = await _read(res, cancelToken);
        if (off == null || !result.reasoned) return result;
        // This way of asking was ignored; the next request tries the next.
        _thinkingOffAttempts[_cacheKey] = attempt + 1;
        return result.withThinkingOffPending(attempt + 1 < offWays.length);
      }

      String error;
      try {
        error = AiHttp.describeError(await http.Response.fromStream(res));
      } catch (_) {
        error = 'HTTP ${res.statusCode}';
      }
      if (res.statusCode == 400 || res.statusCode == 422) {
        final detail = error.toLowerCase();
        // Checked before the field names: this message also says `max_tokens`.
        if (maxTokens != null &&
            !maxCompletionTokens &&
            detail.contains('max_completion_tokens')) {
          maxCompletionTokens = true;
          _wantsMaxCompletionTokens.add(_cacheKey);
          continue;
        }
        if (jsonMode &&
            mode != _JsonMode.none &&
            _namesResponseFormat(detail)) {
          mode = _JsonMode.values[mode.index + 1];
          continue;
        }
        final refused = optional.keys
            .where((field) => _namesField(detail, field))
            .firstOrNull;
        if (refused != null) {
          final isThinkingOffField =
              refused == 'chat_template_kwargs' ||
              (refused == 'reasoning_effort' && off == _ThinkingOff.effortNone);
          if (isThinkingOffField) {
            _thinkingOffAttempts[_cacheKey] = attempt + 1;
          } else {
            rejected.add(refused);
          }
          continue;
        }
      }
      throw AiException(error);
    }
  }

  static Map<String, Object?> _tool(ToolDefinition tool) => {
    'type': 'function',
    'function': {
      'name': tool.name,
      'description': tool.description,
      'parameters': tool.parameters,
    },
  };

  static Map<String, Object?> _wire(ChatMessage message) => switch (message) {
    SystemMessage(:final content) => {'role': 'system', 'content': content},
    UserMessage(:final content) => {'role': 'user', 'content': content},
    AssistantMessage(:final content, :final toolCalls, :final reasoning) => {
      'role': 'assistant',
      // A tool-call turn with no prose is `null` content, not an empty string.
      'content': toolCalls.isNotEmpty && content.isEmpty ? null : content,
      if (toolCalls.isNotEmpty)
        'tool_calls': [
          for (final call in toolCalls)
            {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.arguments},
            },
        ],
      if (toolCalls.isNotEmpty && reasoning != null)
        reasoning.field: reasoning.text,
    },
    ToolResultMessage(:final toolCallId, :final content) => {
      'role': 'tool',
      'tool_call_id': toolCallId,
      'content': content,
    },
  };

  static List<_ThinkingOff> _thinkingOffWays(
    ThinkingControl control,
    ServerKind kind,
  ) => [
    // Ollama's `/v1` passes nothing through to the template.
    if (kind != ServerKind.ollama) _ThinkingOff.templateKwargs,
    _ThinkingOff.effortNone,
    if (control == ThinkingControl.softSwitch) _ThinkingOff.softSwitch,
  ];

  /// Whether a rejection names [field]. A plain substring test for the
  /// sampling fields, whose names do not occur in prose; `thinking` does
  /// ("… in thinking mode", a docs link to `thinking_mode`), and reading such
  /// an error as a refusal would drop the platform's reasoning switch for the
  /// session — silently back to paid reasoning. So `thinking` counts only when
  /// quoted or addressed as a parameter.
  static bool _namesField(String detail, String field) => field == 'thinking'
      ? RegExp(
          r'''["'`]thinking["'`.]|thinking\.type|thinking (field|parameter)''',
        ).hasMatch(detail)
      : detail.contains(field);

  static bool _namesResponseFormat(String detail) =>
      detail.contains('response_format') ||
      detail.contains('json_object') ||
      detail.contains('json_schema');

  static Map<String, Object>? _responseFormat(_JsonMode mode) => switch (mode) {
    _JsonMode.object => const {
      'response_format': {'type': 'json_object'},
    },
    // The loosest schema a server accepts: "some JSON object". The real
    // shape stays in the prompt, where a model that drifts from it is
    // caught by the parser rather than by a grammar it may not support.
    _JsonMode.schema => const {
      'response_format': {
        'type': 'json_schema',
        'json_schema': {
          'name': 'response',
          'schema': {'type': 'object'},
        },
      },
    },
    _JsonMode.none => null,
  };

  /// Collects a streamed reply from its server-sent events.
  ///
  /// `delta.content` is the answer and `delta.tool_calls` arrive in fragments
  /// keyed by index. Reasoning (`reasoning_content` or `reasoning`) is kept
  /// under the field name the server used, for sending back with tool calls.
  /// A body that is not an event stream — a server or proxy that ignored
  /// `stream: true` — is parsed as one ordinary JSON completion instead.
  Future<ChatResult> _read(
    http.StreamedResponse res,
    AiCancelToken? cancelToken,
  ) async {
    final eventStream =
        res.headers['content-type']?.contains('text/event-stream') ?? false;
    final lines = StreamIterator(
      res.stream.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final content = StringBuffer();
    final plain = StringBuffer();
    final calls = SplayTreeMap<int, _PendingCall>();
    final reasoningText = StringBuffer();
    String? reasoningField;
    bool? sse;
    String? finishReason;
    var promptTokens = 0;
    var completionTokens = 0;
    var reasoningTokens = 0;
    var started = false;

    try {
      while (true) {
        final bool more;
        try {
          more = await lines.moveNext().timeout(
            started ? idleTimeout : firstEventTimeout,
          );
        } on TimeoutException {
          throw AiNetworkException(
            started
                ? 'The server stopped sending for ${_duration(idleTimeout)} '
                      'partway through the reply.'
                : _noResponse(firstEventTimeout),
          );
        }
        if (!more) break;
        final line = lines.current;
        if (line.trim().isEmpty) continue;
        started = true;
        sse ??= eventStream || line.startsWith('data:');
        if (!sse) {
          plain.writeln(line);
          continue;
        }
        // `event:`, `id:` and `:` keep-alive comments carry nothing we need.
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;

        final Object? event;
        try {
          event = jsonDecode(data);
        } on FormatException {
          continue;
        }
        if (event is! Map) continue;
        _throwOnErrorEnvelope(event);
        final choices = event['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = choices.first as Map;
          final delta = choice['delta'];
          if (delta is Map) {
            content.write(_text(delta['content']));
            for (final field in _reasoningFields) {
              final piece = delta[field];
              if (piece is String && piece.isNotEmpty) {
                reasoningField ??= field;
                reasoningText.write(piece);
              }
            }
            final toolCalls = delta['tool_calls'];
            if (toolCalls is List) {
              for (final fragment in toolCalls.whereType<Map>()) {
                final index =
                    (fragment['index'] as num?)?.toInt() ?? calls.length;
                calls.putIfAbsent(index, _PendingCall.new).add(fragment);
              }
            }
          }
          if (choice['finish_reason'] is String) {
            finishReason = choice['finish_reason'] as String;
          }
        }
        final usage = event['usage'];
        if (usage is Map) {
          promptTokens =
              (usage['prompt_tokens'] as num?)?.toInt() ?? promptTokens;
          completionTokens =
              (usage['completion_tokens'] as num?)?.toInt() ?? completionTokens;
          reasoningTokens = _reasoningTokens(usage);
        }
      }
    } on AiException {
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      throw AiNetworkException(AiHttp.describeTransportError(e));
    } finally {
      // On an early exit this closes the connection, which is what tells the
      // server to stop generating.
      await lines.cancel();
    }

    if (sse != true) return _parse(plain.toString());
    _throwOnFailedFinish(finishReason);
    if (content.isEmpty && calls.isEmpty && finishReason == null) {
      throw const AiException('Empty response from model.');
    }
    final (text, inline) = splitReasoning(content.toString());
    final field = reasoningField;
    return ChatResult(
      text: text,
      toolCalls: [
        for (final entry in calls.entries) entry.value.build(entry.key),
      ],
      reasoning: field == null
          ? null
          : (field: field, text: reasoningText.toString()),
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      finishReason: finishReason,
      reasoned:
          inline ||
          reasoningText.toString().trim().isNotEmpty ||
          reasoningTokens > 0,
    );
  }

  static const _reasoningFields = ['reasoning_content', 'reasoning'];

  /// Parses a body that is not an event stream as one ordinary completion.
  ///
  /// Any shape it does not expect is a failure worth naming, not a Dart type
  /// error: this runs after the stream's own error handling, so an uncaught
  /// cast would reach the task list as an exception message.
  static ChatResult _parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const AiException('Empty response from model.');
    }
    if (json is! Map) throw const AiException('Empty response from model.');
    _throwOnErrorEnvelope(json);
    try {
      return _parseCompletion(json);
    } on AiException {
      rethrow;
    } on TypeError {
      throw const AiException(
        'The server sent a completion in a shape this app does not read.',
      );
    }
  }

  static ChatResult _parseCompletion(Map<dynamic, dynamic> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiException('Empty response from model.');
    }
    final choice = choices.first as Map;
    final finishReason = _stringOrNull(choice['finish_reason']);
    _throwOnFailedFinish(finishReason);
    final message = choice['message'];
    final usage = json['usage'];
    final content = message is Map ? _text(message['content']) : '';
    final (text, inline) = splitReasoning(content);

    ReasoningPassback? reasoning;
    if (message is Map) {
      for (final field in _reasoningFields) {
        final value = message[field];
        if (value is String && value.trim().isNotEmpty) {
          reasoning = (field: field, text: value);
          break;
        }
      }
    }
    final rawCalls = message is Map ? message['tool_calls'] : null;
    final toolCalls = <ToolCall>[
      if (rawCalls is List)
        for (final (index, raw) in rawCalls.whereType<Map>().indexed)
          if (raw['function'] case final Map<dynamic, dynamic> function)
            ToolCall(
              id: raw['id'] is String && (raw['id'] as String).isNotEmpty
                  ? raw['id'] as String
                  : 'call_$index',
              name: _stringOrNull(function['name']) ?? '',
              // Some servers hand arguments back already decoded.
              arguments: switch (function['arguments']) {
                String s => s,
                null => '{}',
                final Object other => jsonEncode(other),
              },
            ),
    ];

    return ChatResult(
      text: text,
      toolCalls: toolCalls,
      reasoning: reasoning,
      promptTokens: usage is Map
          ? (usage['prompt_tokens'] as num?)?.toInt() ?? 0
          : 0,
      completionTokens: usage is Map
          ? (usage['completion_tokens'] as num?)?.toInt() ?? 0
          : 0,
      finishReason: finishReason,
      reasoned:
          inline ||
          reasoning != null ||
          (usage is Map && _reasoningTokens(usage) > 0),
    );
  }

  static String? _stringOrNull(Object? value) => value is String ? value : null;

  /// Message text in either shape a server uses: a string, or — from relays
  /// that mirror a backend's content parts onto `chat/completions` — a list of
  /// `{"type": "text", "text": …}` parts. Reading only the string dropped the
  /// whole answer from such a relay and reported a successful empty reply.
  static String _text(Object? content) => switch (content) {
    String text => text,
    List<Object?> parts =>
      parts
          .whereType<Map<dynamic, dynamic>>()
          .where(
            (p) =>
                p['type'] == null ||
                p['type'] == 'text' ||
                p['type'] == 'output_text',
          )
          .map((p) => p['text'])
          .whereType<String>()
          .join(),
    _ => '',
  };

  /// Throws for an error that arrived with HTTP 200: OpenAI's `error` object
  /// (or a bare string), and MiniMax's `base_resp` with a non-zero
  /// `status_code` — how it reports an expired key or an empty balance. Read
  /// as an ordinary body, either became "Empty response from model." and sent
  /// the user off to look at the model instead of the account.
  static void _throwOnErrorEnvelope(Map<dynamic, dynamic> json) {
    final error = json['error'];
    if (error != null) {
      final message = error is Map ? error['message'] ?? error['code'] : error;
      throw AiException('Model error: $message');
    }
    if (json['base_resp'] case final Map<dynamic, dynamic> base) {
      final code = base['status_code'];
      if (code is num && code != 0) {
        final message = base['status_msg'];
        // Rate limits, an expired key, an empty balance: facts about the
        // account, never about whether the model calls tools.
        throw AiNetworkException(
          message is String && message.trim().isNotEmpty
              ? 'Model error $code: ${message.trim()}'
              : 'Model error $code.',
        );
      }
    }
  }

  /// See [FinishReasons.failure].
  static void _throwOnFailedFinish(String? finishReason) {
    switch (FinishReasons.failure(finishReason)) {
      case FinishFailure.filtered:
        throw AiException(
          'The provider\'s content filter stopped the reply '
          '("$finishReason"). What arrived before it was discarded.',
        );
      case FinishFailure.upstream:
        throw AiNetworkException(
          'The upstream model failed partway through the reply '
          '("$finishReason").',
        );
      case FinishFailure.contextExceeded:
        throw AiException(
          'The conversation no longer fits the model\'s context window '
          '("$finishReason"). Set the context window in the AI service '
          'settings to what the server really serves, so older tool results '
          'are shortened in time.',
        );
      case null:
        return;
    }
  }

  /// Separates a leading think block from the answer.
  ///
  /// Some servers pass reasoning inline in the content rather than in
  /// `reasoning_content`, and a brace inside it derails every JSON parser.
  /// Only a block at the very start counts — a tag later on is the model's
  /// own text. The Thinking-2507 models can omit the opening tag, so a lone
  /// `</think>` closes a leading block too. Returns the answer, and whether
  /// the block held any reasoning (Qwen3's `/no_think` leaves an empty one).
  static (String, bool) splitReasoning(String content) {
    const open = '<think>';
    const close = '</think>';
    final trimmed = content.trimLeft();
    if (trimmed.startsWith(open)) {
      final end = trimmed.indexOf(close);
      if (end == -1) return ('', trimmed.length > open.length);
      final inner = trimmed.substring(open.length, end);
      return (
        trimmed.substring(end + close.length).trimLeft(),
        inner.trim().isNotEmpty,
      );
    }
    final end = content.indexOf(close);
    if (end != -1) {
      return (
        content.substring(end + close.length).trimLeft(),
        content.substring(0, end).trim().isNotEmpty,
      );
    }
    return (content, false);
  }

  static int _reasoningTokens(Map<dynamic, dynamic> usage) {
    final details = usage['completion_tokens_details'];
    return details is Map
        ? (details['reasoning_tokens'] as num?)?.toInt() ?? 0
        : 0;
  }

  static String _noResponse(Duration timeout) =>
      'No response from the server within ${_duration(timeout)}.';

  static String _duration(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  /// Asks every server dialect at once — llama.cpp, LM Studio, Ollama, then
  /// the generic model list — and keeps the most authoritative answer; see
  /// [ModelLimits] for why a loaded size outranks a model maximum.
  @override
  Future<ModelLimits> detectLimits() async {
    final model = config.model.trim();
    final answers = await Future.wait([
      _probe(Uri.parse('$_root/props')),
      _probe(Uri.parse('$_root/api/v0/models')),
      _probe(Uri.parse('$_root/api/ps')),
      _probe(Uri.parse('$_root/api/show'), body: {'model': model}),
      _probe(Uri.parse('$_base/models')),
    ]);
    return ModelLimits.pick([
      ModelLimits.fromLlamaCppProps(answers[0]),
      ModelLimits.fromLmStudioModels(answers[1], model),
      ModelLimits.fromOllamaPs(answers[2], model),
      ModelLimits.fromOllamaShow(answers[3]),
      ModelLimits.fromOpenAiModels(answers[4], model),
    ]);
  }

  /// Each server answers one route only it serves: LM Studio lists models
  /// with their load state, Ollama and vLLM report a version on different
  /// paths, llama.cpp exposes its launch settings. Detected once per API root
  /// for the session.
  @override
  Future<ServerKind> detectServerKind() =>
      _serverKinds[_root] ??= _probeServerKind();

  Future<ServerKind> _probeServerKind() async {
    final answers = await Future.wait([
      _probe(Uri.parse('$_root/api/v0/models')),
      _probe(Uri.parse('$_root/api/version')),
      _probe(Uri.parse('$_root/props')),
      _probe(Uri.parse('$_root/version')),
    ]);
    bool has(Object? json, String key) => json is Map && json[key] != null;
    if (answers[0] case final Map<dynamic, dynamic> models
        when models['data'] is List) {
      return ServerKind.lmStudio;
    }
    if (has(answers[1], 'version')) return ServerKind.ollama;
    if (has(answers[2], 'default_generation_settings')) {
      return ServerKind.llamaCpp;
    }
    if (has(answers[3], 'version')) return ServerKind.vllm;
    return ServerKind.unknown;
  }

  /// One discovery request: decoded JSON, or null for anything else. The
  /// timeout is short because a server that does not speak a dialect usually
  /// 404s at once, and one that hangs must not hold up the connection test.
  Future<Object?> _probe(Uri uri, {Object? body}) async {
    final client = _client ?? AiHttp.client;
    try {
      final request = body == null
          ? client.get(uri, headers: _headers)
          : client.post(uri, headers: _headers, body: jsonEncode(body));
      final res = await request.timeout(const Duration(seconds: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }
}

/// A tool call assembled from stream fragments.
///
/// Arguments arrive in pieces and are appended. The id and name normally
/// arrive once, and some servers even split the id, so a new piece is
/// appended — but others repeat the full id and name in every fragment, so a
/// piece equal to what is already there is ignored rather than doubled.
class _PendingCall {
  String _id = '';
  String _name = '';
  final _arguments = StringBuffer();

  void add(Map<dynamic, dynamic> fragment) {
    final id = fragment['id'];
    if (id is String && id.isNotEmpty) _id = _mergeFragment(_id, id);
    final function = fragment['function'];
    if (function is! Map) return;
    final name = function['name'];
    if (name is String && name.isNotEmpty) {
      _name = _mergeFragment(_name, name);
    }
    final arguments = function['arguments'];
    if (arguments is String) {
      _arguments.write(arguments);
    } else if (arguments is Map) {
      _arguments.write(jsonEncode(arguments));
    }
  }

  ToolCall build(int index) => ToolCall(
    id: _id.isEmpty ? 'call_$index' : _id,
    name: _name,
    arguments: _arguments.isEmpty ? '{}' : _arguments.toString(),
  );

  /// Providers vary between delta fragments and cumulative values. Keep the
  /// longest useful prefix instead of duplicating a cumulative value (or
  /// appending a new suffix to an already-complete value).
  static String _mergeFragment(String current, String fragment) {
    if (current.isEmpty || fragment == current) {
      return current.isEmpty ? fragment : current;
    }
    if (fragment.startsWith(current)) return fragment;
    if (current.startsWith(fragment)) return current;
    return '$current$fragment';
  }
}
