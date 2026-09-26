import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jellyfin_media_management_tool/services/ai/ai_http.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';

void main() {
  group('AiHttp.statusError', () {
    test('a refused request is an AiException, nothing more', () {
      for (final status in [400, 404, 405, 413, 422]) {
        final error = AiHttp.statusError(status, 'HTTP $status: no');
        expect(error, isA<AiException>(), reason: '$status');
        expect(error, isNot(isA<AiNetworkException>()), reason: '$status');
        expect(error.message, 'HTTP $status: no');
      }
    });

    test('account, rate-limit and server statuses settle nothing', () {
      for (final status in [401, 402, 403, 408, 429, 500, 502, 503, 504, 529]) {
        expect(
          AiHttp.statusError(status, 'HTTP $status'),
          isA<AiNetworkException>(),
          reason: '$status',
        );
      }
    });

    test('only a timeout on the way is a timeout', () {
      for (final status in [408, 504, 524]) {
        final error = AiHttp.statusError(status, 'HTTP $status');
        expect(error, isA<AiTimeoutException>(), reason: '$status');
        expect(error.message, 'HTTP $status');
      }
      for (final status in [401, 402, 403, 429, 500, 502, 503, 529]) {
        expect(
          AiHttp.statusError(status, 'HTTP $status'),
          isNot(isA<AiTimeoutException>()),
          reason: '$status',
        );
      }
    });
  });

  group('AiHttp.withRetry', () {
    Future<(int, int)> send(int status) async {
      var calls = 0;
      final res = await AiHttp.withRetry(() async {
        calls++;
        // retry-after: 0 keeps the backoff out of the test.
        return http.Response('', status, headers: const {'retry-after': '0'});
      });
      return (calls, res.statusCode);
    }

    test('a gateway timeout is not sent again', () async {
      // The upstream may still be generating — and billing — the first one.
      expect(await send(504), (1, 504));
      expect(await send(408), (1, 408));
      expect(await send(524), (1, 524));
    });

    test('an overloaded or rate-limited server is', () async {
      for (final status in [429, 502, 503, 529]) {
        expect(await send(status), (3, status), reason: '$status');
      }
    });
  });

  test('error.param is read when it is a string, and only then', () {
    String? param(String body) => AiHttp.errorParam(http.Response(body, 400));
    expect(param('{"error": {"message": "m", "param": "include"}}'), 'include');
    expect(param('{"error": {"message": "m", "param": null}}'), isNull);
    expect(param('{"error": {"message": "m", "param": " "}}'), isNull);
    expect(param('{"error": "bare string"}'), isNull);
    expect(param('{"param": "top_k"}'), isNull);
    expect(param('<html>bad gateway</html>'), isNull);
    // A malformed byte in the message does not cost the param.
    final malformed = http.Response.bytes([
      ...utf8.encode('{"error": {"message": "bad '),
      0xff,
      ...utf8.encode('", "param": "top_k"}}'),
    ], 400);
    expect(AiHttp.errorParam(malformed), 'top_k');
  });

  test('a param names a field or a path inside it', () {
    expect(AiHttp.paramNames('reasoning.effort', 'reasoning'), isTrue);
    expect(AiHttp.paramNames('include[0]', 'include'), isTrue);
    expect(AiHttp.paramNames('top_k', 'top_k'), isTrue);
    // A prefix of a longer name is another field.
    expect(AiHttp.paramNames('top_p', 'top'), isFalse);
    expect(AiHttp.paramNames('reasoning_effort', 'reasoning'), isFalse);
    expect(AiHttp.paramNames(null, 'top_k'), isFalse);
  });

  test('a wrong address is named, and only a wrong address', () {
    final url = Uri.parse('https://u:p@relay.example:8443/x/v1/messages?k=s#f');
    expect(
      AiHttp.statusError(404, 'HTTP 404', url: url).message,
      'HTTP 404 — POST https://relay.example:8443/x/v1/messages',
    );
    expect(
      AiHttp.statusError(405, 'HTTP 405', url: url).message,
      'HTTP 405 — POST https://relay.example:8443/x/v1/messages',
    );
    for (final status in [400, 401, 422, 500]) {
      expect(
        AiHttp.statusError(status, 'HTTP $status', url: url).message,
        'HTTP $status',
        reason: '$status',
      );
    }
  });
}
