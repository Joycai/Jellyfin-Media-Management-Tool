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
    });

    test('an overloaded or rate-limited server is', () async {
      for (final status in [429, 502, 503, 529]) {
        expect(await send(status), (3, status), reason: '$status');
      }
    });
  });
}
