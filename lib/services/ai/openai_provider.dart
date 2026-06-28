import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_http.dart';
import 'ai_provider.dart';

/// Talks to any OpenAI-compatible `/chat/completions` endpoint.
class OpenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  OpenAiProvider(this.config);

  /// Normalized base URL ending in `/v1` (or whatever versioned suffix the
  /// user supplied). Used to derive both `/chat/completions` and `/models`.
  String get _base {
    var base = config.endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.endsWith('/v1') && !base.contains('/v1/')) {
      base = '$base/v1';
    }
    return base;
  }

  Uri get _chatUri => Uri.parse('$_base/chat/completions');
  Uri get _modelsUri => Uri.parse('$_base/models');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      };

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final body = jsonEncode({
      'model': config.model,
      'response_format': {'type': 'json_object'},
      'temperature': config.temperature,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    });

    http.Response res;
    try {
      res = await AiHttp.withRetry(() => AiHttp.client
          .post(_chatUri, headers: _headers, body: body)
          .timeout(const Duration(seconds: 120)));
    } catch (e) {
      throw AiException('Network error: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiException(_errorMessage(res));
    }

    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const AiException('Empty response from model.');
    }
    final content = (choices.first['message']?['content'] as String?) ?? '';
    final usage = json['usage'] as Map<String, dynamic>?;

    return AiResponse(
      text: content,
      promptTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  /// Probes `GET /v1/models` instead of running a chat completion — credentials
  /// are validated server-side without spending generation tokens.
  @override
  Future<bool> testConnection() async {
    http.Response res;
    try {
      res = await AiHttp.withRetry(() => AiHttp.client
          .get(_modelsUri, headers: _headers)
          .timeout(const Duration(seconds: 15)));
    } catch (e) {
      throw AiException('Network error: $e');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiException(_errorMessage(res));
    }
    return true;
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
