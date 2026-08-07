import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_store.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/scrape_url_dialog.dart';
import 'package:provider/provider.dart';

Future<ScrapeInput? Function()> _open(
  WidgetTester tester, {
  String? suggestedKeyword,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  ScrapeInput? input;
  var returned = false;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
        ChangeNotifierProvider<RecipeStore>.value(value: RecipeStore()),
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
                onPressed: () async {
                  input = await showScrapeUrlDialog(
                    context,
                    targetLabel: 'SPSF-43.mkv',
                    suggestedKeyword: suggestedKeyword,
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => returned ? input : null;
}

void main() {
  testWidgets('a URL without a scheme is refused, and the dialog stays open', (
    tester,
  ) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField).first, 'example.com/x');
    await tester.tap(find.widgetWithText(FilledButton, 'Scrape'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter a full URL'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Scrape'), findsOneWidget);
  });

  testWidgets('a valid URL comes back with no pasted HTML', (tester) async {
    final result = await _open(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'https://e.test/product/1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Scrape'));
    await tester.pumpAndSettle();

    expect(result()!.url, 'https://e.test/product/1');
    expect(result()!.pastedHtml, isNull);
  });

  testWidgets('the paste fallback carries the HTML and still needs the URL', (
    tester,
  ) async {
    final result = await _open(tester);

    await tester.tap(find.text('Paste the page HTML instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '<html>hi</html>');

    // No URL yet: relative links in the paste would have nothing to resolve
    // against, so this must not be accepted.
    await tester.tap(find.widgetWithText(FilledButton, 'Scrape'));
    await tester.pumpAndSettle();
    expect(result(), isNull);

    await tester.enterText(
      find.byType(TextField).first,
      'https://e.test/product/1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Scrape'));
    await tester.pumpAndSettle();

    expect(result()!.pastedHtml, '<html>hi</html>');
  });

  testWidgets('a detected code offers the configured search sites', (
    tester,
  ) async {
    await _open(tester, suggestedKeyword: 'SPSF-43');

    expect(find.textContaining('SPSF-43'), findsWidgets);
    // The default site list from SettingsService — not a second table.
    expect(find.widgetWithText(OutlinedButton, 'TMDB'), findsOneWidget);
  });
}
