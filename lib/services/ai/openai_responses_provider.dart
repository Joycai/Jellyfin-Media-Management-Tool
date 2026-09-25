import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';
import 'api_log.dart';
import 'learned_behaviour.dart';
import 'sse.dart';

/// Talks to the OpenAI Responses API (`/v1/responses`) — the only face of
/// some OpenAI and xAI models, and one relays mirror.
///
/// What the protocol asks for, and what goes wrong without it:
///
/// - `store: false` on every request, with the conversation sent in full:
///   nothing is kept server-side, so a request never depends on state the
///   app cannot see. Reasoning therefore travels back as the reasoning
///   items' `encrypted_content` (asked for through `include`), inside the
///   verbatim output items of the turn ([ProviderTurn]).
/// - `instructions` carries the system prompt on every request; it does not
///   persist between them.
/// - tools are declared with `strict: false`: strict mode rejects the loose
///   schemas the agent tools use.
/// - the stream is grouped by `output_index`, and the finished items of
///   `response.output_item.done` are the truth; deltas only show progress.
/// - `response.incomplete` says why: `max_output_tokens` is a cut-off
///   answer, `content_filter` a blocked one. A stream that ends with no
///   terminal event is an answer only when every item in it arrived whole
///   and it holds text or a call (a relay that drops the last event); it is
///   logged as `incomplete_stream`, with no finish reason.
class OpenAiResponsesProvider implements AiProvider {
  @override
  final AiConfig config;

  final http.Client? _client;
  final Duration firstEventTimeout;
  final Duration idleTimeout;

  OpenAiResponsesProvider(
    this.config, {
    http.Client? client,
    this.firstEventTimeout = const Duration(minutes: 10),
    this.idleTimeout = const Duration(minutes: 2),
  }) : _client = client;

  static LearnedStore get _learned => LearnedStore.instance;

  /// Like Chat Completions: `/v1` is added to a bare origin only.
  String get _base {
    var base = config.endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final path = Uri.tryParse(base)?.path ?? '';
    return path.isEmpty ? '$base/v1' : base;
  }

  Uri get _responsesUri => Uri.parse('$_base/responses');

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
      if (key.isNotEmpty)
        'Authorization': 'Bearer ${masked ? RequestPreview.mask(key) : key}',
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

  /// Optional fields, dropped and remembered when a route refuses them by
  /// name: sampling on a reasoning model, `include` on a model without
  /// encrypted reasoning, `reasoning` on one without any.
  static const _optional = [
    'temperature',
    'top_p',
    'reasoning',
    'include',
    'text',
  ];

  Future<ChatResult> _exchange({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    required bool jsonMode,
    AiCancelToken? cancelToken,
  }) async {
    final client = _client ?? cancelToken?.client ?? AiHttp.client;
    final key = _cacheKey;
    while (true) {
      final learned = _learned.of(key);
      final rejected = learned.rejectedFields;
      final payload = _payload(
        messages,
        tools,
        jsonMode: jsonMode,
        rejected: rejected,
        offRefused: learned.thinkingOffTried.contains(
          LearnedBehaviour.effortNone,
        ),
      );
      final started = DateTime.now();
      void log({
        int? status,
        ChatResult? result,
        String? error,
        bool incomplete = false,
      }) => ApiLog.instance.record(
        protocol: 'responses',
        model: config.model,
        url: _responsesUri,
        request: payload,
        status: status,
        response: result == null
            ? null
            : {
                ...Sse.summarise(result),
                if (incomplete) 'incomplete_stream': true,
              },
        error: error,
        elapsed: DateTime.now().difference(started),
      );

      http.StreamedResponse res;
      try {
        res = await AiHttp.withRetry(
          () => client
              .send(
                http.Request('POST', _responsesUri)
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
        String? param;
        try {
          final body = await http.Response.fromStream(res);
          error = AiHttp.describeError(body);
          param = AiHttp.errorParam(body);
        } catch (_) {
          error = 'HTTP ${res.statusCode}';
        }
        log(status: res.statusCode, error: error);
        if (res.statusCode == 400 || res.statusCode == 422) {
          final detail = error.toLowerCase();
          // `error.param` first: it names the field even when the message
          // does not. The message is the fallback for servers without it.
          final candidates = _optional.where(
            (f) => payload.containsKey(f) && !rejected.contains(f),
          );
          // `reasoning.encrypted_content` is the value `include` asks for,
          // not a path inside `reasoning` — as in [_names].
          if (param != null &&
              param.startsWith('reasoning.encrypted_content')) {
            param = 'include';
          }
          final refused =
              candidates
                  .where((f) => AiHttp.paramNames(param, f))
                  .firstOrNull ??
              candidates.where((f) => _names(detail, f)).firstOrNull;
          // `reasoning` refused while asking for none says nothing about
          // asking for some: the route goes back to the model's default
          // when off, and still asks when on.
          if (refused == 'reasoning' && !config.thinkingEnabled) {
            _learned.update(
              key,
              (b) => b.copyWith(
                thinkingOffTried: {
                  ...b.thinkingOffTried,
                  LearnedBehaviour.effortNone,
                },
              ),
            );
            continue;
          }
          if (refused != null) {
            _learned.update(
              key,
              (b) => b.copyWith(rejectedFields: {...b.rejectedFields, refused}),
            );
            continue;
          }
        }
        throw AiHttp.statusError(res.statusCode, error, url: _responsesUri);
      }

      final ({ChatResult result, bool incomplete}) read;
      try {
        read = await _read(res, cancelToken);
      } on Object catch (e) {
        log(
          status: res.statusCode,
          error: (cancelToken?.isCancelled ?? false)
              ? 'cancelled'
              : AiHttp.describeFailure(e),
        );
        rethrow;
      }
      log(
        status: res.statusCode,
        result: read.result,
        incomplete: read.incomplete,
      );
      return read.result;
    }
  }

  /// Whether a rejection names [field]. `text`, `reasoning` and `include`
  /// are ordinary words, so they count only quoted or as a parameter path.
  /// `reasoning.encrypted_content` is the value `include` asks for, so it
  /// names `include`, never `reasoning`.
  static bool _names(String detail, String field) {
    const encrypted = 'reasoning.encrypted_content';
    if (field == 'include' && detail.contains(encrypted)) return true;
    final text = field == 'reasoning'
        ? detail.replaceAll(encrypted, '')
        : detail;
    return field == 'text' || field == 'reasoning' || field == 'include'
        ? RegExp(
            '["\'`]$field["\'`.\\[]|$field\\.(format|effort)|'
            '$field (field|parameter)',
          ).hasMatch(text)
        : text.contains(field);
  }

  /// The request body — the one place it is built.
  Map<String, Object?> _payload(
    List<ChatMessage> messages,
    List<ToolDefinition> tools, {
    required bool jsonMode,
    required Set<String> rejected,
    required bool offRefused,
  }) {
    final values = config.sampling.values;
    final instructions = messages
        .whereType<SystemMessage>()
        .map((m) => m.content)
        .join('\n\n');
    final optional = <String, Object>{
      'temperature': ?values.temperature,
      'top_p': ?values.topP,
      // Off is asked for, not left to the model's default — that is medium
      // on GPT-5.5/5.6 and high on Grok, paid for either way (KB 03 §7.1). A
      // route that refuses `none` is remembered and left at its default; a
      // relay that quietly rewrites it shows up as reasoning in the
      // connection test.
      if (config.thinkingEnabled)
        'reasoning': const {'effort': 'medium'}
      else if (!offRefused)
        'reasoning': const {'effort': 'none'},
      'include': const ['reasoning.encrypted_content'],
      if (jsonMode)
        'text': const {
          'format': {'type': 'json_object'},
        },
    }..removeWhere((k, _) => rejected.contains(k));
    return {
      'model': config.model,
      // Always present, empty when there is no system message: a relay that
      // finds `instructions` missing injects its own system prompt, 4.4K to
      // 9K tokens on every request (KB 02 §7.1, 01 §9.2).
      'instructions': instructions,
      'store': false,
      ...optional,
      'max_output_tokens': ?config.maxOutputTokens,
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            {
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parameters,
              'strict': false,
            },
        ],
      'stream': true,
      'input': input(messages, model: config.model),
    };
  }

  /// The conversation as Responses input items. Public for tests.
  static List<Map<String, Object?>> input(
    List<ChatMessage> messages, {
    required String model,
  }) => [
    for (final message in messages)
      ...switch (message) {
        SystemMessage() => const <Map<String, Object?>>[],
        UserMessage(:final content, :final images) when images.isEmpty => [
          {'role': 'user', 'content': content},
        ],
        UserMessage(:final content, :final images) => [
          {
            'role': 'user',
            'content': [
              if (content.isNotEmpty) {'type': 'input_text', 'text': content},
              for (final image in images)
                {
                  'type': 'input_image',
                  'image_url': image.dataUrl,
                  'detail': 'auto',
                },
            ],
          },
        ],
        // With store:false a reasoning item is only valid with its
        // encrypted content; one without (a relay that ignored `include`,
        // or `include` refused) names an id the server never kept, and would
        // fail every later request.
        AssistantMessage(:final raw?)
            when raw.fits(AiProviderType.openAiResponses, model) =>
          [
            for (final part in raw.parts)
              if (part case final Map<dynamic, dynamic> item)
                if (item['type'] != 'reasoning' ||
                    item['encrypted_content'] != null)
                  Map<String, Object?>.from(item),
          ],
        AssistantMessage(:final content, :final toolCalls) => [
          if (content.isNotEmpty) {'role': 'assistant', 'content': content},
          for (final call in toolCalls)
            {
              'type': 'function_call',
              'call_id': call.id,
              'name': call.name,
              'arguments': call.arguments,
            },
        ],
        ToolResultMessage(:final toolCallId, :final content) => [
          {
            'type': 'function_call_output',
            'call_id': toolCallId,
            'output': content,
          },
        ],
      },
  ];

  Future<({ChatResult result, bool incomplete})> _read(
    http.StreamedResponse res,
    AiCancelToken? cancelToken,
  ) async {
    final items = SplayTreeMap<int, Map<String, Object?>>();
    // Every item the stream began — an `output_item.added`, a delta — so
    // one cut off before its `output_item.done` is noticed.
    final begun = <int>{};
    Map<dynamic, dynamic>? terminal;
    final read = await Sse.read(
      res,
      firstEventTimeout: firstEventTimeout,
      idleTimeout: idleTimeout,
      cancelToken: cancelToken,
      onEvent: (event) {
        if (event['output_index'] case final num index) {
          begun.add(index.toInt());
        }
        switch (event['type']) {
          case 'error':
            throw streamError(event);
          case 'response.output_item.done':
            final item = event['item'];
            if (item is Map) {
              items[(event['output_index'] as num?)?.toInt() ?? items.length] =
                  Map<String, Object?>.from(item);
            }
          case 'response.completed' ||
              'response.incomplete' ||
              'response.failed':
            terminal = event['response'] is Map
                ? event['response'] as Map
                : event;
        }
      },
    );

    if (read.plain case final plain?) {
      final Object? json;
      try {
        json = jsonDecode(plain);
      } on FormatException {
        throw const AiException('Empty response from model.');
      }
      if (json is! Map) throw const AiException('Empty response from model.');
      return (
        result: parseResponse(json, model: config.model),
        incomplete: false,
      );
    }
    final end = terminal;
    if (end == null) {
      // No terminal event: a relay that drops the last one, or a stream cut
      // off. It stands as an answer when every item it began arrived as a
      // finished `output_item.done`, nothing was skipped, and it holds text
      // or a call; a stream cut mid-item — a call after a finished message
      // included — still fails. Cut exactly between two items it reads as
      // complete — the price of taking these relays at all.
      if (read.skipped > 0 ||
          !begun.every(items.containsKey) ||
          !items.values.any(_answers)) {
        throw const AiNetworkException(
          'The stream ended before the reply was complete.',
        );
      }
      return (
        result: parseResponse({
          'output': items.values.toList(),
        }, model: config.model),
        incomplete: true,
      );
    }
    // The finished items streamed in order win over the copy in the
    // terminal event, which some servers leave empty — unless an event was
    // skipped, which may have been one of them: then only the terminal
    // event's own copy is whole.
    final List<Object?>? output;
    if (read.skipped == 0) {
      output = items.isEmpty ? null : items.values.toList();
    } else if (end['output'] case final List<Object?> whole
        when whole.isNotEmpty) {
      output = whole;
    } else {
      throw Sse.malformed;
    }
    return (
      result: parseResponse({...end, 'output': ?output}, model: config.model),
      incomplete: false,
    );
  }

  /// Whether a finished output item is part of an answer: a message with
  /// text or a refusal (which [parseResponse] then reports), or a function
  /// call.
  static bool _answers(Map<String, Object?> item) => switch (item['type']) {
    'function_call' => true,
    'message' => switch (item['content']) {
      final List<dynamic> parts => parts.any(
        (part) =>
            part is Map &&
            (part['type'] == 'refusal' ||
                (part['text'] is String && part['text'] != '')),
      ),
      _ => false,
    },
    _ => false,
  };

  /// An `error` event mid-stream. The request was accepted, so this is the
  /// server's failure — unless it names the request as the problem. Public
  /// for tests.
  static AiException streamError(Map<dynamic, dynamic> event) {
    final code = '${event['code'] ?? ''}';
    final message = 'Model error: ${event['message'] ?? event}';
    return code.startsWith('invalid') || event['param'] != null
        ? AiException(message)
        : AiNetworkException(message);
  }

  /// One finished response object. Public for tests.
  static ChatResult parseResponse(
    Map<dynamic, dynamic> json, {
    required String model,
  }) {
    final error = json['error'];
    final status = json['status'];
    // `response.failed` always carries `error` too; it is the server's
    // failure, which settles nothing about the model.
    if (status == 'failed') {
      throw AiNetworkException(
        error is Map && error['message'] is String
            ? 'The response failed on the server: ${error['message']}'
            : 'The response failed on the server.',
      );
    }
    if (error != null) {
      throw AiException(
        'Model error: ${error is Map ? error['message'] : error}',
      );
    }
    String? finishReason = status is String ? status : null;
    if (status == 'incomplete') {
      final details = json['incomplete_details'];
      final reason = details is Map ? details['reason'] : null;
      if (reason == 'content_filter') {
        throw const AiException(
          'The provider\'s content filter stopped the reply '
          '("content_filter"). What arrived before it was discarded.',
        );
      }
      // `max_output_tokens`: a real answer, cut short.
      finishReason = reason == 'max_output_tokens'
          ? 'length'
          : reason?.toString();
    }

    final output = [
      if (json['output'] case final List<dynamic> list)
        for (final item in list.whereType<Map<dynamic, dynamic>>())
          Map<String, Object?>.from(item),
    ];
    if (output.isEmpty && finishReason == null) {
      throw const AiException('Empty response from model.');
    }

    final text = StringBuffer();
    final calls = <ToolCall>[];
    var reasoned = false;
    for (final (index, item) in output.indexed) {
      switch (item['type']) {
        case 'message':
          if (item['content'] case final List<dynamic> parts) {
            for (final part in parts.whereType<Map<dynamic, dynamic>>()) {
              if (part['type'] == 'refusal') {
                throw AiException(
                  'The model refused to answer: ${part['refusal']}',
                );
              }
              if (part['text'] case final String piece) text.write(piece);
            }
          }
        case 'function_call':
          calls.add(
            ToolCall(
              id: item['call_id'] is String
                  ? item['call_id'] as String
                  : 'call_$index',
              name: item['name'] is String ? item['name'] as String : '',
              arguments: item['arguments'] is String
                  ? item['arguments'] as String
                  : jsonEncode(item['arguments'] ?? const {}),
            ),
          );
        case 'reasoning':
          reasoned = true;
      }
    }

    final usage = json['usage'];
    final details = usage is Map ? usage['output_tokens_details'] : null;
    int count(Object? v) => v is num ? v.toInt() : 0;
    return ChatResult(
      text: text.toString(),
      toolCalls: calls,
      // Every output item — reasoning with its encrypted content, the text,
      // the calls — goes back verbatim, to this model only.
      raw: calls.isEmpty
          ? null
          : ProviderTurn(
              protocol: AiProviderType.openAiResponses,
              model: model,
              parts: output,
            ),
      promptTokens: usage is Map ? count(usage['input_tokens']) : 0,
      completionTokens: usage is Map ? count(usage['output_tokens']) : 0,
      finishReason: finishReason,
      reasoned:
          reasoned ||
          (details is Map && count(details['reasoning_tokens']) > 0),
    );
  }

  @override
  Future<RequestPreview> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  }) async => RequestPreview(
    url: _responsesUri,
    headers: _headers(masked: true),
    body: _payload(
      messages,
      tools,
      jsonMode: false,
      rejected: learned.rejectedFields,
      offRefused: learned.thinkingOffTried.contains(
        LearnedBehaviour.effortNone,
      ),
    ),
  );

  @override
  Future<ModelLimits> detectLimits() async => ModelLimits.unknown;

  @override
  Future<ServerKind> detectServerKind() async => ServerKind.unknown;
}
