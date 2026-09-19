import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_add_channel_dialog.dart';

void main() {
  List<AiProviderType> routes(PlatformProfile p) => [
    for (final route in initialRoutes(p)) route.protocol,
  ];

  test('a vendor starts with every route this build can speak', () {
    expect(routes(PlatformProfiles.google), [
      AiProviderType.googleGenAi,
      AiProviderType.openAi,
    ]);
  });

  test('the platform\'s primary protocol comes first', () {
    expect(routes(PlatformProfiles.dashScope), [
      AiProviderType.openAi,
      AiProviderType.anthropic,
    ]);
    expect(routes(PlatformProfiles.xai), [
      AiProviderType.openAiResponses,
      AiProviderType.openAi,
    ]);
    expect(routes(PlatformProfiles.anthropic), [AiProviderType.anthropic]);
  });

  test('a relay or custom endpoint starts with its primary route only', () {
    expect(routes(PlatformProfiles.relay), [AiProviderType.openAi]);
    expect(routes(PlatformProfiles.custom), [AiProviderType.openAi]);
  });
}
