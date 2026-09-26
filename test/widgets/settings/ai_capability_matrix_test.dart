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
    const written = {LearnedBehaviour.dialectOff};
    expect(
      provider.learned.thinkingOffTried,
      written,
      reason: 'the test wrote the route the matrix reads',
    );

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

  test('a ladder that ran out says so', () {
    final local = AiChannel.create(
      platform: PlatformProfiles.lmStudio,
      name: 'l',
      baseUrl: 'http://matrix-ladder-out:1234',
    ).withModel(model);
    final provider = AiService.providerFor(local.configFor(model));
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.openAi.id,
        base: 'http://matrix-ladder-out:1234/v1',
        model: 'glm-4.6',
        apiKey: '',
      ),
      (b) => b.copyWith(thinkingOffTried: {'templateKwargs', 'effortNone'}),
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
    expect(value.state, CapabilityState.unavailable);
    expect(value.text, l10n.aiCellLadderExhausted);
  });

  test('Messages that refused every form of thinking is still off', () {
    // No field to name: the cell must not reach for one.
    final m = AiModelEntry.create(
      upstream: 'claude-sonnet-4-5',
      route: AiProviderType.anthropic,
    );
    final relay =
        AiChannel.create(
              platform: PlatformProfiles.custom,
              name: 'r',
              apiKey: 'k-no-forms',
            )
            .copyWith(
              routes: [
                const AiRoute(
                  protocol: AiProviderType.anthropic,
                  endpoint: 'https://matrix-forms.example',
                ),
              ],
            )
            .withModel(m);
    final provider = AiService.providerFor(relay.configFor(m));
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: 'https://matrix-forms.example/v1',
        model: 'claude-sonnet-4-5',
        apiKey: 'k-no-forms',
      ),
      (b) =>
          b.copyWith(rejectedFields: {'thinking:adaptive', 'thinking:enabled'}),
    );
    expect(
      provider.learned.rejectedFields,
      hasLength(2),
      reason: 'the test wrote the route the matrix reads',
    );

    final value = capabilityCell(
      l10n,
      relay,
      m,
      AiProviderType.anthropic,
      Capability.thinkingOff,
    );
    expect(value.state, CapabilityState.works);
    expect(value.text, l10n.aiCellDefaultOff);
  });

  // Refused `none`, or refused `reasoning` itself: nothing is sent when off.
  for (final (what, learn)
      in <(String, LearnedBehaviour Function(LearnedBehaviour))>[
        (
          'effort none',
          (b) => b.copyWith(thinkingOffTried: {LearnedBehaviour.effortNone}),
        ),
        ('reasoning', (b) => b.copyWith(rejectedFields: {'reasoning'})),
      ]) {
    test('a Responses route that refused $what runs at its default', () {
      final responsesModel = AiModelEntry.create(
        upstream: 'gpt-5.5',
        route: AiProviderType.openAiResponses,
      );
      final responsesChannel =
          AiChannel.create(
                platform: PlatformProfiles.custom,
                name: 'r',
                apiKey: 'k',
              )
              .copyWith(
                routes: [
                  const AiRoute(
                    protocol: AiProviderType.openAiResponses,
                    endpoint: 'https://responses.example/v1',
                  ),
                ],
              )
              .withModel(responsesModel);
      final provider = AiService.providerFor(
        responsesChannel.configFor(responsesModel),
      );
      addTearDown(provider.forgetLearned);
      LearnedStore.instance.update(
        LearnedStore.routeKey(
          protocol: AiProviderType.openAiResponses.id,
          base: 'https://responses.example/v1',
          model: 'gpt-5.5',
          apiKey: 'k',
        ),
        learn,
      );
      expect(
        {
          ...provider.learned.thinkingOffTried,
          ...provider.learned.rejectedFields,
        },
        hasLength(1),
        reason: 'the test wrote the route the matrix reads',
      );

      final value = capabilityCell(
        l10n,
        responsesChannel,
        responsesModel,
        AiProviderType.openAiResponses,
        Capability.thinkingOff,
      );
      expect(value.state, CapabilityState.unavailable);
      expect(value.text, l10n.aiCellModelDefault);
    });
  }

  test('a Messages route with a platform switch names it', () {
    final m = AiModelEntry.create(
      upstream: 'MiniMax-M3',
      route: AiProviderType.anthropic,
    );
    final minimax = AiChannel.create(
      platform: PlatformProfiles.miniMax,
      name: 'mm',
      apiKey: 'k',
    ).withModel(m);
    final value = capabilityCell(
      l10n,
      minimax,
      m,
      AiProviderType.anthropic,
      Capability.thinkingOff,
    );
    expect(value.state, CapabilityState.works);
    expect(value.text, l10n.aiCellSwitch('thinking'));
  });

  test('a platform switch refused by name is sent neither way', () {
    final provider = AiService.providerFor(channel.configFor(model));
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.openAi.id,
        base: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.6',
        apiKey: 'k',
      ),
      (b) => b.copyWith(rejectedFields: {'thinking'}),
    );
    expect(provider.learned.rejectedFields, {'thinking'});

    final value = cell(model, AiProviderType.openAi, Capability.thinkingOff);
    expect(value.state, CapabilityState.unavailable);
    expect(value.text, l10n.aiCellModelDefault);
  });

  test('a Messages switch the model refused off always reasons', () {
    final m = AiModelEntry.create(
      upstream: 'MiniMax-M3',
      route: AiProviderType.anthropic,
    );
    final minimax =
        AiChannel.create(
              platform: PlatformProfiles.miniMax,
              name: 'mm',
              apiKey: 'k-always',
            )
            .copyWith(
              routes: [const AiRoute(protocol: AiProviderType.anthropic)],
            )
            .withModel(m);
    final config = minimax.configFor(m);
    expect(config.provider, AiProviderType.anthropic);
    final provider = AiService.providerFor(config);
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: '${config.endpoint}/v1',
        model: 'MiniMax-M3',
        apiKey: 'k-always',
      ),
      (b) => b.copyWith(thinkingOffTried: {LearnedBehaviour.dialectOff}),
    );
    const written = {LearnedBehaviour.dialectOff};
    expect(
      provider.learned.thinkingOffTried,
      written,
      reason: 'the test wrote the route the matrix reads',
    );

    final value = capabilityCell(
      l10n,
      minimax,
      m,
      AiProviderType.anthropic,
      Capability.thinkingOff,
    );
    expect(value.state, CapabilityState.unavailable);
    expect(value.text, l10n.aiCellAlwaysReasons);
  });

  test('a Messages switch that refused adaptive still sends off', () {
    // On is no longer asked; off is still `disabled`, so the cell is the
    // switch, not the model's default.
    final m = AiModelEntry.create(
      upstream: 'MiniMax-M3',
      route: AiProviderType.anthropic,
    );
    final minimax =
        AiChannel.create(
              platform: PlatformProfiles.miniMax,
              name: 'mm',
              apiKey: 'k-no-adaptive',
            )
            .copyWith(
              routes: [const AiRoute(protocol: AiProviderType.anthropic)],
            )
            .withModel(m);
    final config = minimax.configFor(m);
    final provider = AiService.providerFor(config);
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: '${config.endpoint}/v1',
        model: 'MiniMax-M3',
        apiKey: 'k-no-adaptive',
      ),
      (b) => b.copyWith(rejectedFields: {'thinking:adaptive'}),
    );
    const written = {'thinking:adaptive'};
    expect(
      provider.learned.rejectedFields,
      written,
      reason: 'the test wrote the route the matrix reads',
    );

    final value = capabilityCell(
      l10n,
      minimax,
      m,
      AiProviderType.anthropic,
      Capability.thinkingOff,
    );
    expect(value.state, CapabilityState.works);
    expect(value.text, l10n.aiCellSwitch('thinking'));
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
    // Sent, but a relay can rewrite `none` to medium: not measured.
    final responses = cell(
      model,
      AiProviderType.openAiResponses,
      Capability.thinkingOff,
    );
    expect(responses.state, CapabilityState.unmeasured);
    expect(responses.text, l10n.aiCellProtocolSwitch('reasoning.effort'));
  });

  test('image input the user has not allowed says so', () {
    expect(
      cell(model, AiProviderType.openAi, Capability.image).text,
      l10n.aiCellNotAllowed,
    );
  });
}
