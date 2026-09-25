import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';
import 'api_log.dart';
import 'learned_behaviour.dart';
import 'sse.dart';

/// A way of asking Gemini for no reasoning, in the order they are tried.
///
/// The field is generation-specific and the wrong one is a 400, so the ladder
/// is walked by rejection like [OpenAiProvider]'s — and, like it, also by
/// whether the reply still reasoned, because a relay that does not implement
/// `thinkingConfig` drops it silently rather than refusing it.
enum _ThinkingOff {
  /// `thinkingConfig.thinkingBudget = 0`, which turns thinking off on 2.5
  /// Flash and Flash-Lite. 2.5 Pro cannot go below its minimum and rejects it.
  budgetZero,

  /// `thinkingConfig.thinkingLevel = "low"`, Gemini 3's replacement for the
  /// budget. Its floor is "low": that generation cannot stop thinking at all.
  levelLow,
}

/// Talks to the Google Generative Language REST API
/// (`:streamGenerateContent?alt=sse`).
///
/// **Why a stream.** A whole tool-calling turn, not a greeting: a thinking
/// model working through an organize batch regularly spends minutes. The
/// request used to be one `generateContent` with a 10-minute budget for the
/// whole reply, which cut off a long generation the server was still running
/// — and billing for — and made a hung connection wait out the full ten
/// minutes. A stream is timed on silence instead, like [OpenAiProvider]:
/// [firstEventTimeout] until the first event, [idleTimeout] for any gap after
/// it. Closing the stream, on timeout or cancel, is what stops the
/// generation. A timeout is never retried.
///
/// Each streamed event is a complete `GenerateContentResponse` holding the
/// parts produced since the last one; they are appended, never merged as
/// deltas. A relay that ignores `alt=sse` and answers with one JSON object,
/// or a JSON array of them, is read the same way.
class GoogleGenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  /// Replaces the transport in tests; see [OpenAiProvider].
  final http.Client? _client;

  /// How long to wait for the first streamed event: loading and reading the
  /// prompt, plus any thinking before the first part.
  final Duration firstEventTimeout;

  /// How long the stream may fall silent once it has started.
  final Duration idleTimeout;

  GoogleGenAiProvider(
    this.config, {
    http.Client? client,
    this.firstEventTimeout = const Duration(minutes: 10),
    this.idleTimeout = const Duration(minutes: 2),
  }) : _client = client;

  /// Which [_ThinkingOff] way each route is on, kept across launches — see
  /// [LearnedStore]. Keyed by the credential as well as the URL and model:
  /// two profiles can point at one endpoint through different keys, and what
  /// one was refused says nothing about the other. Only the key's hash is
  /// used, so this holds no secret.
  String get _cacheKey => LearnedStore.routeKey(
    protocol: config.provider.id,
    base: _base,
    model: config.model,
    apiKey: config.apiKey,
  );

  static LearnedStore get _learned => LearnedStore.instance;

  @override
  void forgetLearned() => _learned.forget(_cacheKey);

  @override
  LearnedBehaviour get learned => _learned.of(_cacheKey);

  /// Normalized base URL with a `/v1*` segment, e.g.
  /// `https://generativelanguage.googleapis.com/v1beta`.
  ///
  /// A pasted `…/v1beta/models` or a full
  /// `…/models/<model>:generateContent` is cut back to its root first — a
  /// path segment only, never a host named `models`.
  String get _base {
    var base = AiHttp.endpointBase(
      config.endpoint,
    ).replaceFirst(RegExp(r'(?<=[^/])/models(/[^/]*)?$'), '');
    if (!base.contains('/v1')) {
      base = '$base/v1beta';
    }
    return base;
  }

  /// The key travels in `x-goog-api-key`, never as `?key=`. A query string
  /// ends up in every relay's, proxy's and packet capture's access log, and in
  /// any error that quotes the request URL.
  Map<String, String> get _headers {
    final key = config.apiKey.trim();
    return {
      'Content-Type': 'application/json',
      if (key.isNotEmpty) 'x-goog-api-key': key,
    };
  }

  Uri _generateUri() =>
      Uri.parse('$_base/models/${config.model}:streamGenerateContent?alt=sse');

  Uri _modelUri() => Uri.parse('$_base/models/${config.model}');

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) async => AiResponse.fromChat(
    await _generate(
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
  }) => _generate(
    messages: messages,
    tools: tools,
    jsonMode: false,
    cancelToken: cancelToken,
  );

  Future<ChatResult> _generate({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    required bool jsonMode,
    AiCancelToken? cancelToken,
  }) async {
    // A cancellable call goes through the token's own client so cancelling can
    // close the socket; otherwise reuse the shared pooled client.
    final client = _client ?? cancelToken?.client ?? AiHttp.client;

    while (true) {
      final key = _cacheKey;
      final tried = _learned.of(key).thinkingOffTried;
      final off = config.thinkingEnabled
          ? null
          : _ThinkingOff.values
                .where((w) => !tried.contains(w.name))
                .firstOrNull;
      void offFailed() => _learned.update(
        key,
        (b) => b.copyWith(thinkingOffTried: {...b.thinkingOffTried, off!.name}),
      );

      final payload = _payload(messages, tools, jsonMode: jsonMode, off: off);
      final body = jsonEncode(payload);
      final started = DateTime.now();
      void log({int? status, ChatResult? result, String? error}) =>
          ApiLog.instance.record(
            protocol: 'gemini',
            model: config.model,
            url: _generateUri(),
            request: payload,
            status: status,
            response: result == null
                ? null
                : {
                    'finish_reason': result.finishReason,
                    'text': result.text,
                    if (result.toolCalls.isNotEmpty)
                      'tool_calls': [
                        for (final call in result.toolCalls)
                          {'name': call.name, 'arguments': call.arguments},
                      ],
                    if (result.reasoned) 'reasoned': true,
                    'usage': {
                      'prompt': result.promptTokens,
                      'completion': result.completionTokens,
                    },
                  },
            error: error,
            elapsed: DateTime.now().difference(started),
          );

      http.StreamedResponse res;
      try {
        res = await AiHttp.withRetry(
          () => client
              .send(
                http.Request('POST', _generateUri())
                  ..headers.addAll(_headers)
                  ..body = body,
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
        final error = _noResponse(firstEventTimeout);
        log(error: error);
        throw AiNetworkException(error);
      } catch (e) {
        // Closing the client to cancel surfaces as a generic ClientException;
        // report it as a cancellation, not a network failure.
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
        // This way of asking for no reasoning is not this model's; try the
        // next. Checked before throwing, exactly as the OpenAI provider does.
        if ((res.statusCode == 400 || res.statusCode == 422) &&
            off != null &&
            _namesThinking(error.toLowerCase())) {
          offFailed();
          continue;
        }
        throw AiHttp.statusError(res.statusCode, error, url: _generateUri());
      }

      final ChatResult result;
      try {
        final read = await _events(res, cancelToken);
        result = _merge(
          read.events,
          model: config.model,
          streamed: read.streamed,
        );
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
      if (off == null || !result.reasoned) return result;
      // `levelLow` is the least Gemini 3 thinks, never none: still reasoning
      // is what it does, not a sign it was ignored. Dropping it would send
      // no thinkingConfig at all and run at the default, highest level.
      if (off == _ThinkingOff.levelLow) return result;
      // Accepted and ignored — a relay that does not implement thinkingConfig
      // drops it silently. The next request tries the next way.
      offFailed();
      return result.withThinkingOffPending(
        _ThinkingOff.values.any((w) => w != off && !tried.contains(w.name)),
      );
    }
  }

  /// The request body for one attempt — the one place it is built, so the
  /// settings preview shows exactly what a task sends. Keys stay camelCase:
  /// a relay that forwards the body verbatim passes snake_case through to a
  /// Gemini that ignores it.
  Map<String, Object?> _payload(
    List<ChatMessage> messages,
    List<ToolDefinition> tools, {
    required bool jsonMode,
    required _ThinkingOff? off,
  }) {
    final sampling = config.sampling.values;
    final system = messages
        .whereType<SystemMessage>()
        .map((m) => m.content)
        .join('\n\n');
    return {
      if (system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'contents': contents(messages, model: config.model),
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final tool in tools)
                {
                  'name': tool.name,
                  'description': tool.description,
                  'parameters': tool.parameters,
                },
            ],
          },
        ],
      'generationConfig': {
        'temperature': ?sampling.temperature,
        'topP': ?sampling.topP,
        'topK': ?sampling.topK,
        'presencePenalty': ?sampling.presencePenalty,
        if (jsonMode) 'responseMimeType': 'application/json',
        'maxOutputTokens': ?config.maxOutputTokens,
        if (off == _ThinkingOff.budgetZero)
          'thinkingConfig': const {'thinkingBudget': 0},
        if (off == _ThinkingOff.levelLow)
          'thinkingConfig': const {'thinkingLevel': 'low'},
      },
    };
  }

  @override
  Future<RequestPreview> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    final tried = _learned.of(_cacheKey).thinkingOffTried;
    final off = config.thinkingEnabled
        ? null
        : _ThinkingOff.values.where((w) => !tried.contains(w.name)).firstOrNull;
    final key = config.apiKey.trim();
    return RequestPreview(
      url: _generateUri(),
      headers: {
        'Content-Type': 'application/json',
        if (key.isNotEmpty) 'x-goog-api-key': RequestPreview.mask(key),
      },
      body: _payload(messages, tools, jsonMode: false, off: off),
    );
  }

  static bool _namesThinking(String detail) =>
      detail.contains('thinking') ||
      detail.contains('thinkingconfig') ||
      detail.contains('thinking_config') ||
      detail.contains('thinking_budget') ||
      detail.contains('thinking_level');

  static String _noResponse(Duration timeout) =>
      'No response from the server within ${_duration(timeout)}.';

  static String _duration(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  /// Reads every response object the server sent: one per `data:` event, or
  /// — from a relay that ignored `alt=sse` — the whole body as one object or
  /// an array of them. Times out on silence, as the class explains.
  ///
  /// A skipped event fails the read: each one carries parts of the answer
  /// (or its finish reason), and the reply would read as whole without it.
  Future<({List<Map<dynamic, dynamic>> events, bool streamed})> _events(
    http.StreamedResponse res,
    AiCancelToken? cancelToken,
  ) async {
    final read = await Sse.read(
      res,
      firstEventTimeout: firstEventTimeout,
      idleTimeout: idleTimeout,
      cancelToken: cancelToken,
    );
    if (read.skipped > 0) throw Sse.malformed;
    final events = [...read.events];
    if (read.plain case final plain? when plain.trim().isNotEmpty) {
      final Object? body;
      try {
        body = jsonDecode(plain);
      } on FormatException {
        throw const AiException('Empty response from model.');
      }
      if (body is Map) events.add(body);
      if (body is List) events.addAll(body.whereType<Map<dynamic, dynamic>>());
    }
    return (events: events, streamed: read.plain == null);
  }

  /// Folds the streamed responses into one [ChatResult].
  ///
  /// A blocked request and a blocked answer are both failures, not empty
  /// replies. Gemini reports the first as `promptFeedback.blockReason` and the
  /// second as a `finishReason` other than `STOP`, in both cases with HTTP 200
  /// and often after some text — so returning what arrived would hand the
  /// caller a partial answer it cannot tell from a complete one, and the agent
  /// loop would read the silence as "the model stopped calling tools".
  static ChatResult _merge(
    List<Map<dynamic, dynamic>> events, {
    required String model,
    bool streamed = false,
  }) {
    final rawParts = <Object?>[];
    String? finishReason;
    Map<dynamic, dynamic>? usage;
    var sawCandidate = false;
    for (final event in events) {
      if (event['error'] case final Object error) {
        final message = error is Map ? error['message'] : error;
        throw AiException('Model error: $message');
      }
      if (event['promptFeedback'] case final Map<dynamic, dynamic> feedback) {
        if (feedback['blockReason'] case final String reason) {
          throw AiException('The request was blocked by Google: $reason.');
        }
      }
      if (event['usageMetadata'] case final Map<dynamic, dynamic> u) {
        usage = u;
      }
      final candidates = event['candidates'];
      if (candidates is! List ||
          candidates.isEmpty ||
          candidates.first is! Map) {
        continue;
      }
      sawCandidate = true;
      final candidate = candidates.first as Map;
      final content = candidate['content'];
      if (content is Map && content['parts'] is List) {
        rawParts.addAll(content['parts'] as List);
      }
      if (candidate['finishReason'] case final String reason) {
        finishReason = reason;
      }
    }
    if (!sawCandidate) throw const AiException('Empty response from model.');
    // Gemini's last streamed chunk always carries the finish reason. A
    // stream closed without one was cut off, and what arrived is not the
    // whole answer. (A relay answering with one JSON object may omit it.)
    if (streamed && finishReason == null) {
      throw const AiNetworkException(
        'The stream ended before the reply was complete.',
      );
    }

    final parts = rawParts.whereType<Map<dynamic, dynamic>>().toList();
    final toolCalls = <ToolCall>[
      for (final (index, part) in parts.indexed)
        if (part['functionCall'] case final Map<dynamic, dynamic> call)
          ToolCall(
            id: call['id'] is String ? call['id'] as String : 'call_$index',
            name: call['name'] is String ? call['name'] as String : '',
            arguments: jsonEncode(call['args'] ?? const <String, Object?>{}),
          ),
    ];

    _throwOnFailedFinish(finishReason);

    int count(String key) => (usage?[key] as num?)?.toInt() ?? 0;
    // Thinking is billed on top of the answer and Google reports it beside
    // `candidatesTokenCount`, never inside it. Reading only the latter
    // under-reports the most expensive part of a reasoning run.
    final completionTokens =
        count('candidatesTokenCount') + count('thoughtsTokenCount');

    return ChatResult(
      // Thought parts are reasoning, not the answer.
      text: parts
          .where((p) => p['thought'] != true && p['text'] is String)
          .map((p) => p['text'] as String)
          .join(),
      toolCalls: toolCalls,
      // Sent back verbatim: function-call parts can carry thought signatures.
      raw: toolCalls.isEmpty
          ? null
          : ProviderTurn(
              protocol: AiProviderType.googleGenAi,
              model: model,
              parts: rawParts,
            ),
      promptTokens: count('promptTokenCount'),
      completionTokens: completionTokens,
      finishReason: finishReason,
      reasoned:
          parts.any((p) => p['thought'] == true) ||
          count('thoughtsTokenCount') > 0,
    );
  }

  /// Only `STOP` and `MAX_TOKENS` are an answer; every other finish reason
  /// throws.
  ///
  /// The check is an allow-list because the failures keep growing and all of
  /// them arrive with HTTP 200: besides the content-safety set, Gemini ends a
  /// turn with `MISSING_THOUGHT_SIGNATURE`, `UNEXPECTED_TOOL_CALL`,
  /// `TOO_MANY_TOOL_CALLS`, `MALFORMED_RESPONSE` or `OTHER`. Read as a short
  /// reply, any of them looks to the agent loop like a model that stopped
  /// calling tools. `MAX_TOKENS` is a real answer cut short, which
  /// [ChatResult.truncated] reports. A missing reason is checked by the
  /// caller: fine in one JSON object, a cut-off in a stream.
  static void _throwOnFailedFinish(String? finishReason) {
    switch (finishReason?.toUpperCase()) {
      case null || 'STOP' || 'MAX_TOKENS' || 'FINISH_REASON_UNSPECIFIED':
        return;
      // The request is what was wrong here, not the model or the files: a
      // thought signature from an earlier turn did not come back intact.
      case 'MISSING_THOUGHT_SIGNATURE':
        throw AiNetworkException(
          'Gemini rejected the conversation ("$finishReason"): a reasoning '
          'signature from an earlier turn was not sent back. This is a '
          'request the app built wrongly, not a problem with your files.',
        );
      // Says nothing settled about the model — `OTHER` is Google's own
      // catch-all, and a model that over- or mis-calls tools does call them —
      // so the tool probe must read these as inconclusive, not as "no tools".
      case 'OTHER' ||
          'MALFORMED_RESPONSE' ||
          'UNEXPECTED_TOOL_CALL' ||
          'TOO_MANY_TOOL_CALLS':
        throw AiNetworkException(
          'The model stopped with "$finishReason" and its answer was '
          'discarded.',
        );
      default:
        throw AiException(
          'The model stopped with "$finishReason" and its answer was '
          'discarded.',
        );
    }
  }

  /// Converts the conversation to Gemini `contents`.
  ///
  /// System messages travel separately as `systemInstruction`. A round's tool
  /// results go back as one user turn of `functionResponse` parts, matching the
  /// single model turn whose calls they answer.
  /// A turn from another protocol or model is rebuilt from its text and
  /// calls; [model] null accepts any Gemini turn (tests).
  static List<Map<String, Object?>> contents(
    List<ChatMessage> messages, {
    String? model,
  }) {
    final out = <Map<String, Object?>>[];
    for (final message in messages) {
      switch (message) {
        case SystemMessage():
          break;
        case UserMessage(:final content, :final images):
          out.add({
            'role': 'user',
            'parts': [
              {'text': content},
              for (final image in images)
                {
                  'inlineData': {
                    'mimeType': image.mimeType,
                    'data': image.base64,
                  },
                },
            ],
          });
        case AssistantMessage(:final content, :final toolCalls, :final raw):
          out.add({
            'role': 'model',
            'parts':
                raw != null &&
                    raw.fits(AiProviderType.googleGenAi, model ?? raw.model)
                ? raw.parts
                : [
                    if (content.isNotEmpty) {'text': content},
                    for (final call in toolCalls)
                      {
                        'functionCall': {
                          'name': call.name,
                          'args': call.decodedArguments ?? const {},
                        },
                      },
                  ],
          });
        case ToolResultMessage(:final name, :final content):
          final part = {
            'functionResponse': {
              'name': name,
              'response': {'content': content},
            },
          };
          final last = out.lastOrNull;
          final lastParts = last?['parts'];
          if (last != null &&
              last['role'] == 'user' &&
              lastParts is List &&
              lastParts.every(
                (p) => p is Map && p.containsKey('functionResponse'),
              )) {
            lastParts.add(part);
          } else {
            out.add({
              'role': 'user',
              'parts': <Object?>[part],
            });
          }
      }
    }
    return out;
  }

  /// `GET models/{model}` reports the input and output limits the API itself
  /// enforces.
  @override
  Future<ModelLimits> detectLimits() async {
    try {
      final res = await (_client ?? AiHttp.client)
          .get(_modelUri(), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return ModelLimits.unknown;
      }
      return ModelLimits.fromGoogleModel(
            jsonDecode(utf8.decode(res.bodyBytes)),
          ) ??
          ModelLimits.unknown;
    } catch (_) {
      return ModelLimits.unknown;
    }
  }

  /// Google's API is not one of the self-hosted servers [ServerKind] tells
  /// apart.
  @override
  Future<ServerKind> detectServerKind() async => ServerKind.unknown;
}
