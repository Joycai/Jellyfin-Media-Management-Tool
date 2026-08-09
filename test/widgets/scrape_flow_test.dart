import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/metadata/metadata_writer.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_store.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/services/task_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/scrape_flow.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/scrape_panel.dart';
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
        ChangeNotifierProvider<AiProfilesService>.value(
          value: AiProfilesService(),
        ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () => startScrapeFlow(context, baseDir: '/work'),
                    child: const Text('go'),
                  ),
                  ElevatedButton(
                    onPressed: () => showScrapePanel(
                      context,
                      targetDir: '/work',
                      nfoFileName: 'SPSF-43.nfo',
                      label: 'SPSF-43.mkv',
                      suggestedKeyword: 'SPSF-43',
                    ),
                    child: const Text('go with code'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drives the panel down the paste branch, so the whole flow runs offline.
Future<void> _pasteAndScrape(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byType(TextField).first,
    'https://e.test/product/1',
  );
  // The paste fallback lives behind the Advanced disclosure.
  await tester.tap(find.text('Advanced'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Paste the page HTML instead'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, _html);
  await tester.tap(find.widgetWithText(FilledButton, 'Process'));
  await tester.pumpAndSettle();
}

/// The Write button's label now carries the field/image counts, so the stable
/// landmark is its save icon rather than a fixed string.
final _writeButton = find.widgetWithIcon(FilledButton, Icons.save_outlined);

void main() {
  testWidgets('Process shows the result without a detour', (tester) async {
    // The whole point of the panel. The old flow put a background task and a
    // SnackBar between pressing the button and seeing anything, and the
    // hand-off across them is where a stale BuildContext crashed with
    // "No ScaffoldMessenger widget found". One await, and the preview is up.
    await _pumpApp(tester);
    await _pasteAndScrape(tester);

    expect(tester.takeException(), isNull);
    // The preview header shows the scraped title, so the Write button is the
    // stable landmark. Its being a route also proves a Navigator resolved.
    // The label carries live counts, so the anchor is its save icon.
    expect(_writeButton, findsOneWidget);
    expect(find.textContaining('Pasted Title'), findsWidgets);
  });

  testWidgets('cancelling the preview writes nothing', (tester) async {
    await _pumpApp(tester);
    await _pasteAndScrape(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // No commit task was queued, so nothing is on its way to disk.
    expect(find.textContaining('Writing metadata'), findsNothing);
  });

  testWidgets('cancelling the panel never reaches the preview', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(_writeButton, findsNothing);
    expect(find.widgetWithText(FilledButton, 'Process'), findsNothing);
  });

  testWidgets('a URL without a scheme is refused in place', (tester) async {
    // The panel keeps the user where they are instead of failing later in a
    // task they would have to go and find.
    await _pumpApp(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'example.com/x');
    await tester.tap(find.widgetWithText(FilledButton, 'Process'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Process'), findsOneWidget);
    expect(_writeButton, findsNothing);
  });

  testWidgets('the NFO target is auto-detected and shown', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Twice: once in the path row, once in the auto-matched caption.
    expect(find.textContaining('movie.nfo'), findsWidgets);
    expect(find.text('Browse…'), findsOneWidget);
  });

  testWidgets('no AI profile means no direct-LLM button', (tester) async {
    // Offering a button that can only produce an error is worse than not
    // offering it.
    await _pumpApp(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Ask the LLM directly'), findsNothing);
  });

  testWidgets('a detected code offers the configured search sites', (
    tester,
  ) async {
    // Knowing the catalogue number is not knowing the URL. This came across
    // from the URL dialog the panel replaced, and uses the same site list the
    // user curates in Settings rather than a second table.
    await _pumpApp(tester);
    await tester.tap(find.text('go with code'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SPSF-43'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'TMDB'), findsOneWidget);
  });

  testWidgets('the search links give way once a URL is typed', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('go with code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://e.test/p/1');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'TMDB'), findsNothing);
  });
}
