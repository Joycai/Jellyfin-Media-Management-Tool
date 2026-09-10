import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';

/// How a request asks for JSON, most to least constrained. [OpenAiProvider]
/// steps down this list when a server rejects the current form.
enum _JsonMode { object, schema, none }

/// Talks to any OpenAI-compatible `/chat/completions` endpoint.
class OpenAiProvider implements AiProvider {
  @override
  final AiConfig config;

  /// Replaces the transport in tests. Left null, a request goes through its
  /// cancel token's client (so cancelling closes the socket) or the shared
  /// pooled one.
  final http.Client? _client;

  OpenAiProvider(this.config, {http.Client? client}) : _client = client;

  /// The JSON mode each server + model last accepted, remembered for the
  /// process so only the first request of a session pays for a rejection.
  static final Map<String, _JsonMode> _acceptedJsonModes = {};

  /// Server + model pairs that refused `max_tokens` in favour of
  /// `max_completion_tokens`, as OpenAI's reasoning models do.
  static final Set<String> _wantsMaxCompletionTokens = {};

  /// Normalized base URL ending in `/v1` (or whatever versioned suffix the
  /// user supplied). Used to derive `/chat/completions` and `/models`.
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

  /// [_base] without its `/v1` — where LM Studio, Ollama and llama.cpp serve
  /// their native endpoints beside the compatible API.
  String get _root {
    final base = _base;
    return base.endsWith('/v1') ? base.substring(0, base.length - 3) : base;
  }

  String get _cacheKey => '$_base|${config.model}';

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

  /// Performs one completion, stepping down the JSON modes on rejection.
  ///
  /// `response_format: json_object` is OpenAI's form and most servers take it,
  /// but not all: LM Studio answers it with a 400 ("'response_format.type'
  /// must be 'json_schema' or 'text'"), which failed every organize and scrape
  /// request against it. A rejection naming the parameter now retries with a
  /// permissive `json_schema`, then with no constraint at all — the prompts
  /// already demand a bare JSON object, and every parser tolerates stray prose
  /// around one. The mode that worked is remembered.
  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) async {
    // A cancellable call goes through the token's own client so cancelling can
    // close the socket; otherwise reuse the shared pooled client.
    final client = _client ?? cancelToken?.client ?? AiHttp.client;
    final maxTokens = config.maxOutputTokens;
    var mode = _acceptedJsonModes[_cacheKey] ?? _JsonMode.object;
    var maxCompletionTokens = _wantsMaxCompletionTokens.contains(_cacheKey);

    while (true) {
      final body = jsonEncode({
        'model': config.model,
        'temperature': config.temperature,
        (maxCompletionTokens ? 'max_completion_tokens' : 'max_tokens'):
            ?maxTokens,
        ...?_responseFormat(mode),
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      });

      http.Response res;
      try {
        res = await AiHttp.withRetry(
          () => client
              .post(_chatUri, headers: _headers, body: body)
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

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _acceptedJsonModes[_cacheKey] = mode;
        return _parse(res);
      }

      final error = AiHttp.describeError(res);
      if (res.statusCode == 400 || res.statusCode == 422) {
        final detail = error.toLowerCase();
        if (mode != _JsonMode.none && _namesResponseFormat(detail)) {
          mode = _JsonMode.values[mode.index + 1];
          continue;
        }
        if (maxTokens != null &&
            !maxCompletionTokens &&
            detail.contains('max_completion_tokens')) {
          maxCompletionTokens = true;
          _wantsMaxCompletionTokens.add(_cacheKey);
          continue;
        }
      }
      throw AiException(error);
    }
  }

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

  static AiResponse _parse(http.Response res) {
    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const AiException('Empty response from model.');
    }
    final choice = choices.first as Map<String, dynamic>;
    final content = (choice['message']?['content'] as String?) ?? '';
    final usage = json['usage'] as Map<String, dynamic>?;

    return AiResponse(
      text: content,
      promptTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
      finishReason: choice['finish_reason'] as String?,
    );
  }

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
