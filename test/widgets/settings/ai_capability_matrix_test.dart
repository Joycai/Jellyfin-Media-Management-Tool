import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations_en.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
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

  test('a model that refused the switch off always reasons', () {
    final provider = AiService.providerFor(channel.configFor(model));
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.openAi.id,
        base: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.6',
        apiKey: 'k',
      ),
      (b) => b.copyWith(thinkingOffTried: {LearnedBehaviour.dialectOff}),
    );
    expect(provider.learned.thinkingOffTried, {
      LearnedBehaviour.dialectOff,
    }, reason: 'the test wrote the route the matrix reads');

    final value = cell(model, AiProviderType.openAi, Capability.thinkingOff);
    expect(value.state, CapabilityState.unavailable);
    expect(value.text, l10n.aiCellAlwaysReasons);
  });

  test('a switch refused under another platform is no ladder step', () {
    // The route key has no platform in it: this route was a Zhipu one when
    // the switch was refused, and one ladder step has been tried since.
    final local = AiChannel.create(
      platform: PlatformProfiles.lmStudio,
      name: 'l',
      baseUrl: 'http://matrix-ladder:1234',
    ).withModel(model);
    final provider = AiService.providerFor(local.configFor(model));
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.openAi.id,
        base: 'http://matrix-ladder:1234/v1',
        model: 'glm-4.6',
        apiKey: '',
      ),
      (b) => b.copyWith(
        thinkingOffTried: {LearnedBehaviour.dialectOff, 'templateKwargs'},
      ),
    );
    expect(
      provider.learned.thinkingOffTried,
      hasLength(2),
      reason: 'the test wrote the route the matrix reads',
    );

    final value = capabilityCell(
      l10n,
      local,
      model,
      AiProviderType.openAi,
      Capability.thinkingOff,
    );
    expect(value.state, CapabilityState.unmeasured);
    expect(value.text, l10n.aiCellLadder);
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
