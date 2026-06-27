import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'services/ai_service.dart';
import 'services/file_browser_service.dart';
import 'services/history_service.dart';
import 'services/settings_service.dart';
import 'services/task_service.dart';
import 'theme/app_theme.dart';
import 'widgets/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final settingsService = SettingsService();
  await settingsService.init();

  final aiService = AiService();
  aiService.updateConfig(settingsService.aiConfig);

  final historyService = HistoryService();
  // Best-effort initial load; UI is fine before this completes.
  unawaited(historyService.refresh());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
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

    return MaterialApp(
      title: 'Jellyfin Media Management Tool',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      locale: settings.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      theme: AppTheme.light(
        accent: settings.accentColor == null ? null : Color(settings.accentColor!),
        glassIntensity: settings.glassIntensity,
      ),
      darkTheme: AppTheme.dark(
        accent: settings.accentColor == null ? null : Color(settings.accentColor!),
        glassIntensity: settings.glassIntensity,
      ),
      home: settings.onboardingSeen ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
