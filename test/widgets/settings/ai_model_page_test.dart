import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_model_page.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_controls.dart';

import '../../helpers/settings.dart';

void main() {
  late AiProfilesService profiles;

  setUp(() {
    useTempSupportDir();
    profiles = AiProfilesService();
  });

  Future<AiModelEntry> pump(
    WidgetTester tester, {
    PlatformProfile platform = PlatformProfiles.dashScope,
    String upstream = 'qwen-plus',
    AiProviderType route = AiProviderType.openAi,
  }) async {
    final model = AiModelEntry.create(upstream: upstream, route: route);
    final channel = AiChannel.create(
      platform: platform,
      name: 'Bailian',
      apiKey: 'sk-abcdefgh1234',
    ).copyWith(routes: [AiRoute(protocol: route)]).withModel(model);
    await profiles.addChannel(channel);
    await pumpAiPage(
      tester,
      AiModelPage(
        channelId: channel.id,
        modelId: model.id,
        onBack: () {},
        onMatrix: () {},
        onDiagnostics: () {},
      ),
      profiles: profiles,
    );
    return model;
  }

  testWidgets('the preview is the adapter\'s own request', (tester) async {
    await pump(tester);

    final preview = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join();
    expect(
      preview,
      contains(
        'POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      ),
    );
    // The platform's own switch, and a masked key.
    expect(preview, contains('"enable_thinking": false'));
    expect(preview, contains('Bearer sk-…1234'));
    expect(preview, isNot(contains('abcdefgh')));
    await settleSaves(tester);
  });

  testWidgets('image input is a model setting, whatever the route', (
    tester,
  ) async {
    final model = await pump(tester);

    // The toggles on the page, in order: image input, video input, reasoning.
    await tester.tap(find.byType(AppToggle).at(0));
    await tester.pumpAndSettle();

    expect(profiles.modelById(model.id)!.model.imageInput, isTrue);
    await settleSaves(tester);
  });

  testWidgets('a Messages route declared as a switch can be switched', (
    tester,
  ) async {
    // MiniMax-M3 has no sampling preset, so only the platform's switch
    // makes its reasoning toggle live.
    await pump(
      tester,
      platform: PlatformProfiles.miniMax,
      upstream: 'MiniMax-M3',
      route: AiProviderType.anthropic,
    );

    expect(find.text('thinking · from the platform profile'), findsOneWidget);
    // The toggles on the page, in order: image input, video input, reasoning.
    expect(
      tester.widget<AppToggle>(find.byType(AppToggle).at(2)).onChanged,
      isNotNull,
    );
    final preview = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join();
    expect(preview, contains('"disabled"'));
    await settleSaves(tester);
  });

  testWidgets('Messages switches reasoning without a preset or a platform '
      'switch', (tester) async {
    // No sampling preset knows Claude, and the official profile declares no
    // switch: the protocol's own `thinking` field is the switch.
    final model = await pump(
      tester,
      platform: PlatformProfiles.anthropic,
      upstream: 'claude-sonnet-4-5',
      route: AiProviderType.anthropic,
    );

    // Not the local-server ladder: the protocol's own field.
    expect(find.text('thinking · protocol field'), findsOneWidget);
    // The toggles on the page, in order: image input, video input, reasoning.
    final reasoning = find.byType(AppToggle).at(2);
    expect(tester.widget<AppToggle>(reasoning).onChanged, isNotNull);
    await tester.tap(reasoning);
    await tester.pumpAndSettle();

    final entry = profiles.modelById(model.id)!;
    expect(entry.channel.configFor(entry.model).thinkingEnabled, isTrue);
    final preview = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .join();
    expect(preview, contains('"thinking"'));
    await settleSaves(tester);
  });

  testWidgets('Responses switches reasoning without a preset', (tester) async {
    await pump(
      tester,
      platform: PlatformProfiles.openAi,
      upstream: 'gpt-4.1',
      route: AiProviderType.openAiResponses,
    );

    expect(find.text('reasoning.effort · protocol field'), findsOneWidget);
    expect(
      tester.widget<AppToggle>(find.byType(AppToggle).at(2)).onChanged,
      isNotNull,
    );
    await settleSaves(tester);
  });

  testWidgets('without a preset or a documented field, "on" sends nothing, '
      'so the switch stays off', (tester) async {
    for (final (platform, route) in [
      (PlatformProfiles.openAi, AiProviderType.openAi),
      (PlatformProfiles.google, AiProviderType.googleGenAi),
    ]) {
      await pump(tester, platform: platform, upstream: 'x-1', route: route);

      expect(
        tester.widget<AppToggle>(find.byType(AppToggle).at(2)).onChanged,
        isNull,
        reason: '$route',
      );
      expect(
        find.textContaining('local-server ladder'),
        findsOneWidget,
        reason: '$route',
      );
      await settleSaves(tester);
    }
  });
}
