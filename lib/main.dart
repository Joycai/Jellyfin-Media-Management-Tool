import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'services/ai_profiles_service.dart';
import 'services/ai_service.dart';
import 'services/file_browser_service.dart';
import 'services/font_service.dart';
import 'services/history_service.dart';
import 'services/settings_service.dart';
import 'services/task_service.dart';
import 'theme/app_theme.dart';
import 'widgets/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required by media_kit (video preview playback).
  MediaKit.ensureInitialized();

  // The layout has fixed-width panes (sidebar 244 + AI panel 352); below
  // ~1024 logical px the center pane collapses and the header overflows.
  // Cap the window at an iPad-class minimum instead of letting it shrink
  // into a broken state.
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(1024, 700));

  // Init the AI profiles service FIRST so its one-time legacy-config.json
  // migration runs before SettingsService writes a config.json without the
  // ai_services / active_ai_service keys.
  final aiProfilesService = AiProfilesService();
  await aiProfilesService.init();

  final settingsService = SettingsService();
  await settingsService.init();

  // Register the user's chosen UI font (if previously downloaded) before the
  // first frame so the app doesn't flash the system font.
  final fontService = FontService();
  await fontService.init();
  await fontService.loadIfDownloaded(
    AppFontChoiceX.fromId(settingsService.fontChoice),
  );

  final aiService = AiService();
  aiService.updateConfig(aiProfilesService.aiConfig);

  final historyService = HistoryService();
  // Best-effort initial load; UI is fine before this completes.
  unawaited(historyService.refresh());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: fontService),
        ChangeNotifierProvider.value(value: aiProfilesService),
        ChangeNotifierProvider.value(value: aiService),
        ChangeNotifierProvider.value(value: historyService),
        ChangeNotifierProvider(create: (_) => TaskService()),
        ChangeNotifierProvider(create: (_) => FileBrowserService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final fonts = context.watch<FontService>();
    final fontFamily = fonts.familyFor(
      AppFontChoiceX.fromId(settings.fontChoice),
    );

    return MaterialApp(
      title: 'Jellyfin Media Management Tool',
      themeMode: settings.themeMode,
      locale: settings.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      theme: AppTheme.light(
        accent: settings.accentColor == null
            ? null
            : Color(settings.accentColor!),
        glassIntensity: settings.glassIntensity,
        fontFamily: fontFamily,
      ),
      darkTheme: AppTheme.dark(
        accent: settings.accentColor == null
            ? null
            : Color(settings.accentColor!),
        glassIntensity: settings.glassIntensity,
        fontFamily: fontFamily,
      ),
      home: settings.onboardingSeen
          ? const HomeScreen()
          : const OnboardingScreen(),
    );
  }
}
