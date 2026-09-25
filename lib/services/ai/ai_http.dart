import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_provider.dart';

/// Shared HTTP machinery for the AI providers: a process-wide client (so
/// connections get reused across calls) and a small retry helper for the
/// classic LLM-endpoint transient errors.
class AiHttp {
  /// Single client reused across every provider call so the underlying
  /// `HttpClient` can pool keep-alive connections. We never close it; it
  /// lives for the process lifetime.
  static final http.Client client = http.Client();

  /// Statuses that LLM endpoints commonly fail with transiently, before the
  /// work began. We retry these; anything else (4xx auth errors, 400
  /// validation, etc.) is returned to the caller so they can render the
  /// real error. 529 is Anthropic's "overloaded".
  ///
  /// Not 408 or 504: both are a timeout on the way, and the upstream may
  /// still be generating — and billing — the first attempt, exactly like a
  /// client-side timeout. 502 stays: a gateway that got no valid answer
  /// more likely failed before the upstream started.
  static const _retryableStatuses = {429, 502, 503, 529};

  /// Calls [send] up to [maxAttempts] times with exponential backoff between
  /// retries — only for a request that is safe to send twice once refused.
  /// Retries on:
  /// - [_retryableStatuses]
  /// - [TimeoutException], unless [retryTimeouts] is false
  /// - [SocketException] (network blips)
  ///
  /// Backoff doubles each retry starting from [initialBackoff]. Honors the
  /// `Retry-After` header on the last response when present (as an integer
  /// seconds value).
  ///
  /// Pass `retryTimeouts: false` for a generation request. A timeout there
  /// usually means the server is still working, and a retry makes it start
  /// the same generation again while the first one keeps running.
  ///
  /// A cancelled [cancelToken] aborts the loop with [AiCancelled] — checked
  /// before every attempt and after every backoff so a cancel that lands
  /// mid-backoff doesn't wait for the next request to be sent.
  static Future<T> withRetry<T extends http.BaseResponse>(
    Future<T> Function() send, {
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(milliseconds: 500),
    AiCancelToken? cancelToken,
    bool retryTimeouts = true,
  }) async {
    var backoff = initialBackoff;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      cancelToken?.throwIfCancelled();
      try {
        final res = await send();
        if (_retryableStatuses.contains(res.statusCode) &&
            attempt < maxAttempts) {
          // An unread streamed body would hold its connection open.
          if (res is http.StreamedResponse) {
            await res.stream.drain<void>().catchError((_) {});
          }
          await Future.delayed(_retryAfter(res) ?? backoff);
          backoff *= 2;
          continue;
        }
        return res;
      } on TimeoutException {
        if (!retryTimeouts || attempt == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
      } on SocketException {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
      }
      cancelToken?.throwIfCancelled();
    }
    throw StateError('AiHttp.withRetry: unreachable');
  }

  /// A one-line, UI-safe description of a transport failure.
  ///
  /// Never the exception's own text. `package:http` puts the request URL in
  /// every `ClientException` it raises (`ClientException with …, uri=…`), and
  /// Google's API carries the API key in that URL's query string — so
  /// interpolating the exception would print the key into the settings page,
  /// a SnackBar and anywhere either is copied. The cause is what a user can
  /// act on; the URL is not, and they already know which endpoint they typed.
  static String describeTransportError(Object error) {
    final message = switch (error) {
      SocketException(:final osError) =>
        osError?.message.trim() ?? 'the server could not be reached',
      HandshakeException() => 'the TLS handshake failed',
      TlsException() => 'the TLS connection failed',
      http.ClientException(:final message) => message.trim(),
      FormatException() => 'the server sent a malformed reply',
      _ => '',
    };
    return message.isEmpty
        ? 'Network error.'
        : 'Network error: ${_clip(message)}';
  }

  /// What a log may say about [error]: an [AiException]'s own message, which
  /// is written to be shown, or else [describeTransportError] — never the
  /// exception's text, which can carry the request URL.
  static String describeFailure(Object error) => switch (error) {
    AiCancelled() => 'cancelled',
    AiException(:final message) => message,
    _ => describeTransportError(error),
  };

  static String _clip(String message) =>
      message.length > 200 ? '${message.substring(0, 200)}\u2026' : message;

  /// A one-line, UI-safe description of a failed response.
  ///
  /// OpenAI nests the text as `{"error": {"message": …}}`, but compatible
  /// servers each pick their own shape: LM Studio sends `{"error": "…"}` as a
  /// bare string, vLLM `{"message": …}`, FastAPI-based servers
  /// `{"detail": …}`. Reading only the first reduced an LM Studio rejection to
  /// a bare "HTTP 400" with its reason thrown away.
  static String describeError(http.Response res) {
    final body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    String? message;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          message = error['message'] as String;
        } else if (error is String) {
          message = error;
        } else if (json['message'] is String) {
          message = json['message'] as String;
        } else if (json['detail'] is String) {
          message = json['detail'] as String;
        }
      }
    } on FormatException {
      // Plain text is worth showing; a proxy's HTML error page is not.
      if (!body.startsWith('<')) message = body;
    }
    message = message?.trim();
    if (message == null || message.isEmpty) return 'HTTP ${res.statusCode}';
    if (message.length > 300) message = '${message.substring(0, 300)}…';
    return 'HTTP ${res.statusCode}: $message';
  }

  /// The request field an OpenAI-style error names in `error.param`
  /// (`"top_k"`, `"reasoning.effort"`, `"include"`), or null. The message
  /// is prose and may not name the field at all (audit V5 expects "Encrypted
  /// content is not supported with this model." for `include` — unverified);
  /// `param` is where OpenAI puts it.
  static String? errorParam(http.Response res) {
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (json case {'error': {'param': final String param}}) {
        final trimmed = param.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
    } on FormatException {
      // Not JSON; the message is all there is.
    }
    return null;
  }

  /// Whether [param], from [errorParam], names [field] itself or a path
  /// inside it (`reasoning.effort`, `messages[0]` → `messages`).
  static bool paramNames(String? param, String field) =>
      param != null &&
      (param == field ||
          param.startsWith('$field.') ||
          param.startsWith('$field['));

  /// The exception for a non-2xx reply carrying [message].
  ///
  /// A bad key, an empty balance, a rate limit and the server's own failure
  /// settle nothing about the model, so they are [AiNetworkException]s;
  /// anything else is the request itself being refused. A 408 or 504 is a
  /// timeout on the way, and the upstream may still be generating: an
  /// [AiTimeoutException], which nothing resends.
  ///
  /// A 404 or 405 — the address is wrong — also says where the request went
  /// ([url], through [safeUrl]), since a path the adapter built from a
  /// pasted endpoint is the one thing the user cannot see. Only then: the
  /// learning that reads other refusals matches words in the message, and
  /// a relay's path can contain `function` or `thinking`.
  static AiException statusError(int status, String message, {Uri? url}) {
    if (url != null && (status == 404 || status == 405)) {
      message = '$message — POST ${safeUrl(url)}';
    }
    if (status == 408 || status == 504) return AiTimeoutException(message);
    return status == 401 ||
            status == 402 ||
            status == 403 ||
            status == 429 ||
            status >= 500
        ? AiNetworkException(message)
        : AiException(message);
  }

  /// [url] without its query string, fragment or user info, any of which
  /// can carry a credential (Google's key once travelled as `?key=`).
  static String safeUrl(Uri url) => Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: url.path,
  ).toString();

  /// [endpoint] as typed, trimmed, without a query string, fragment or
  /// trailing slashes — the part an adapter builds its paths on.
  static String endpointBase(String endpoint) {
    var base = endpoint.trim();
    final cut = base.indexOf(RegExp('[?#]'));
    if (cut != -1) base = base.substring(0, cut);
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  static Duration? _retryAfter(http.BaseResponse res) {
    final header = res.headers['retry-after'];
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    return null;
  }
}
