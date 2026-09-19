import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_diagnostics_page.dart';

import '../../helpers/settings.dart';

void main() {
  testWidgets("today's API log is listed, newest first", (tester) async {
    useTempSupportDir();
    final dir = Directory.systemTemp.createTempSync('diag_log');
    addTearDown(() {
      ApiLog.instance
        ..enabled = false
        ..directory = null;
      dir.deleteSync(recursive: true);
    });
    ApiLog.instance
      ..directory = dir
      ..enabled = true;
    await tester.runAsync(() async {
      for (final model in ['first-model', 'second-model']) {
        ApiLog.instance.record(
          protocol: 'chat',
          model: model,
          url: Uri.parse('http://x/v1/chat/completions'),
          request: const {},
          status: 200,
          response: const {
            'finish_reason': 'stop',
            'usage': {'prompt': 10, 'completion': 2},
          },
        );
      }
      await ApiLog.instance.flush();
    });

    await pumpAiPage(
      tester,
      AiDiagnosticsPage(initialModelId: null, onBack: () {}),
      profiles: AiProfilesService(),
    );
    // The page reads the log from disk, which only real time moves along.
    for (
      var i = 0;
      i < 10 && find.textContaining('first-model').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.textContaining('first-model'));
    final second = tester.getTopLeft(find.textContaining('second-model'));
    expect(second.dy, lessThan(first.dy));
    await settleSaves(tester);
  });
}
