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
  }) async {
    final sampling = config.sampling.values;
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userPrompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': ?sampling.temperature,
        'topP': ?sampling.topP,
        'topK': ?sampling.topK,
        'presencePenalty': ?sampling.presencePenalty,
        'responseMimeType': 'application/json',
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
    final parts = (candidate['content']?['parts'] as List<dynamic>? ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .toList();
    // Thought parts are reasoning, not the answer.
    final answer = parts.where((p) => p['thought'] != true).firstOrNull;
    final usage = json['usageMetadata'] as Map<String, dynamic>?;

    return AiResponse(
      text: answer?['text'] as String? ?? '',
      promptTokens: (usage?['promptTokenCount'] as num?)?.toInt() ?? 0,
      completionTokens: (usage?['candidatesTokenCount'] as num?)?.toInt() ?? 0,
      finishReason: candidate['finishReason'] as String?,
      reasoned:
          parts.any((p) => p['thought'] == true) ||
          ((usage?['thoughtsTokenCount'] as num?)?.toInt() ?? 0) > 0,
    );
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
