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

  Future<AiModelEntry> pump(WidgetTester tester) async {
    final model = AiModelEntry.create(
      upstream: 'qwen-plus',
      route: AiProviderType.openAi,
    );
    final channel = AiChannel.create(
      platform: PlatformProfiles.dashScope,
      name: 'Bailian',
      apiKey: 'sk-abcdefgh1234',
    ).withModel(model);
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
}
