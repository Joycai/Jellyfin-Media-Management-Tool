import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_merge.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_cache.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_fetcher.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/image_gallery.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/scrape_review_pane.dart';

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
Future<(ScrapeCommitDecision? Function(), Map<String, String>? Function())>
_open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  ScrapeCommitDecision? decision;
  Map<String, String>? saved;
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
        body: ScrapeReviewPane(
          result: _result(),
          defaultTargetDir: '/work',
          defaultNfoFileName: 'SPSF-43.nfo',
          // No network in a widget test: every tile stays a placeholder, which
          // is exactly what an unreachable image host would also produce.
          cache: ScrapeImageCache(
            fetcher: PageFetcher(minIntervalMs: 0),
            referer: Uri.parse('https://e.test/product/1'),
          ),
          onBack: () {},
          onCancel: () {},
          onSaveImages: (names) async => saved = names,
          onSubmit: (d) => decision = d,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (() => decision, () => saved);
}

/// The Write button's label now carries the field/image counts, so the stable
/// landmark is its save icon rather than a fixed string.
final _writeButton = find.widgetWithIcon(FilledButton, Icons.save_outlined);

void main() {
  testWidgets('shows both sides of every field that differs', (tester) async {
    final (_, _) = await _open(tester);

    // Twice: once in the row's "on disk" cell, once in the header, which shows
    // the title as it currently stands after the merge plan.
    expect(find.text('Old Title'), findsNWidgets(2));
    expect(find.text('New Title'), findsOneWidget);
    expect(find.text('SPSF-43'), findsOneWidget);
    // A note the user should see, not a silent degradation.
    expect(find.textContaining('No recipe matched'), findsOneWidget);
  });

  testWidgets('going back submits nothing at all', (tester) async {
    // The pane never writes and never decides on its own: only Write hands a
    // decision up. Back returns to the panel's setup stage with the disk
    // untouched.
    final (decision, saved) = await _open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();

    expect(decision(), isNull);
  });

  testWidgets('every image the page offered gets a tile', (tester) async {
    // A chip listed a URL and left you to guess whether it was the cover or a
    // banner ad. The tile is the whole point of the grid, even before its
    // bytes arrive.
    final (_, _) = await _open(tester);

    expect(find.byType(ImageGallery), findsOneWidget);
    // Scoped to the grid: the field table also carries a "Poster" row, which
    // answers a different question — which URL goes in the NFO, rather than
    // whether to download it.
    expect(
      find.descendant(
        of: find.byType(ImageGallery),
        matching: find.text('Poster (folder)'),
      ),
      findsOneWidget,
    );
    // No network in a widget test, so each tile shows its placeholder.
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
  });

  testWidgets('select-none clears the artwork, and Write agrees', (
    tester,
  ) async {
    final (decision, saved) = await _open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'None'));
    await tester.pumpAndSettle();
    await tester.tap(_writeButton);
    await tester.pumpAndSettle();

    expect(decision()!.images.poster, isFalse);
    expect(decision()!.images.fanart, isFalse);
    expect(decision()!.images.extraFanart, isEmpty);
  });

  testWidgets('the defaults keep a conflict and take a new field', (
    tester,
  ) async {
    final (decision, saved) = await _open(tester);

    await tester.tap(_writeButton);
    await tester.pumpAndSettle();

    final written = decision()!.metadata;
    expect(written.title, 'Old Title', reason: 'conflict defaults to keep');
    expect(written.code, 'SPSF-43', reason: 'blank field defaults to replace');
    expect(written.genres, ['Drama', 'Action'], reason: 'lists merge');
    expect(decision()!.targetDir, '/work');
    expect(decision()!.nfoFileName, 'SPSF-43.nfo');
  });

  testWidgets('the replace-all preset overrides the conflict', (tester) async {
    final (decision, saved) = await _open(tester);

    // The presets are pill chips now, not OutlinedButtons.
    await tester.tap(find.text('Replace all'));
    await tester.pump();
    await tester.tap(_writeButton);
    await tester.pumpAndSettle();

    expect(decision()!.metadata.title, 'New Title');
    expect(decision()!.metadata.genres, ['Action']);
  });

  testWidgets('a per-field decision beats the default', (tester) async {
    final (decision, saved) = await _open(tester);

    // The `title` row's Replace segment — the first "Replace" on screen, since
    // rows follow MetadataField.all order and title is first.
    await tester.tap(find.text('Replace').first);
    await tester.pump();
    await tester.tap(_writeButton);
    await tester.pumpAndSettle();

    expect(decision()!.metadata.title, 'New Title');
    // Untouched rows keep their own defaults.
    expect(decision()!.metadata.genres, ['Drama', 'Action']);
  });

  testWidgets('artwork is selected by default so a poster gets written', (
    tester,
  ) async {
    final (decision, saved) = await _open(tester);

    await tester.tap(_writeButton);
    await tester.pumpAndSettle();

    expect(decision()!.images.poster, isTrue);
  });
}
