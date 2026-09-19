import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations_en.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_capability_matrix.dart';

void main() {
  final l10n = AppLocalizationsEn();
  final model = AiModelEntry.create(
    upstream: 'glm-4.6',
    route: AiProviderType.openAi,
  );
  final channel = AiChannel.create(
    platform: PlatformProfiles.zhipu,
    name: 'z',
    apiKey: 'k',
  ).withModel(model);

  CapabilityCell cell(AiModelEntry m, AiProviderType p, Capability c) =>
      capabilityCell(l10n, channel.withModel(m), m, p, c);

  test('a platform switch is named in the reasoning row', () {
    final value = cell(model, AiProviderType.openAi, Capability.thinkingOff);
    expect(value.state, CapabilityState.works);
    expect(value.text, contains('thinking'));
  });

  test('tool calling reads the measurement on that route', () {
    expect(
      cell(model, AiProviderType.openAi, Capability.tools).state,
      CapabilityState.unmeasured,
    );
    final measured = model.withCurrentParams(
      RouteParams.fromConfig(channel.configFor(model).withToolSupport(true)),
    );
    expect(
      cell(measured, AiProviderType.openAi, Capability.tools).state,
      CapabilityState.works,
    );
  });

  test('a route the channel does not have shows nothing measured', () {
    final measured = model.withCurrentParams(
      RouteParams.fromConfig(channel.configFor(model).withToolSupport(true)),
    );
    // Only Chat Completions is enabled; its measurement is not Anthropic's.
    expect(
      cell(measured, AiProviderType.anthropic, Capability.tools).state,
      CapabilityState.unmeasured,
    );
  });

  test('each protocol answers the questions it has its own way', () {
    expect(
      cell(model, AiProviderType.anthropic, Capability.json).text,
      l10n.aiCellPromptOnly,
    );
    expect(
      cell(model, AiProviderType.anthropic, Capability.thinkingOff).text,
      l10n.aiCellDefaultOff,
    );
    expect(
      cell(model, AiProviderType.openAiResponses, Capability.thinkingOff).state,
      CapabilityState.unmeasured,
    );
  });

  test('image input the user has not allowed says so', () {
    expect(
      cell(model, AiProviderType.openAi, Capability.image).text,
      l10n.aiCellNotAllowed,
    );
  });
}
