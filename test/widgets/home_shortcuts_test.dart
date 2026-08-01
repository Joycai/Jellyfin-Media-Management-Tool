import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/screens/home_screen.dart';
import 'package:jellyfin_media_management_tool/services/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:jellyfin_media_management_tool/services/font_service.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/services/task_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:provider/provider.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
        ChangeNotifierProvider<AiProfilesService>.value(
          value: AiProfilesService(),
        ),
        ChangeNotifierProvider<AiService>.value(value: AiService()),
        ChangeNotifierProvider<FontService>.value(value: FontService()),
        ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
        ChangeNotifierProvider(create: (_) => TaskService()),
        ChangeNotifierProvider(create: (_) => FileBrowserService()),
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
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump();
}

/// Presses [key] with the primary modifier held. Tests run on a non-macOS
/// target platform, so that modifier is Ctrl.
Future<void> _pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

bool _searchHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText).first)
    .focusNode
    .hasFocus;

void main() {
  testWidgets('a shortcut fires on a cold start, before any click', (
    tester,
  ) async {
    // The regression this guards: shortcuts dispatch up the focus chain, so
    // without an autofocused node inside the CallbackShortcuts subtree every
    // binding is dead until the user happens to click something.
    await _pumpHome(tester);
    expect(_searchHasFocus(tester), isFalse);

    await _pressCtrl(tester, LogicalKeyboardKey.keyK);

    expect(_searchHasFocus(tester), isTrue);
  });

  testWidgets('Ctrl+F is an accepted alias for focus-search', (tester) async {
    await _pumpHome(tester);

    await _pressCtrl(tester, LogicalKeyboardKey.keyF);

    expect(_searchHasFocus(tester), isTrue);
  });

  testWidgets('Ctrl+2 switches to the Library section', (tester) async {
    await _pumpHome(tester);

    await _pressCtrl(tester, LogicalKeyboardKey.digit2);

    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('a skipWhileTyping shortcut stands down inside a text field', (
    tester,
  ) async {
    await _pumpHome(tester);
    await _pressCtrl(tester, LogicalKeyboardKey.keyK);
    expect(_searchHasFocus(tester), isTrue);

    await _pressCtrl(tester, LogicalKeyboardKey.digit2);

    // Still on Files: the section shortcut must not fire while typing.
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('Esc clears the search text before giving up focus', (
    tester,
  ) async {
    await _pumpHome(tester);
    await _pressCtrl(tester, LogicalKeyboardKey.keyK);
    await tester.enterText(find.byType(TextField).first, 'dune');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      isEmpty,
    );
    // First Esc only clears the query; focus survives so the user can retype.
    expect(_searchHasFocus(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_searchHasFocus(tester), isFalse);
  });
}
