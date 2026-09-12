import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';

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

/// Talks to the Google Generative Language REST API (`:generateContent`).
class GoogleGenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  /// Replaces the transport in tests; see [OpenAiProvider].
  final http.Client? _client;

  /// How long one generation may take.
  ///
  /// A whole tool-calling turn, not a greeting: a thinking model working
  /// through an organize batch regularly spends minutes. A timeout is never
  /// retried — `Future.timeout` does not close the socket, so the request the
  /// server is still working on keeps running and a retry would start a second
  /// one beside it and bill for both.
  final Duration timeout;

  GoogleGenAiProvider(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(minutes: 10),
  }) : _client = client;

  /// Which [_ThinkingOff] way each endpoint + model is on. Process-wide, so
  /// only the first request of a session pays for a rejection.
  static final Map<String, int> _thinkingOffAttempts = {};

  /// Keyed by the credential as well as the URL and model: two profiles can
  /// point at one endpoint through different keys, and what one was refused
  /// says nothing about the other. Only the key's hash is used, so this holds
  /// no secret.
  String get _cacheKey =>
      '$_base|${config.model}|${config.apiKey.trim().hashCode}';

  /// Normalized base URL with a `/v1*` segment, e.g.
  /// `https://generativelanguage.googleapis.com/v1beta`.
  String get _base {
    var base = config.endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.contains('/v1')) {
      base = '$base/v1beta';
    }
    return base;
  }

  String get _keyQuery {
    final key = config.apiKey.trim();
    return key.isEmpty ? '' : '?key=${Uri.encodeQueryComponent(key)}';
  }

  Uri _generateUri() =>
      Uri.parse('$_base/models/${config.model}:generateContent$_keyQuery');

  Uri _modelUri() => Uri.parse('$_base/models/${config.model}$_keyQuery');

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
    final sampling = config.sampling.values;
    final system = messages
        .whereType<SystemMessage>()
        .map((m) => m.content)
        .join('\n\n');
    final contents = GoogleGenAiProvider.contents(messages);
    // A cancellable call goes through the token's own client so cancelling can
    // close the socket; otherwise reuse the shared pooled client.
    final client = _client ?? cancelToken?.client ?? AiHttp.client;

    while (true) {
      final attempt = _thinkingOffAttempts[_cacheKey] ?? 0;
      final off =
          config.thinkingEnabled || attempt >= _ThinkingOff.values.length
          ? null
          : _ThinkingOff.values[attempt];

      final body = jsonEncode({
        if (system.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
        'contents': contents,
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
      });

      http.Response res;
      try {
        res = await AiHttp.withRetry(
          () => client
              .post(
                _generateUri(),
                headers: {'Content-Type': 'application/json'},
                body: body,
              )
              .timeout(timeout),
          cancelToken: cancelToken,
          retryTimeouts: false,
        );
      } on AiCancelled {
        rethrow;
      } on TimeoutException {
        if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
        throw AiNetworkException(
          'No response from the server within ${timeout.inMinutes} min.',
        );
      } catch (e) {
        // Closing the client to cancel surfaces as a generic ClientException;
        // report it as a cancellation, not a network failure.
        if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
        throw AiNetworkException(AiHttp.describeTransportError(e));
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final error = AiHttp.describeError(res);
        // This way of asking for no reasoning is not this model's; try the
        // next. Checked before throwing, exactly as the OpenAI provider does.
        if ((res.statusCode == 400 || res.statusCode == 422) &&
            off != null &&
            _namesThinking(error.toLowerCase())) {
          _thinkingOffAttempts[_cacheKey] = attempt + 1;
          continue;
        }
        throw AiException(error);
      }

      final result = _read(res);
      if (off == null || !result.reasoned) return result;
      // Accepted and ignored — a relay that does not implement thinkingConfig
      // drops it silently. The next request tries the next way.
      _thinkingOffAttempts[_cacheKey] = attempt + 1;
      return result.withThinkingOffPending(
        attempt + 1 < _ThinkingOff.values.length,
      );
    }
  }

  static bool _namesThinking(String detail) =>
      detail.contains('thinking') ||
      detail.contains('thinkingconfig') ||
      detail.contains('thinking_config') ||
      detail.contains('thinking_budget') ||
      detail.contains('thinking_level');

  /// Turns one `generateContent` response into a [ChatResult].
  ///
  /// A blocked request and a blocked answer are both failures, not empty
  /// replies. Gemini reports the first as `promptFeedback.blockReason` and the
  /// second as a `finishReason` other than `STOP`, in both cases with HTTP 200
  /// and often after some text — so returning what arrived would hand the
  /// caller a partial answer it cannot tell from a complete one, and the agent
  /// loop would read the silence as "the model stopped calling tools".
  ChatResult _read(http.Response res) {
    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json['promptFeedback'] case final Map<String, dynamic> feedback) {
      if (feedback['blockReason'] case final String reason) {
        throw AiException('The request was blocked by Google: $reason.');
      }
    }
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const AiException('Empty response from model.');
    }
    final candidate = candidates.first as Map<String, dynamic>;
    final rawParts = candidate['content']?['parts'] as List<dynamic>? ?? [];
    final parts = rawParts.whereType<Map<dynamic, dynamic>>().toList();
    final usage = json['usageMetadata'] as Map<String, dynamic>?;
    final finishReason = candidate['finishReason'] as String?;

    final toolCalls = <ToolCall>[
      for (final (index, part) in parts.indexed)
        if (part['functionCall'] case final Map<dynamic, dynamic> call)
          ToolCall(
            id: call['id'] as String? ?? 'call_$index',
            name: call['name'] as String? ?? '',
            arguments: jsonEncode(call['args'] ?? const <String, Object?>{}),
          ),
    ];

    if (_blocked(finishReason)) {
      throw AiException(
        'The model stopped with "$finishReason" and its answer was '
        'discarded.',
      );
    }

    // Thinking is billed on top of the answer and Google reports it beside
    // `candidatesTokenCount`, never inside it. Reading only the latter
    // under-reports the most expensive part of a reasoning run.
    final completionTokens =
        ((usage?['candidatesTokenCount'] as num?)?.toInt() ?? 0) +
        ((usage?['thoughtsTokenCount'] as num?)?.toInt() ?? 0);

    return ChatResult(
      // Thought parts are reasoning, not the answer.
      text: parts
          .where((p) => p['thought'] != true && p['text'] is String)
          .map((p) => p['text'] as String)
          .join(),
      toolCalls: toolCalls,
      // Sent back verbatim: function-call parts can carry thought signatures.
      geminiParts: toolCalls.isEmpty ? null : List<Object?>.of(rawParts),
      promptTokens: (usage?['promptTokenCount'] as num?)?.toInt() ?? 0,
      completionTokens: completionTokens,
      finishReason: finishReason,
      reasoned:
          parts.any((p) => p['thought'] == true) ||
          ((usage?['thoughtsTokenCount'] as num?)?.toInt() ?? 0) > 0,
    );
  }

  /// Finish reasons that mean the answer must not be used.
  ///
  /// `MAX_TOKENS` is deliberately absent: it is a real, usable answer that was
  /// cut short, and [ChatResult.truncated] already reports it.
  static bool _blocked(String? finishReason) =>
      switch (finishReason?.toUpperCase()) {
        'SAFETY' ||
        'RECITATION' ||
        'BLOCKLIST' ||
        'PROHIBITED_CONTENT' ||
        'SPII' ||
        'IMAGE_SAFETY' ||
        'MALFORMED_FUNCTION_CALL' => true,
        _ => false,
      };

  /// Converts the conversation to Gemini `contents`.
  ///
  /// System messages travel separately as `systemInstruction`. A round's tool
  /// results go back as one user turn of `functionResponse` parts, matching the
  /// single model turn whose calls they answer.
  static List<Map<String, Object?>> contents(List<ChatMessage> messages) {
    final out = <Map<String, Object?>>[];
    for (final message in messages) {
      switch (message) {
        case SystemMessage():
          break;
        case UserMessage(:final content):
          out.add({
            'role': 'user',
            'parts': [
              {'text': content},
            ],
          });
        case AssistantMessage(
          :final content,
          :final toolCalls,
          :final geminiParts,
        ):
          out.add({
            'role': 'model',
            'parts':
                geminiParts ??
                [
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
          .get(_modelUri())
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
