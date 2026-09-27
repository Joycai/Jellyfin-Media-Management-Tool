import 'dart:async';

import 'package:http/http.dart' as http;

/// Passes every request to [inner] and keeps the last one as the adapter
/// built it. `MockClient` hands its handler a copy, so a test that must see
/// the request object itself — whether it can be aborted — reads it here.
class RecordingClient extends http.BaseClient {
  final http.Client inner;
  http.BaseRequest? last;

  RecordingClient(this.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    last = request;
    return inner.send(request);
  }
}

/// A server that never answers: `send` waits for the request's abort
/// trigger, then fails the way `IOClient` does. A request that cannot be
/// aborted waits forever.
class MuteClient extends http.BaseClient {
  http.BaseRequest? last;

  /// Whether a request was aborted through its trigger.
  var aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    last = request;
    if (request case http.Abortable(:final abortTrigger?)) {
      await abortTrigger;
      aborted = true;
      throw http.RequestAbortedException(request.url);
    }
    return Completer<http.StreamedResponse>().future;
  }
}

/// The abort trigger of [request] — the last one a [RecordingClient] saw —
/// which fails the test when the adapter did not build an abortable one.
Future<void> abortOf(http.BaseRequest? request) =>
    (request! as http.Abortable).abortTrigger!;
