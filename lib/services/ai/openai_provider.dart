import 'dart:async';
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

  /// Server + model pairs that refused `stream_options`.
  static final Set<String> _rejectsStreamOptions = {};

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

  /// Performs one streamed completion, stepping down the JSON modes on
  /// rejection.
  ///
  /// **Why a stream.** A plan is long — every file comes back as an action —
  /// and a local model writes it slowly: a 27B model on LM Studio took 88 s
  /// for thirty episodes, much of it reasoning. The request used to have 120 s
  /// in total, so any real folder timed out, and the retry that followed made
  /// the server start the same generation again while the abandoned one was
  /// still running. A stream is timed on silence instead — [firstEventTimeout]
  /// for loading and reading the prompt, [idleTimeout] for any later gap.
  /// Reasoning tokens stream too, so a slow model that is working never trips
  /// it and a hung one still fails. Closing the stream, on timeout or cancel,
  /// is also what makes the server stop generating. A timeout is never
  /// retried.
  ///
  /// **JSON mode.** `response_format: json_object` is OpenAI's form and most
  /// servers take it, but not all: LM Studio answers it with a 400
  /// ("'response_format.type' must be 'json_schema' or 'text'"). A rejection
  /// naming the parameter retries with a permissive `json_schema`, then with
  /// no constraint at all — the prompts already demand a bare JSON object, and
  /// every parser tolerates stray prose around one. The mode that worked is
  /// remembered.
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
    var streamOptions = !_rejectsStreamOptions.contains(_cacheKey);

    while (true) {
      final body = jsonEncode({
        'model': config.model,
        'temperature': config.temperature,
        (maxCompletionTokens ? 'max_completion_tokens' : 'max_tokens'):
            ?maxTokens,
        ...?_responseFormat(mode),
        'stream': true,
        // Asks for token usage in the final chunk; a stream omits it otherwise.
        if (streamOptions) 'stream_options': const {'include_usage': true},
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
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
        throw AiException(_noResponse(firstEventTimeout));
      } catch (e) {
        // Closing the client to cancel surfaces as a generic ClientException;
        // report it as a cancellation, not a network failure.
        if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
        throw AiException('Network error: $e');
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _acceptedJsonModes[_cacheKey] = mode;
        return _read(res, cancelToken);
      }

      String error;
      try {
        error = AiHttp.describeError(await http.Response.fromStream(res));
      } catch (_) {
        error = 'HTTP ${res.statusCode}';
      }
      if (res.statusCode == 400 || res.statusCode == 422) {
        final detail = error.toLowerCase();
        if (streamOptions && detail.contains('stream_options')) {
          streamOptions = false;
          _rejectsStreamOptions.add(_cacheKey);
          continue;
        }
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

  /// Collects a streamed completion from its server-sent events.
  ///
  /// Only `delta.content` is kept: reasoning arrives as `reasoning_content`
  /// and is not part of the answer. A body that is not an event stream — a
  /// server or proxy that ignored `stream: true` — is parsed as one ordinary
  /// JSON completion instead.
  Future<AiResponse> _read(
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
    bool? sse;
    String? finishReason;
    var promptTokens = 0;
    var completionTokens = 0;
    var started = false;

    try {
      while (true) {
        final bool more;
        try {
          more = await lines.moveNext().timeout(
            started ? idleTimeout : firstEventTimeout,
          );
        } on TimeoutException {
          throw AiException(
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
        final error = event['error'];
        if (error != null) {
          final message = error is Map ? error['message'] : error;
          throw AiException('Model error: $message');
        }
        final choices = event['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final choice = choices.first as Map;
          final delta = choice['delta'];
          if (delta is Map && delta['content'] is String) {
            content.write(delta['content']);
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
        }
      }
    } on AiException {
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      throw AiException('Network error: $e');
    } finally {
      // On an early exit this closes the connection, which is what tells the
      // server to stop generating.
      await lines.cancel();
    }

    if (sse != true) return _parse(plain.toString());
    if (content.isEmpty && finishReason == null) {
      throw const AiException('Empty response from model.');
    }
    return AiResponse(
      text: content.toString(),
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      finishReason: finishReason,
    );
  }

  static AiResponse _parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const AiException('Empty response from model.');
    }
    final choices = json is Map ? json['choices'] : null;
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiException('Empty response from model.');
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    final content = message is Map ? message['content'] as String? : null;
    final usage = (json as Map)['usage'];

    return AiResponse(
      text: content ?? '',
      promptTokens: usage is Map
          ? (usage['prompt_tokens'] as num?)?.toInt() ?? 0
          : 0,
      completionTokens: usage is Map
          ? (usage['completion_tokens'] as num?)?.toInt() ?? 0
          : 0,
      finishReason: choice['finish_reason'] as String?,
    );
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
