import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_channel_page.dart';

import '../../helpers/settings.dart';

void main() {
  late AiProfilesService profiles;

  setUp(() {
    useTempSupportDir();
    profiles = AiProfilesService();
  });

  Future<AiChannel> pump(WidgetTester tester, AiChannel channel) async {
    await profiles.addChannel(channel);
    await pumpAiPage(
      tester,
      AiChannelPage(channelId: channel.id, onBack: () {}, onOpenModel: (_) {}),
      profiles: profiles,
    );
    return channel;
  }

  testWidgets('a model is added on the primary route', (tester) async {
    final channel = await pump(
      tester,
      AiChannel.create(
        platform: PlatformProfiles.deepSeek,
        name: 'DeepSeek',
        apiKey: 'k',
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Model name as the server knows it'),
      'deepseek-chat',
    );
    await tester.tap(find.text('Add model'));
    await tester.pumpAndSettle();

    final model = profiles.channelById(channel.id)!.models.single;
    expect(model.upstream, 'deepseek-chat');
    expect(model.route, AiProviderType.openAi);
    // The first model anywhere becomes the organize model.
    expect(profiles.resolve(AiTask.organize)?.model.id, model.id);
    expect(find.text('POST https://api.deepseek.com'), findsOneWidget);
    await settleSaves(tester);
  });

  testWidgets('a route a model runs on cannot be turned off', (tester) async {
    final model = AiModelEntry.create(
      upstream: 'gemini-2.5-flash',
      route: AiProviderType.openAi,
    );
    await pump(
      tester,
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
      ),
    );

    expect(
      find.text('1 model uses this route — it cannot be turned off.'),
      findsOneWidget,
    );
    await settleSaves(tester);
  });

  testWidgets('a path field follows its route when the host moves', (
    tester,
  ) async {
    final channel = await pump(
      tester,
      AiChannel.fromLegacyProfile(
        id: 'p',
        name: 'Local',
        config: const AiConfig(
          provider: AiProviderType.openAi,
          endpoint: 'http://localhost:1234/v1',
          apiKey: '',
          model: 'm',
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'http://localhost:1234'),
      'http://10.0.0.5:1234',
    );
    await tester.pumpAndSettle();

    expect(
      profiles.channelById(channel.id)!.endpointFor(AiProviderType.openAi),
      'http://10.0.0.5:1234/v1',
    );
    // The field shows where the route points now, so the next keystroke in
    // it cannot write the old host back.
    expect(find.text('http://10.0.0.5:1234/v1'), findsWidgets);
    await settleSaves(tester);
  });

  testWidgets('a route the platform offers can be enabled', (tester) async {
    final channel = await pump(
      tester,
      AiChannel.create(
        platform: PlatformProfiles.google,
        name: 'Gemini',
        apiKey: 'k',
      ),
    );

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();

    expect(profiles.channelById(channel.id)!.routes.map((r) => r.protocol), [
      AiProviderType.googleGenAi,
      AiProviderType.openAi,
    ]);
    expect(
      find.text('POST https://generativelanguage.googleapis.com/v1beta/openai'),
      findsOneWidget,
    );
    await settleSaves(tester);
  });
}
