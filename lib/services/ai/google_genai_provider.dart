import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';

/// Talks to the Google Generative Language REST API (`:generateContent`).
class GoogleGenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  /// Replaces the transport in tests; see [OpenAiProvider].
  final http.Client? _client;

  GoogleGenAiProvider(this.config, {http.Client? client}) : _client = client;

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
    final body = jsonEncode({
      if (system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'contents': contents(messages),
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
      },
    });

    // A cancellable call goes through the token's own client so cancelling can
    // close the socket; otherwise reuse the shared pooled client.
    final client = _client ?? cancelToken?.client ?? AiHttp.client;

    http.Response res;
    try {
      res = await AiHttp.withRetry(
        () => client
            .post(
              _generateUri(),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 120)),
        cancelToken: cancelToken,
      );
    } on AiCancelled {
      rethrow;
    } catch (e) {
      // Closing the client to cancel surfaces as a generic ClientException;
      // report it as a cancellation, not a network failure.
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      throw AiException('Network error: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiException(AiHttp.describeError(res));
    }

    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const AiException('Empty response from model.');
    }
    final candidate = candidates.first as Map<String, dynamic>;
    final rawParts = candidate['content']?['parts'] as List<dynamic>? ?? [];
    final parts = rawParts.whereType<Map<dynamic, dynamic>>().toList();
    final usage = json['usageMetadata'] as Map<String, dynamic>?;

    final toolCalls = <ToolCall>[
      for (final (index, part) in parts.indexed)
        if (part['functionCall'] case final Map<dynamic, dynamic> call)
          ToolCall(
            id: call['id'] as String? ?? 'call_$index',
            name: call['name'] as String? ?? '',
            arguments: jsonEncode(call['args'] ?? const <String, Object?>{}),
          ),
    ];

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
      completionTokens: (usage?['candidatesTokenCount'] as num?)?.toInt() ?? 0,
      finishReason: candidate['finishReason'] as String?,
      reasoned:
          parts.any((p) => p['thought'] == true) ||
          ((usage?['thoughtsTokenCount'] as num?)?.toInt() ?? 0) > 0,
    );
  }

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
