import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/ai_service_profile.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_services_screen.dart';
import 'package:provider/provider.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  late Directory tempDir;
  late AiProfilesService profiles;
  late AiService ai;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ai_profiles_view_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async => tempDir.path);
    profiles = AiProfilesService();
    ai = AiService();
  });

  tearDown(() async {
    profiles.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpView(WidgetTester tester) async {
    // The view is a 360px list beside a detail pane; at the default 800x600
    // the header buttons overflow and the overflow itself fails the test.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AiProfilesService>.value(value: profiles),
          ChangeNotifierProvider<AiService>.value(value: ai),
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
          home: const Scaffold(body: AiServicesView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The profile store saves on a 250ms debounce; leaving that timer
    // pending outlives the widget tree and fails the test.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a configured service can be made the active one', (
    tester,
  ) async {
    final local = await profiles.add(AiServiceProfile.create(name: 'Local'));
    await profiles.add(AiServiceProfile.create(name: 'Cloud'));
    // Adding activates what it added, so the second profile is live and the
    // first is the one the user has to be able to switch back to.
    expect(profiles.activeId, isNot(local.id));

    await pumpView(tester);
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();

    // Without this control the active profile could only be changed by
    // editing ai_profiles.json by hand.
    await tester.tap(find.text('Use this service'));
    await tester.pumpAndSettle();

    expect(profiles.activeId, local.id);
    // The live service follows immediately, not on the next app launch.
    expect(ai.config.model, profiles.aiConfig.model);
    // Nothing left to switch to on the profile already in use.
    expect(find.text('Use this service'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('the active service offers no redundant switch', (tester) async {
    await profiles.add(AiServiceProfile.create(name: 'Only'));

    await pumpView(tester);

    expect(find.text('Only'), findsWidgets);
    expect(find.text('Use this service'), findsNothing);
  });
}
