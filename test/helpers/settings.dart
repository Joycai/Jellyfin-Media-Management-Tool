import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:provider/provider.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

/// Points path_provider at a temporary folder for the test, so the services'
/// debounced saves land somewhere harmless.
Directory useTempSupportDir() {
  final dir = Directory.systemTemp.createTempSync('settings_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProvider, (call) async => dir.path);
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// Pumps [child] with the AI services and settings it reads, on a window
/// wide enough for the two-column AI pages.
Future<void> pumpAiPage(
  WidgetTester tester,
  Widget child, {
  required AiProfilesService profiles,
  AiService? ai,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AiProfilesService>.value(value: profiles),
        ChangeNotifierProvider<AiService>.value(value: ai ?? AiService()),
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets the profile store's 250 ms save debounce fire before the test ends.
Future<void> settleSaves(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 300));
