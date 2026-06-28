import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_http.dart';
import 'ai_provider.dart';

/// Talks to the Google Generative Language REST API (`:generateContent`).
class GoogleGenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  GoogleGenAiProvider(this.config);

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

  Uri _generateUri() => Uri.parse(
        '$_base/models/${config.model}:generateContent?key=${config.apiKey}',
      );

  Uri _modelsUri() => Uri.parse('$_base/models?key=${config.apiKey}');

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userPrompt}
          ],
        }
      ],
      'generationConfig': {
        'temperature': config.temperature,
        'responseMimeType': 'application/json',
      },
    });

    http.Response res;
    try {
      res = await AiHttp.withRetry(() => AiHttp.client
          .post(
            _generateUri(),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 120)));
    } catch (e) {
      throw AiException('Network error: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiException(_errorMessage(res));
    }

    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const AiException('Empty response from model.');
    }
    final parts = candidates.first['content']?['parts'] as List<dynamic>?;
    final text = (parts != null && parts.isNotEmpty)
        ? (parts.first['text'] as String? ?? '')
        : '';
    final usage = json['usageMetadata'] as Map<String, dynamic>?;

    return AiResponse(
      text: text,
      promptTokens: (usage?['promptTokenCount'] as num?)?.toInt() ?? 0,
      completionTokens: (usage?['candidatesTokenCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Probes `GET /v1beta/models` — validates the API key without spending
  /// generation tokens. Confirms the response carries a `models` array.
  @override
  Future<bool> testConnection() async {
    http.Response res;
    try {
      res = await AiHttp.withRetry(() => AiHttp.client
          .get(_modelsUri())
          .timeout(const Duration(seconds: 15)));
    } catch (e) {
      throw AiException('Network error: $e');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiException(_errorMessage(res));
    }
    final Map<String, dynamic> body = jsonDecode(utf8.decode(res.bodyBytes));
    return body['models'] is List;
  }

  String _errorMessage(http.Response res) {
    try {
      final Map<String, dynamic> body = jsonDecode(utf8.decode(res.bodyBytes));
      final msg = body['error']?['message'];
      if (msg is String && msg.isNotEmpty) return 'HTTP ${res.statusCode}: $msg';
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }
}
