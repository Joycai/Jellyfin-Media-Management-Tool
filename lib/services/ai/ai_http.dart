import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';

/// Shared HTTP machinery for the AI providers: a process-wide client (so
/// connections get reused across calls) and a small retry helper for the
/// classic LLM-endpoint transient errors.
class AiHttp {
  /// Single client reused across every provider call so the underlying
  /// `HttpClient` can pool keep-alive connections. We never close it; it
  /// lives for the process lifetime.
  static final http.Client client = http.Client();

  /// Statuses that LLM endpoints commonly fail with transiently. We retry
  /// these; anything else (4xx auth errors, 400 validation, etc.) is
  /// returned to the caller so they can render the real error.
  static const _retryableStatuses = {408, 429, 502, 503, 504};

  /// Calls [send] up to [maxAttempts] times with exponential backoff between
  /// retries. Retries on:
  /// - [_retryableStatuses]
  /// - [TimeoutException] and [SocketException] (network blips)
  ///
  /// Backoff doubles each retry starting from [initialBackoff]. Honors the
  /// `Retry-After` header on the last response when present (as an integer
  /// seconds value).
  ///
  /// A cancelled [cancelToken] aborts the loop with [AiCancelled] — checked
  /// before every attempt and after every backoff so a cancel that lands
  /// mid-backoff doesn't wait for the next request to be sent.
  static Future<http.Response> withRetry(
    Future<http.Response> Function() send, {
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(milliseconds: 500),
    AiCancelToken? cancelToken,
  }) async {
    var backoff = initialBackoff;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      cancelToken?.throwIfCancelled();
      try {
        final res = await send();
        if (_retryableStatuses.contains(res.statusCode) &&
            attempt < maxAttempts) {
          await Future.delayed(_retryAfter(res) ?? backoff);
          backoff *= 2;
          continue;
        }
        return res;
      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
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

  static Duration? _retryAfter(http.Response res) {
    final header = res.headers['retry-after'];
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    return null;
  }
}
