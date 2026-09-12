import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/font_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_appearance_section.dart';
import 'package:provider/provider.dart';

/// The appearance page stacks three equal-height theme cards inside a
/// ListView, which is exactly the shape that makes `CrossAxisAlignment.stretch`
/// throw on an unbounded height — and a layout throw here blanks the whole page
/// while the console stays quiet. Worth a test of its own.
void main() {
  testWidgets('every block lays out inside the scrolling page', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService(),
          ),
          ChangeNotifierProvider<FontService>.value(value: FontService()),
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
          home: const Scaffold(body: AppearanceSection()),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Accent color'), findsOneWidget);
    expect(find.text('Behavior'), findsOneWidget);
  });
}
