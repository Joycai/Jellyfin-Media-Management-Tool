import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations_en.dart';
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

  test('the reasoning step is judged by the reply, whichever way', () {
    final l10n = AppLocalizationsEn();
    expect(thinkingStep(l10n, asked: false, reasoned: false), (
      ok: true,
      text: l10n.aiStepThinkingOff,
    ));
    expect(thinkingStep(l10n, asked: false, reasoned: true), (
      ok: false,
      text: l10n.aiStepThinkingStillOn,
    ));
    expect(thinkingStep(l10n, asked: true, reasoned: true), (
      ok: true,
      text: l10n.aiStepThinkingOn,
    ));
    // A relay that drops the request for thinking says nothing — but an
    // adaptive model may also skip thinking on a request this small, so it
    // is undecided rather than failed.
    expect(thinkingStep(l10n, asked: true, reasoned: false), (
      ok: null,
      text: l10n.aiStepThinkingNotOn,
    ));
  });
}
