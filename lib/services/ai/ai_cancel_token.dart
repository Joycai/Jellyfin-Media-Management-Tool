import 'package:http/http.dart' as http;

/// Thrown when work was aborted through an [AiCancelToken]. Callers treat this
/// as "stopped by the user", not as a failure.
class AiCancelled implements Exception {
  const AiCancelled();

  @override
  String toString() => 'Cancelled';
}

/// Aborts one in-flight AI analysis.
///
/// The request is issued on this token's own [http.Client] rather than the
/// shared [AiHttp.client]: closing that client is what actually tears down the
/// socket, so a cancel takes effect immediately instead of only being noticed
/// after the model finally answers. One analysis = one request, so giving up
/// the shared connection pool costs nothing here.
class AiCancelToken {
  bool _cancelled = false;
  http.Client? _client;

  bool get isCancelled => _cancelled;

  /// The client the request must go through. Created lazily so an unused token
  /// costs nothing.
  http.Client get client {
    throwIfCancelled();
    return _client ??= http.Client();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const AiCancelled();
  }

  /// Marks the token cancelled and aborts any request already in flight.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _client?.close();
    _client = null;
  }

  /// Releases the client once the work finished normally. Idempotent, and safe
  /// to call after [cancel].
  void dispose() {
    _client?.close();
    _client = null;
  }
}
