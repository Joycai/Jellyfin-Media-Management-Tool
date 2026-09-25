import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';
import 'api_log.dart';
import 'learned_behaviour.dart';
import 'platform_profiles.dart';
import 'sse.dart';
import 'thinking_dialect.dart';

/// Talks to the Anthropic Messages API (`/v1/messages`), and to the
/// Anthropic-shaped routes other platforms mirror (DeepSeek, DashScope,
/// Zhipu, MiniMax, relays).
///
/// The shape differs from Chat Completions in ways that each fail loudly or
/// silently when ignored, so the request is repaired before it is sent:
///
/// - roles strictly alternate, and the system prompt is a top-level field;
/// - every tool result of a round goes back as one user turn of
///   `tool_result` blocks, matching the one assistant turn whose calls they
///   answer;
/// - `max_tokens` is required — [defaultMaxTokens] when the user set none;
/// - an assistant turn goes back as the exact blocks it arrived in, thinking
///   blocks and their signatures included, but only to the model that wrote
///   them ([ProviderTurn]);
/// - usage is three buckets (input, cache writes, cache reads) that together
///   are the prompt.
///
/// Streamed and timed on silence, like the other providers.
class AnthropicProvider implements AiProvider {
  @override
  final AiConfig config;

  final http.Client? _client;
  final Duration firstEventTimeout;
  final Duration idleTimeout;

  AnthropicProvider(
    this.config, {
    http.Client? client,
    this.firstEventTimeout = const Duration(minutes: 10),
    this.idleTimeout = const Duration(minutes: 2),
  }) : _client = client;

  /// The API version this adapter is written against. Pinned: a header that
  /// followed the latest version would change the wire shape under it.
  static const apiVersion = '2023-06-01';

  /// Sent when the user set no output cap; the protocol has no default.
  static const defaultMaxTokens = 8192;

  static LearnedStore get _learned => LearnedStore.instance;

  /// `…/v1` as typed, else the root with `/v1` added: Anthropic's own host
  /// is a bare origin, and the platforms that mirror it publish a prefix
  /// (`/apps/anthropic`, `/api/anthropic`) below which `/v1/messages` sits.
  /// A pasted full endpoint (`…/v1/messages`) is cut back to its root first
  /// — a path segment only, never a host named `messages`.
  String get _base {
    final base = AiHttp.endpointBase(
      config.endpoint,
    ).replaceFirst(RegExp(r'(?<=[^/])/messages$'), '');
    return base.endsWith('/v1') ? base : '$base/v1';
  }

  Uri get _messagesUri => Uri.parse('$_base/messages');

  bool get _official => _messagesUri.host == 'api.anthropic.com';

  String get _cacheKey => LearnedStore.routeKey(
    protocol: config.provider.id,
    base: _base,
    model: config.model,
    apiKey: config.apiKey,
  );

  @override
  void forgetLearned() => _learned.forget(_cacheKey);

  @override
  LearnedBehaviour get learned => _learned.of(_cacheKey);

  Map<String, String> _headers({bool masked = false}) {
    final key = config.apiKey.trim();
    return {
      'Content-Type': 'application/json',
      'anthropic-version': apiVersion,
      if (key.isNotEmpty) 'x-api-key': masked ? RequestPreview.mask(key) : key,
      // Mirrors (Zhipu, DashScope, relays) document the key as a bearer
      // token; Anthropic's own host takes x-api-key alone.
      if (key.isNotEmpty && !_official)
        'Authorization': 'Bearer ${masked ? RequestPreview.mask(key) : key}',
    };
  }

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) async => AiResponse.fromChat(
    // No JSON parameter in this protocol: the prompt asks for JSON, and the
    // caller's parser is what holds the model to it.
    await chat(
      messages: [SystemMessage(systemPrompt), UserMessage(userPrompt)],
      tools: const [],
      cancelToken: cancelToken,
    ),
  );

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) async {
    final client = _client ?? cancelToken?.client ?? AiHttp.client;
    final key = _cacheKey;
    while (true) {
      final rejected = _learned.of(key).rejectedFields;
      final payload = _payload(messages, tools, rejected: rejected);
      final started = DateTime.now();
      void log({int? status, ChatResult? result, String? error}) =>
          ApiLog.instance.record(
            protocol: 'anthropic',
            model: config.model,
            url: _messagesUri,
            request: payload,
            status: status,
            response: result == null ? null : Sse.summarise(result),
            error: error,
            elapsed: DateTime.now().difference(started),
          );

      http.StreamedResponse res;
      try {
        res = await AiHttp.withRetry(
          () => client
              .send(
                http.Request('POST', _messagesUri)
                  ..headers.addAll(_headers())
                  ..body = jsonEncode(payload),
              )
              .timeout(firstEventTimeout),
          cancelToken: cancelToken,
          retryTimeouts: false,
        );
      } on AiCancelled {
        log(error: 'cancelled');
        rethrow;
      } on TimeoutException {
        if (cancelToken?.isCancelled ?? false) {
          log(error: 'cancelled');
          throw const AiCancelled();
        }
        final error = Sse.noResponse(firstEventTimeout);
        log(error: error);
        throw AiNetworkException(error);
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) {
          log(error: 'cancelled');
          throw const AiCancelled();
        }
        final error = AiHttp.describeTransportError(e);
        log(error: error);
        throw AiNetworkException(error);
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        String error;
        try {
          error = AiHttp.describeError(await http.Response.fromStream(res));
        } catch (_) {
          error = 'HTTP ${res.statusCode}';
        }
        log(status: res.statusCode, error: error);
        // An optional field this route refuses by name is dropped and
        // remembered — `top_k` on a mirror, `temperature` beside `top_p`.
        if (res.statusCode == 400 || res.statusCode == 422) {
          final detail = error.toLowerCase();
          final thinkingRefusal = _thinkingRefusal(
            // The model id is not the message: a relay's `…-thinking` model
            // named in an unrelated error must not read as a refusal.
            detail.replaceAll(config.model.toLowerCase(), ''),
            sent: _sentForm(payload),
            rejected: rejected,
            swap: !PlatformProfiles.messagesSwitchFor(config),
          );
          if (thinkingRefusal != null) {
            _learned.update(
              key,
              (b) => b.copyWith(
                rejectedFields: {...b.rejectedFields, ...thinkingRefusal},
              ),
            );
            continue;
          }
          final refused = _optional
              .where(
                (f) =>
                    payload.containsKey(f) &&
                    !rejected.contains(f) &&
                    detail.contains(f),
              )
              .firstOrNull;
          if (refused != null) {
            _learned.update(
              key,
              (b) => b.copyWith(rejectedFields: {...b.rejectedFields, refused}),
            );
            continue;
          }
        }
        throw AiHttp.statusError(res.statusCode, error, url: _messagesUri);
      }

      final ChatResult result;
      try {
        result = await _read(res, cancelToken);
      } on Object catch (e) {
        log(
          status: res.statusCode,
          error: (cancelToken?.isCancelled ?? false)
              ? 'cancelled'
              : AiHttp.describeFailure(e),
        );
        rethrow;
      }
      log(status: res.statusCode, result: result);
      return result;
    }
  }

  /// Whether a rejection refuses extended thinking itself — "does not
  /// support thinking", "thinking: Extra inputs are not permitted" — rather
  /// than only mentioning it. The budget error ("max_tokens must be greater
  /// than thinking.budget_tokens") is about the numbers, not the feature,
  /// and dropping thinking over it would switch reasoning off unasked.
  static bool refusesThinking(String detail) {
    if (!detail.contains('thinking')) return false;
    if (detail.contains('budget_tokens') && detail.contains('max_tokens')) {
      return false;
    }
    return RegExp(
      'not support|unsupported|extra inputs|not permitted|not allowed|'
      'unknown (field|parameter)|["\'`]thinking["\'`]',
    ).hasMatch(detail);
  }

  /// What to remember when a request that asked for thinking in [sent] is
  /// refused with [detail], or null when the refusal is not about thinking.
  ///
  /// A refused form is swapped for the other before thinking is given up:
  /// an older Claude answers `adaptive` with "thinking.type: Input tag
  /// 'adaptive' … does not match … 'disabled', 'enabled'", which names the
  /// field without refusing the feature, and dropping thinking over it would
  /// switch reasoning off for a month without a word. Only once the other
  /// form was refused too, and the message refuses thinking itself, is
  /// `thinking` recorded. A budget error is about the numbers, never the
  /// form, and is thrown as it is. So is an error about the thinking blocks
  /// in the conversation ("`thinking` or `redacted_thinking` blocks … cannot
  /// be modified", "messages.3.content.0: Invalid `signature` in `thinking`
  /// block"): the history is wrong, whichever form was asked for.
  ///
  /// A route declared as a switch has one form only ([swap] false).
  static Set<String>? _thinkingRefusal(
    String detail, {
    required MessagesThinking? sent,
    required Set<String> rejected,
    required bool swap,
  }) {
    if (sent == null || !detail.contains('thinking')) return null;
    if (detail.contains('budget_tokens') && detail.contains('max_tokens')) {
      return null;
    }
    if (RegExp(r'redacted_thinking|signature|messages\.\d').hasMatch(detail)) {
      return null;
    }
    if (swap && !rejected.contains(sent.other.refusedName)) {
      return {sent.refusedName};
    }
    return refusesThinking(detail) ? {sent.refusedName, 'thinking'} : null;
  }

  /// The form [payload] asked for thinking in, if it did.
  static MessagesThinking? _sentForm(Map<String, Object?> payload) =>
      switch (payload['thinking']) {
        {'type': final String type} =>
          MessagesThinking.values
              .where((form) => form.type == type)
              .firstOrNull,
        _ => null,
      };

  /// The form this route asks for thinking in: the model's own first, the
  /// other once that was refused, none once both were.
  ///
  /// A route declared as a switch asks adaptive only, the one form it takes.
  MessagesThinking? _form(Set<String> rejected) {
    if (!config.thinkingEnabled || rejected.contains('thinking')) return null;
    if (PlatformProfiles.messagesSwitchFor(config)) {
      const form = MessagesThinking.adaptive;
      return rejected.contains(form.refusedName) ? null : form;
    }
    final first = MessagesThinking.forModel(config.model);
    for (final form in [first, first.other]) {
      if (!rejected.contains(form.refusedName)) return form;
    }
    return null;
  }

  /// Sampling fields the adapter may leave out when a route refuses them;
  /// `thinking` has its own rules ([_thinkingRefusal]).
  static const _optional = ['temperature', 'top_p', 'top_k'];

  /// The request body — the one place it is built.
  Map<String, Object?> _payload(
    List<ChatMessage> messages,
    List<ToolDefinition> tools, {
    required Set<String> rejected,
  }) {
    final values = config.sampling.values;
    final form = _form(rejected);
    // Thinking needs room inside max_tokens — for extended, a budget of at
    // least 1024 with room left for the answer — so a smaller cap is raised.
    final thinking = form != null;
    final maxTokens = thinking
        ? math.max(config.maxOutputTokens ?? defaultMaxTokens, 2048)
        : (config.maxOutputTokens ?? defaultMaxTokens);
    final system = messages
        .whereType<SystemMessage>()
        .map((m) => m.content)
        .join('\n\n');
    final optional = <String, Object>{
      // Thinking, in either form, is sent with no sampling overrides.
      if (!thinking) 'temperature': ?values.temperature,
      if (!thinking) 'top_p': ?values.topP,
      if (!thinking) 'top_k': ?values.topK,
      // `display` only where it is documented: a mirror that has no such
      // field may refuse it, or ignore it and hide the summary regardless.
      if (form == MessagesThinking.adaptive)
        'thinking': {
          'type': 'adaptive',
          if (_official) 'display': 'summarized',
        },
      if (form == MessagesThinking.extended)
        'thinking': {
          'type': 'enabled',
          'budget_tokens': math.max(1024, maxTokens ~/ 2),
          if (_official) 'display': 'summarized',
        },
      // A route declared as a switch is told off in its own words (its
      // platform may think by default); elsewhere off is the protocol's
      // default and nothing is sent.
      if (!config.thinkingEnabled && PlatformProfiles.messagesSwitchFor(config))
        'thinking': const {'type': 'disabled'},
    }..removeWhere((k, _) => rejected.contains(k));
    return {
      'model': config.model,
      'max_tokens': maxTokens,
      if (system.isNotEmpty) 'system': system,
      ...optional,
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.parameters,
            },
        ],
      'stream': true,
      'messages': wire(messages, model: config.model),
    };
  }

  /// The conversation as Anthropic messages: alternating roles, tool results
  /// grouped into the user turn after their calls, consecutive turns of one
  /// role merged. Public for tests.
  static List<Map<String, Object?>> wire(
    List<ChatMessage> messages, {
    required String model,
  }) {
    final out = <Map<String, Object?>>[];
    void add(String role, List<Object?> blocks) {
      if (blocks.isEmpty) return;
      final last = out.lastOrNull;
      if (last != null && last['role'] == role) {
        (last['content'] as List<Object?>).addAll(blocks);
      } else {
        out.add({
          'role': role,
          'content': <Object?>[...blocks],
        });
      }
    }

    for (final message in messages) {
      switch (message) {
        case SystemMessage():
          break;
        // An empty text block is refused, so an empty message adds none.
        case UserMessage(:final content, :final images):
          add('user', [
            for (final image in images)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': image.mimeType,
                  'data': image.base64,
                },
              },
            if (content.isNotEmpty) {'type': 'text', 'text': content},
          ]);
        case AssistantMessage(:final content, :final toolCalls, :final raw):
          if (raw != null &&
              raw.protocol == AiProviderType.anthropic &&
              raw.model == model) {
            add('assistant', raw.parts);
          } else {
            add('assistant', [
              if (content.isNotEmpty) {'type': 'text', 'text': content},
              for (final call in toolCalls)
                {
                  'type': 'tool_use',
                  'id': call.id,
                  'name': call.name,
                  'input': call.decodedArguments ?? const <String, Object?>{},
                },
            ]);
          }
        case ToolResultMessage(:final toolCallId, :final content):
          add('user', [
            {
              'type': 'tool_result',
              'tool_use_id': toolCallId,
              'content': content,
            },
          ]);
      }
    }
    return out;
  }

  Future<ChatResult> _read(
    http.StreamedResponse res,
    AiCancelToken? cancelToken,
  ) async {
    final blocks = SplayTreeMap<int, _Block>();
    String? stopReason;
    final usage = <String, int>{};
    var stopped = false;

    // Mirrors differ in where they report usage — some only in
    // `message_delta`, with zeros at the start — so any non-zero bucket
    // wins wherever it arrives.
    void readUsage(Object? raw) {
      if (raw is! Map) return;
      for (final key in const [
        'input_tokens',
        'cache_creation_input_tokens',
        'cache_read_input_tokens',
        'output_tokens',
      ]) {
        final value = _int(raw[key]);
        if (value > 0) usage[key] = value;
      }
    }

    final read = await Sse.read(
      res,
      firstEventTimeout: firstEventTimeout,
      idleTimeout: idleTimeout,
      cancelToken: cancelToken,
      onEvent: (event) {
        switch (event['type']) {
          case 'error':
            final error = event['error'];
            final type = error is Map ? error['type'] : null;
            final message = error is Map ? error['message'] : error;
            // `overloaded_error` mid-stream: the request never finished, and
            // nothing was learned about the model.
            throw type == 'overloaded_error' || type == 'api_error'
                ? AiNetworkException('Model error: $message')
                : AiException('Model error: $message');
          case 'message_start':
            readUsage((event['message'] as Map?)?['usage']);
          case 'content_block_start':
            final block = event['content_block'];
            if (block is Map) {
              blocks[_int(event['index'])] = _Block(
                Map<String, Object?>.from(block),
              );
            }
          case 'content_block_delta':
            final block = blocks[_int(event['index'])];
            final delta = event['delta'];
            if (block != null && delta is Map) block.add(delta);
          case 'message_delta':
            final delta = event['delta'];
            if (delta is Map && delta['stop_reason'] is String) {
              stopReason = delta['stop_reason'] as String;
            }
            readUsage(event['usage']);
          case 'message_stop':
            stopped = true;
        }
      },
    );

    if (read.plain case final plain?) {
      return parseMessage(plain, model: config.model);
    }
    // A stream that ends without `message_stop` was cut off in transit; what
    // arrived is not the whole answer.
    if (!stopped) {
      throw const AiNetworkException(
        'The stream ended before the reply was complete.',
      );
    }
    return _result(
      [for (final block in blocks.values) block.finish()],
      stopReason: stopReason,
      promptTokens:
          (usage['input_tokens'] ?? 0) +
          (usage['cache_creation_input_tokens'] ?? 0) +
          (usage['cache_read_input_tokens'] ?? 0),
      completionTokens: usage['output_tokens'] ?? 0,
      model: config.model,
    );
  }

  /// A non-streamed `message` object (a relay that ignored `stream`).
  static ChatResult parseMessage(String body, {required String model}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const AiException('Empty response from model.');
    }
    if (json is! Map) throw const AiException('Empty response from model.');
    if (json['type'] == 'error' || json['error'] != null) {
      final error = json['error'];
      throw AiException(
        'Model error: ${error is Map ? error['message'] : error}',
      );
    }
    final content = json['content'];
    final usage = json['usage'];
    return _result(
      [
        if (content is List)
          for (final block in content.whereType<Map<dynamic, dynamic>>())
            Map<String, Object?>.from(block),
      ],
      stopReason: json['stop_reason'] as String?,
      promptTokens: usage is Map
          ? _int(usage['input_tokens']) +
                _int(usage['cache_creation_input_tokens']) +
                _int(usage['cache_read_input_tokens'])
          : 0,
      completionTokens: usage is Map ? _int(usage['output_tokens']) : 0,
      model: model,
    );
  }

  static ChatResult _result(
    List<Map<String, Object?>> blocks, {
    required String? stopReason,
    required int promptTokens,
    required int completionTokens,
    required String model,
  }) {
    switch (stopReason) {
      case 'refusal':
        throw AiException(
          'The model refused to answer ("$stopReason"). What arrived before '
          'it was discarded.',
        );
      case 'model_context_window_exceeded':
        throw const AiException(
          'The conversation no longer fits the model\'s context window. Set '
          'the context window in the AI settings to what the model really '
          'has, so older tool results are shortened in time.',
        );
      // Only server tools pause a turn, and this app sends none.
      case 'pause_turn':
        throw const AiNetworkException(
          'The server paused the turn ("pause_turn") unexpectedly.',
        );
    }
    if (blocks.isEmpty && stopReason == null) {
      throw const AiException('Empty response from model.');
    }
    final calls = <ToolCall>[
      for (final (index, block) in blocks.indexed)
        if (block['type'] == 'tool_use')
          ToolCall(
            id: block['id'] is String && (block['id'] as String).isNotEmpty
                ? block['id'] as String
                : 'call_$index',
            name: block['name'] is String ? block['name'] as String : '',
            arguments: jsonEncode(block['input'] ?? const <String, Object?>{}),
          ),
    ];
    final thought = blocks.any(
      (b) => b['type'] == 'thinking' || b['type'] == 'redacted_thinking',
    );
    return ChatResult(
      text: [
        for (final block in blocks)
          if (block['type'] == 'text' && block['text'] is String)
            block['text'] as String,
      ].join(),
      toolCalls: calls,
      // Thinking blocks must return with their signatures on a tool-use
      // turn, unchanged and to the same model.
      raw: calls.isEmpty
          ? null
          : ProviderTurn(
              protocol: AiProviderType.anthropic,
              model: model,
              // A tool input that arrived cut off goes back as `{}`: the
              // turn itself — with its thinking block, which a thinking
              // model requires at the head of every tool turn — must still
              // be sent back whole.
              parts: [
                for (final block in blocks)
                  if (block['type'] == 'tool_use' && block['input'] is! Map)
                    {...block, 'input': const <String, Object?>{}}
                  else
                    block,
              ],
            ),
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      // `end_turn` / `tool_use` / `stop_sequence` are ordinary ends; only
      // `max_tokens` means cut short, which [ChatResult.truncated] reads.
      finishReason: stopReason,
      reasoned: thought,
    );
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  @override
  Future<RequestPreview> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  }) async => RequestPreview(
    url: _messagesUri,
    headers: _headers(masked: true),
    body: _payload(messages, tools, rejected: learned.rejectedFields),
  );

  /// Anthropic reports no context size through the API.
  @override
  Future<ModelLimits> detectLimits() async => ModelLimits.unknown;

  @override
  Future<ServerKind> detectServerKind() async => ServerKind.unknown;
}

/// One content block assembled from stream deltas.
class _Block {
  final Map<String, Object?> _block;
  final _json = StringBuffer();

  _Block(this._block);

  void add(Map<dynamic, dynamic> delta) {
    switch (delta['type']) {
      case 'text_delta':
        _block['text'] = '${_block['text'] ?? ''}${delta['text'] ?? ''}';
      case 'input_json_delta':
        _json.write(delta['partial_json'] ?? '');
      case 'thinking_delta':
        _block['thinking'] =
            '${_block['thinking'] ?? ''}${delta['thinking'] ?? ''}';
      case 'signature_delta':
        _block['signature'] =
            '${_block['signature'] ?? ''}${delta['signature'] ?? ''}';
    }
  }

  /// The block as it goes back: a tool call's input decoded from its
  /// fragments (an empty `{}` when it had none — a tool with no arguments).
  Map<String, Object?> finish() {
    if (_block['type'] == 'tool_use' && _json.isNotEmpty) {
      try {
        _block['input'] = jsonDecode(_json.toString());
      } on FormatException {
        // Cut-off arguments: kept as text so the loop reports a bad call
        // rather than an empty one.
        _block['input'] = _json.toString();
      }
    }
    return _block;
  }
}
