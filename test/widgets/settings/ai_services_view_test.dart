import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
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
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService(),
          ),
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

  /// A flat profile as older builds stored it.
  Map<String, dynamic> legacy(String id, String name, String endpoint) => {
    'id': id,
    'name': name,
    'provider': 'openai',
    'endpoint': endpoint,
    'api_key': '',
    'model': 'qwen3.6-27b',
  };

  testWidgets('a migrated profile shows as a channel with no route UI', (
    tester,
  ) async {
    profiles.loadFromMap({
      'ai_services': [legacy('p1', 'Local', 'http://localhost:1234/v1')],
      'active_ai_service': 'p1',
    });

    await pumpView(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('qwen3.6-27b'), findsWidgets);
    // One route: the channel looks and behaves exactly as the profile did,
    // with no protocol chips anywhere on the card.
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Chat Completions'), findsNothing);
  });

  testWidgets('a task can be pointed at another model', (tester) async {
    profiles.loadFromMap({
      'ai_services': [
        legacy('a', 'Local', 'http://task-a:1234/v1'),
        {...legacy('b', 'Cloud', 'http://task-b:1234/v1'), 'model': 'glm-4.6'},
      ],
      'active_ai_service': 'a',
    });
    await pumpView(tester);

    // The scrape-learn picker is the second one; it starts on "follow".
    final pickers = find.byType(DropdownButtonFormField<String?>);
    await tester.tap(pickers.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('glm-4.6').last);
    await tester.pumpAndSettle();

    expect(profiles.tasks[AiTask.scrapeLearn], 'b');
    expect(profiles.resolve(AiTask.organize)?.model.id, 'a');
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('adding a channel starts from the platform', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('Add channel').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    // A vendor needs its key before the channel can be added.
    await tester.enterText(find.byType(TextField).first, 'sk-deepseek');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add channel').last);
    await tester.pumpAndSettle();

    final channel = profiles.channels.single;
    expect(channel.platform.id, 'deepseek');
    expect(channel.apiKey, 'sk-deepseek');
    // Every protocol the platform offers is created, primary first.
    expect(channel.routes.map((r) => r.protocol), [
      AiProviderType.openAi,
      AiProviderType.anthropic,
    ]);
    // The channel page opens on the new channel.
    expect(find.text('Routes'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('switching route parks the old parameters', (tester) async {
    final model = AiModelEntry.create(
      upstream: 'gemini-2.5-flash',
      route: AiProviderType.googleGenAi,
    ).withCurrentParams(const RouteParams(maxOutputTokens: 8192));
    final channel =
        AiChannel.create(
          platform: PlatformProfiles.google,
          name: 'Gemini',
          apiKey: 'k',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.googleGenAi),
            AiRoute(protocol: AiProviderType.openAi),
          ],
          models: [model],
        );
    await profiles.addChannel(channel);
    await pumpView(tester);

    await tester.tap(find.text('gemini-2.5-flash').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat Completions').first);
    await tester.pumpAndSettle();

    // The new route was never configured: nothing is carried over.
    expect(find.text('not set · not sent'), findsWidgets);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    final moved = profiles.modelById(model.id)!.model;
    expect(moved.route, AiProviderType.openAi);
    expect(moved.current.maxOutputTokens, isNull);
    expect(moved.params[AiProviderType.googleGenAi]?.maxOutputTokens, 8192);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('the capability matrix says what this build cannot send', (
    tester,
  ) async {
    final model = AiModelEntry.create(
      upstream: 'qwen-plus',
      route: AiProviderType.openAi,
    );
    await profiles.addChannel(
      AiChannel.create(
        platform: PlatformProfiles.dashScope,
        name: 'Bailian',
        apiKey: 'k',
      ).withModel(model),
    );
    await pumpView(tester);

    await tester.tap(find.text('qwen-plus').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capability matrix →'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // DashScope's own switch is named, its Anthropic route has no JSON
    // parameter, and image input was never allowed.
    expect(find.text('enable_thinking · platform switch'), findsOneWidget);
    expect(find.text('no parameter · prompt only'), findsOneWidget);
    expect(find.text('not allowed'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
