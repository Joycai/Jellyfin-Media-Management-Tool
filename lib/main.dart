import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import './services/ai/ai_profiles_service.dart';
import './services/ai/ai_service.dart';
import './widgets/home/home_screen.dart';
import 'l10n/app_localizations.dart';
import 'services/file_browser_service.dart';
import 'services/font_service.dart';
import 'services/history_service.dart';
import 'services/organize/organize_workspace.dart';
import 'services/scrape/recipe_store.dart';
import 'services/scrape/scrape_service.dart';
import 'services/settings_service.dart';
import 'services/task_service.dart';
import 'theme/app_theme.dart';
import 'widgets/onboarding/onboarding_screen.dart';
import 'widgets/shell/window_state.dart';
import 'widgets/ui/glass_cover.dart';

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

  // Design spec 2.1: ONE 48px bar carries the brand, the section tabs, the
  // search field, the actions AND the window controls — so the OS title bar
  // has to go. Windows and Linux get our own caption buttons (46x48, drawn to
  // the spec in `WindowCaptionButtons`); macOS keeps the system traffic
  // lights, which are the only correct-looking option there, and the bar
  // simply reserves 84px on the left for them.
  //
  // The frame itself stays: `TitleBarStyle.hidden` keeps WS_THICKFRAME /
  // the titled NSWindow, so resize edges, the system shadow and the OS's own
  // rounded corners all still work. That is why `AppShell` does not clip.
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: defaultTargetPlatform == TargetPlatform.macOS,
  );

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

  // Remembered group decisions and preview corrections. Pruning is best
  // effort: an old cache costs disk, never correctness.
  final organizeWorkspace = OrganizeWorkspace();
  unawaited(organizeWorkspace.prune().catchError((Object _) {}));
  final aiService = AiService(workspace: organizeWorkspace);
  aiService.updateConfig(aiProfilesService.aiConfig);
  // A task that had to check whether its model calls tools records the answer
  // on the profiles, so the next task (and Settings) need not check again.
  aiService.onToolSupport = (config, supported) {
    if (aiProfilesService.recordToolSupport(config, supported)) {
      aiService.updateConfig(aiProfilesService.aiConfig);
    }
  };

  final historyService = HistoryService();
  // Best-effort initial load; UI is fine before this completes.
  unawaited(historyService.refresh());

  // Also best-effort: until scrapers.json is read, `forUrl` falls back to the
  // built-in recipes, so nothing has to wait on this. Deliberately last —
  // scraping is independent of the AiProfiles-before-Settings ordering above,
  // and inserting anything between those two would break the migration.
  final recipeStore = RecipeStore();
  unawaited(recipeStore.init());
  // One store instance for both: the settings page edits the same recipes the
  // scraper selects from.
  final scrapeService = ScrapeService(recipes: recipeStore);

  // Focused / maximized / full-screen, read once and shared. Attaching one
  // listener rather than one per widget: window_manager dispatches to every
  // registered listener on every event, and they all want the same answer.
  final windowState = WindowStateNotifier();
  unawaited(windowState.attach());

  // 谁盖住了谁 —— GlassSurface 用它跳过看不见的模糊。观察者必须先于 Navigator
  // 存在，所以在这里造，而不是在某个 widget 的 build 里。
  final glassCover = OpaqueCoverObserver();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: fontService),
        ChangeNotifierProvider.value(value: aiProfilesService),
        ChangeNotifierProvider.value(value: aiService),
        ChangeNotifierProvider.value(value: historyService),
        ChangeNotifierProvider.value(value: recipeStore),
        ChangeNotifierProvider.value(value: scrapeService),
        ChangeNotifierProvider(create: (_) => TaskService()),
        ChangeNotifierProvider(create: (_) => FileBrowserService()),
      ],
      child: WindowStateScope(
        notifier: windowState,
        child: MyApp(glassCover: glassCover),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.glassCover});

  final OpaqueCoverObserver glassCover;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final fonts = context.watch<FontService>();
    final fontFamily = fonts.familyFor(
      AppFontChoiceX.fromId(settings.fontChoice),
    );

    return GlassCoverScope(
      notifier: glassCover,
      child: MaterialApp(
        navigatorObservers: [glassCover],
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
          bakedGlass: settings.bakedGlass,
          fontFamily: fontFamily,
        ),
        darkTheme: AppTheme.dark(
          accent: settings.accentColor == null
              ? null
              : Color(settings.accentColor!),
          glassIntensity: settings.glassIntensity,
          bakedGlass: settings.bakedGlass,
          fontFamily: fontFamily,
        ),
        home: settings.onboardingSeen
            ? const HomeScreen()
            : const OnboardingScreen(),
      ),
    );
  }
}
