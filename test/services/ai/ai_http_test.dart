import 'package:flutter_test/flutter_test.dart';
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
}
