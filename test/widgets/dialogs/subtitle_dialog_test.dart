import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/ai/edit_action_dialog.dart';

/// SubtitleDialog had no test and could not be opened in a debug build
/// without tripping a framework assertion: its CheckboxListTile sat directly
/// on the glass dialog's DecoratedBox, and a ListTile paints its ink on the
/// nearest Material, so there was nothing to catch the splash.
///
/// Driven through EditActionDialog, which is how the app reaches it, so the
/// naming the rule produces is asserted end to end.
const _baseDir = '/work';

OrganizeAction _subtitle() => OrganizeAction(
  source: 'flat/loose.srt',
  target: 'Movies/Dune/loose.srt',
  kind: 'subtitle',
  confidence: 0.9,
  note: '',
);

String _fwd(String s) => s.replaceAll('\\', '/');

void main() {
  Future<void> openSubtitleRule(WidgetTester tester) async {
    // The app enforces a 1024x700 minimum window; the 800x600 test default is
    // not a configuration these dialogs have to fit.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => EditActionDialog.show(
                context,
                action: _subtitle(),
                baseDir: _baseDir,
                videoTargets: const ['Movies/Dune/Dune.mkv'],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Jellyfin Subtitle...'));
    await tester.pumpAndSettle();
  }

  String target(WidgetTester tester) => _fwd(
    tester.widget<TextField>(find.byType(TextField).first).controller!.text,
  );

  testWidgets('the dialog opens without tripping the ListTile assertion', (
    tester,
  ) async {
    await openSubtitleRule(tester);

    // The video it is anchored to, the language it defaults to, and the
    // checkbox that used to be the problem.
    expect(find.text('Dune.mkv'), findsWidgets);
    expect(find.textContaining('zh-Hans'), findsWidgets);
    expect(find.text('Default'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('apply builds <video>.<lang>.<ext> in the target folder', (
    tester,
  ) async {
    await openSubtitleRule(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(target(tester), 'Movies/Dune/Dune.zh-Hans.srt');
  });

  testWidgets('the default flag adds the .default Jellyfin suffix', (
    tester,
  ) async {
    await openSubtitleRule(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(target(tester), 'Movies/Dune/Dune.zh-Hans.default.srt');
  });

  testWidgets('the chosen language is the one that lands in the name', (
    tester,
  ) async {
    await openSubtitleRule(tester);

    await tester.tap(find.textContaining('zh-Hans').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('en').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(target(tester), 'Movies/Dune/Dune.en.srt');
  });

  testWidgets('cancel leaves the target alone', (tester) async {
    await openSubtitleRule(tester);

    // Two dialogs are open, so two Cancel buttons: the subtitle one is the
    // later route and therefore the last match.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    // Cancelling the rule leaves EditActionDialog open and the target as it
    // was -- a dismissed rule must not rewrite anything.
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(target(tester), 'Movies/Dune/loose.srt');
  });
}
