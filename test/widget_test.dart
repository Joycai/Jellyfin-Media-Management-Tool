import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jellyfin_media_management_tool/main.dart';
import 'package:jellyfin_media_management_tool/services/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/font_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';

void main() {
  testWidgets('Fresh install shows the onboarding welcome step', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService(),
          ),
          ChangeNotifierProvider<AiProfilesService>.value(
            value: AiProfilesService(),
          ),
          ChangeNotifierProvider<AiService>.value(value: AiService()),
          ChangeNotifierProvider<FontService>.value(value: FontService()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider(create: (_) => FileBrowserService()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    // Welcome copy from the first onboarding step.
    expect(find.text('Welcome to Jellyfin Organizer'), findsOneWidget);
    expect(find.text('Get started →'), findsOneWidget);
  });
}
