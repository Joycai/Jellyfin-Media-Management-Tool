import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/ai/edit_action_dialog.dart';

/// EditActionDialog is the last gate before a planned move is written, and the
/// only place a user can correct a target path. It was at 0% coverage, as were
/// the rule dialogs it opens. Nothing here touches the filesystem: the dialog
/// rewrites a string and hands it back.
const _baseDir = '/work';

OrganizeAction _action(String target, {String source = 'flat/old.mkv'}) =>
    OrganizeAction(
      source: source,
      target: target,
      kind: 'video',
      confidence: 0.9,
      note: '',
    );

/// Separators differ per host once `path` normalizes; the assertions compare
/// with forward slashes so the suite is not host-dependent.
String _fwd(String s) => s.replaceAll('\\', '/');

void main() {
  late String? result;
  late bool returned;

  Future<void> openDialog(
    WidgetTester tester, {
    required OrganizeAction action,
    List<String> videoTargets = const [],
  }) async {
    result = null;
    returned = false;
    // The app enforces a 1024x700 minimum window, so the 800x600 default test
    // surface is not a configuration the dialog has to fit; with the subtitle
    // rule present the chip Wrap gains a row and overflows it.
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
              onPressed: () async {
                result = await EditActionDialog.show(
                  context,
                  action: action,
                  baseDir: _baseDir,
                  videoTargets: videoTargets,
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ActionChip, label));
    await tester.pumpAndSettle();
  }

  String targetOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  Future<void> setTarget(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField).first, value);
    await tester.pumpAndSettle();
  }

  testWidgets('cancel returns null and changes nothing', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);
  });

  testWidgets('save hands back the normalized target', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await setTarget(tester, '  Dune (2021).mkv  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(_fwd(result!), 'Dune (2021).mkv');
  });

  testWidgets('an empty target is refused in place', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await setTarget(tester, '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The dialog stays open with the reason next to the field rather than
    // popping a value that would fail mid-apply.
    expect(returned, isFalse);
    expect(find.textContaining('Invalid path'), findsOneWidget);
  });

  testWidgets('a target that escapes the folder is refused', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await setTarget(tester, '../../outside.mkv');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(returned, isFalse);
    expect(find.textContaining('Invalid path'), findsOneWidget);
  });

  testWidgets('an absolute target is refused', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await setTarget(
      tester,
      Platform.isWindows ? r'C:\Windows\system32\x.mkv' : '/etc/passwd',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(returned, isFalse);
    expect(find.textContaining('Invalid path'), findsOneWidget);
  });

  testWidgets('editing clears a previous error', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await setTarget(tester, '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid path'), findsOneWidget);

    await setTarget(tester, 'Dune.mkv');
    expect(find.textContaining('Invalid path'), findsNothing);
  });

  testWidgets('match-folder rewrites only the filename', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/homevideo.mkv'));

    await tapChip(tester, 'Match Folder Name');

    expect(_fwd(targetOf(tester)), 'Movies/Dune/Dune.mkv');
  });

  testWidgets('featurette and interview suffix the filename', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));
    await tapChip(tester, 'Rename to Featurette');
    expect(_fwd(targetOf(tester)), 'Movies/Dune/Dune-featurette.mkv');

    await tapChip(tester, 'Rename to Interview');
    expect(_fwd(targetOf(tester)), 'Movies/Dune/Dune-interview.mkv');
  });

  testWidgets('the part rule asks for a part number', (tester) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.mkv'));

    await tapChip(tester, 'Rename to Part...');

    // PartDialog is open on top: its custom field is the second TextField.
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(_fwd(targetOf(tester)), 'Movies/Dune/Dune-part2.mkv');
  });

  testWidgets('the TV rule climbs out of the Season folder for its base name', (
    tester,
  ) async {
    await openDialog(
      tester,
      action: _action('Shows/The Expanse/Season 01/episode.mkv'),
    );

    await tapChip(tester, 'Rename to TV Show...');
    // One tap on + takes the episode from 01 to 02.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    // The base name is the series folder, not "Season 01" -- the rule
    // RenameService.baseNameForTarget exists for.
    expect(
      _fwd(targetOf(tester)),
      'Shows/The Expanse/Season 01/The Expanse.S01E02.mkv',
    );
  });

  testWidgets('the subtitle rule needs a subtitle target and a video', (
    tester,
  ) async {
    await openDialog(
      tester,
      action: _action('Movies/Dune/Dune.srt'),
      videoTargets: ['Movies/Dune/Dune.mkv'],
    );

    expect(
      find.widgetWithText(ActionChip, 'Jellyfin Subtitle...'),
      findsOneWidget,
    );
  });

  testWidgets('a video target is offered no subtitle rule', (tester) async {
    await openDialog(
      tester,
      action: _action('Movies/Dune/Dune.mkv'),
      videoTargets: ['Movies/Dune/Dune.mkv'],
    );

    expect(
      find.widgetWithText(ActionChip, 'Jellyfin Subtitle...'),
      findsNothing,
    );
  });

  testWidgets('a subtitle target with no videos to anchor gets no rule', (
    tester,
  ) async {
    await openDialog(tester, action: _action('Movies/Dune/Dune.srt'));

    expect(
      find.widgetWithText(ActionChip, 'Jellyfin Subtitle...'),
      findsNothing,
    );
  });
}
