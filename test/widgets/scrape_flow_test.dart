import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/metadata/metadata_writer.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_store.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/services/task_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/scrape_flow.dart';
import 'package:provider/provider.dart';

/// Enough markup for tier 1 to find a title, and no network anywhere: the
/// paste path never touches [PageFetcher].
const _html = '''
<html><head><title>SPSF-43</title>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Product",
 "name":"Pasted Title","description":"A synopsis long enough to be real."}
</script>
</head><body><h1>Pasted Title</h1></body></html>
''';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final fs = MemoryFileSystem();
  await fs.directory('/work').create(recursive: true);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
        ChangeNotifierProvider<RecipeStore>.value(value: RecipeStore()),
        ChangeNotifierProvider<AiService>.value(value: AiService()),
        ChangeNotifierProvider<TaskService>.value(value: TaskService()),
        ChangeNotifierProvider<HistoryService>.value(
          value: HistoryService(fs: fs, undoDir: '/undo'),
        ),
        ChangeNotifierProvider<ScrapeService>.value(
          value: ScrapeService(writer: MetadataWriter(fs: fs)),
        ),
      ],
      child: MaterialApp(
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
                onPressed: () => startScrapeFlow(context, baseDir: '/work'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drives the URL dialog down the paste branch, so the whole flow runs offline.
Future<void> _pasteAndScrape(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byType(TextField).first,
    'https://e.test/product/1',
  );
  await tester.tap(find.text('Paste the page HTML instead'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, _html);
  await tester.tap(find.widgetWithText(FilledButton, 'Scrape'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the deferred Review action can still open the preview', (
    tester,
  ) async {
    // A regression test for a crash, not for a feature: the "Review" action is
    // pressed long after the widget that started the flow could be gone, so the
    // context it uses has to be one that outlives it *and* still resolves the
    // messenger, the navigator and the providers. `messenger.context` looks
    // like that context and is not — it is the ScaffoldMessenger element
    // itself, above its own scope and above the navigator, so every lookup off
    // it threw "No ScaffoldMessenger widget found".
    await _pumpApp(tester);
    await _pasteAndScrape(tester);

    // The started notice comes first; let it expire so the ready notice, which
    // carries the Review action, takes its place.
    expect(find.textContaining('Scrape started'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.textContaining('Scrape finished'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Review'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The preview is open (its header shows the scraped title rather than the
    // generic one, so the Write button is the stable landmark) and, being a
    // route, it proves the deferred context resolved a Navigator too.
    expect(find.widgetWithText(FilledButton, 'Write'), findsOneWidget);
    expect(find.textContaining('Pasted Title'), findsWidgets);
  });

  testWidgets('cancelling the preview writes nothing', (tester) async {
    await _pumpApp(tester);
    await _pasteAndScrape(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // No commit task was queued, so nothing is on its way to disk.
    expect(find.textContaining('Writing metadata'), findsNothing);
  });
}
