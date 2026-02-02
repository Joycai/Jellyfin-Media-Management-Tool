import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jellyfin_media_management_tool/main.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final settingsService = SettingsService();
    
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settingsService,
        child: const MyApp(),
      ),
    );

    // Verify that the navigation rail destinations are present
    expect(find.byIcon(Icons.folder_copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}