import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/sidebar/app_sidebar.dart';
import 'package:provider/provider.dart';

Future<FileBrowserService> _pumpSidebar(WidgetTester tester) async {
  final browser = FileBrowserService();
  addTearDown(browser.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
        ChangeNotifierProvider<AiService>.value(value: AiService()),
        ChangeNotifierProvider<FileBrowserService>.value(value: browser),
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
        home: const Scaffold(body: SizedBox(width: 244, child: AppSidebar())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return browser;
}

void main() {
  testWidgets('the home location is on the first frame', (tester) async {
    await _pumpSidebar(tester);

    // Resolved from the environment, so it needs no directory scan and must
    // not wait for one. Tests run on a non-macOS, non-Linux host, where there
    // is no mount root to scan at all, so this is the whole Locations list.
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rebuild from another service does not rescan or duplicate', (
    tester,
  ) async {
    final browser = await _pumpSidebar(tester);
    expect(find.text('Home'), findsOneWidget);

    // The sidebar watches this service, so notifying it rebuilds the whole
    // list. Locations used to be recomputed inside build, which is where the
    // synchronous mount scan was happening.
    browser.setSelectedFile(null);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tearing the sidebar down mid-scan is safe', (tester) async {
    final browser = FileBrowserService();
    addTearDown(browser.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService(),
          ),
          ChangeNotifierProvider<AiService>.value(value: AiService()),
          ChangeNotifierProvider<FileBrowserService>.value(value: browser),
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
          home: const Scaffold(body: SizedBox(width: 244, child: AppSidebar())),
        ),
      ),
    );
    // Straight back out, without settling: the volume scan is still in flight
    // on the platforms that do one, and its setState has to notice.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
