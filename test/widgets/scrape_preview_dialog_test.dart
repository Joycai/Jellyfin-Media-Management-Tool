import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_merge.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/scrape_preview_dialog.dart';

/// A scrape that conflicts with the NFO on disk on `title`, adds `code`, and
/// brings a list field — one instance of each merge default.
ScrapeResult _result() {
  final existing = MediaMetadata(title: 'Old Title', genres: ['Drama']);
  final scraped = MediaMetadata()
    ..set(MetadataField.title, 'New Title', FieldOrigin.recipe)
    ..set(MetadataField.code, 'SPSF-43', FieldOrigin.recipe)
    ..set(MetadataField.genres, ['Action'], FieldOrigin.recipe)
    ..set(MetadataField.poster, 'https://e.test/p.jpg', FieldOrigin.recipe);

  return ScrapeResult(
    scraped: scraped,
    existing: existing,
    mergePlan: NfoMerge.suggest(existing, scraped),
    pageUrl: Uri.parse('https://e.test/product/1'),
    recipe: null,
    notes: const [ScrapeNote.noRecipe],
  );
}

/// Opens the dialog and hands back a getter for whatever it returned. Null
/// means the user cancelled — and therefore that nothing should be written.
Future<ScrapeCommitDecision? Function()> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  ScrapeCommitDecision? decision;
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                decision = await showScrapePreviewDialog(
                  context,
                  result: _result(),
                  defaultTargetDir: '/work',
                  defaultNfoFileName: 'SPSF-43.nfo',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => decision;
}

void main() {
  testWidgets('shows both sides of every field that differs', (tester) async {
    await _open(tester);

    // Twice: once in the row's "on disk" cell, once in the header, which shows
    // the title as it currently stands after the merge plan.
    expect(find.text('Old Title'), findsNWidgets(2));
    expect(find.text('New Title'), findsOneWidget);
    expect(find.text('SPSF-43'), findsOneWidget);
    // A note the user should see, not a silent degradation.
    expect(find.textContaining('No recipe matched'), findsOneWidget);
  });

  testWidgets('cancel returns nothing at all', (tester) async {
    final decision = await _open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(decision(), isNull);
  });

  testWidgets('the defaults keep a conflict and take a new field', (
    tester,
  ) async {
    final decision = await _open(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    final written = decision()!.metadata;
    expect(written.title, 'Old Title', reason: 'conflict defaults to keep');
    expect(written.code, 'SPSF-43', reason: 'blank field defaults to replace');
    expect(written.genres, ['Drama', 'Action'], reason: 'lists merge');
    expect(decision()!.targetDir, '/work');
    expect(decision()!.nfoFileName, 'SPSF-43.nfo');
  });

  testWidgets('the replace-all preset overrides the conflict', (tester) async {
    final decision = await _open(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Replace all'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(decision()!.metadata.title, 'New Title');
    expect(decision()!.metadata.genres, ['Action']);
  });

  testWidgets('a per-field decision beats the default', (tester) async {
    final decision = await _open(tester);

    // The `title` row's Replace segment — the first "Replace" on screen, since
    // rows follow MetadataField.all order and title is first.
    await tester.tap(find.text('Replace').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(decision()!.metadata.title, 'New Title');
    // Untouched rows keep their own defaults.
    expect(decision()!.metadata.genres, ['Drama', 'Action']);
  });

  testWidgets('artwork is selected by default so a poster gets written', (
    tester,
  ) async {
    final decision = await _open(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(decision()!.images.poster, isTrue);
  });
}
