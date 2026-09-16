import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/ai/organize_preview_dialog.dart';
import 'package:jellyfin_media_management_tool/widgets/glass/glass_dialog.dart';

OrganizePlan _plan() => OrganizePlan(
  mediaType: 'movie',
  targetRoot: 'Movies',
  reasoning: const [],
  actions: [
    OrganizeAction(
      source: 'Dune2/Dune.Part.Two.2024.mkv',
      target: 'Movies/Dune Part Two (2024)/Dune Part Two (2024).mkv',
      kind: 'video',
      confidence: 0.93,
      note: '',
    ),
  ],
);

Future<void> _open(
  WidgetTester tester, {
  Size surface = const Size(1400, 900),
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      locale: locale,
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => OrganizePreviewDialog.show(
                context,
                plan: _plan(),
                baseDir: '/media',
                totalBytes: 616 * 1024 * 1024,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the apply button sits flush with the dialog edge', (
    tester,
  ) async {
    // The footer row ends where the header does: at the card's 24px padding.
    // A regression here reads as the primary action floating mid-dialog.
    await _open(tester);

    final surfaceRight = tester.getTopRight(find.byType(GlassDialogSurface)).dx;
    final applyRight = tester
        .getTopRight(find.widgetWithIcon(FilledButton, Icons.auto_awesome))
        .dx;

    expect(surfaceRight - applyRight, closeTo(24, 1));
  });

  testWidgets('flush also holds in zh on a wide window', (tester) async {
    // The report came from a zh build on a large display — pin that exact
    // combination so a locale- or width-dependent regression cannot hide.
    await _open(
      tester,
      surface: const Size(2560, 1400),
      locale: const Locale('zh'),
    );

    final surfaceRight = tester.getTopRight(find.byType(GlassDialogSurface)).dx;
    final applyRight = tester
        .getTopRight(find.widgetWithIcon(FilledButton, Icons.auto_awesome))
        .dx;

    expect(surfaceRight - applyRight, closeTo(24, 1));
  });

  testWidgets('the adjust-rules button opens the rule editor', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Adjust rules'));
    await tester.pumpAndSettle();

    expect(find.text('Naming rule · Movies'), findsOneWidget);
    // Nothing behind the Save button yet: it only closes the editor.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Naming rule · Movies'), findsNothing);
  });
}
