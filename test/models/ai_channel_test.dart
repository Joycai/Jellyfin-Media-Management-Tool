import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';

void main() {
  test('a route with no endpoint is the host plus the platform path', () {
    final channel =
        AiChannel.create(
          platform: PlatformProfiles.dashScope,
          name: 'b',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.openAi),
            AiRoute(protocol: AiProviderType.anthropic),
          ],
        );
    expect(
      channel.endpointFor(AiProviderType.openAi),
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    );
    expect(
      channel.endpointFor(AiProviderType.anthropic),
      'https://dashscope.aliyuncs.com/apps/anthropic',
    );
  });

  test('the host is joined as typed, never normalised', () {
    final channel = AiChannel.create(
      platform: PlatformProfiles.custom,
      name: 'c',
      baseUrl: 'HTTP://MixedCase.example:8080/prefix/',
    );
    expect(
      channel.endpointFor(AiProviderType.openAi),
      'HTTP://MixedCase.example:8080/prefix',
    );
  });

  test('a relative path follows the host when it changes', () {
    var channel =
        AiChannel.create(
          platform: PlatformProfiles.relay,
          name: 'r',
          baseUrl: 'https://relay.example.com',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.openAi, endpoint: '/api/openai'),
          ],
        );
    expect(
      channel.endpointFor(AiProviderType.openAi),
      'https://relay.example.com/api/openai',
    );
    expect(channel.hasOwnHost(AiProviderType.openAi), isFalse);
    channel = channel.copyWith(baseUrl: 'https://moved.example.com/');
    expect(
      channel.endpointFor(AiProviderType.openAi),
      'https://moved.example.com/api/openai',
    );
  });

  test('a migrated route moves with its host', () {
    final channel = AiChannel.fromLegacyProfile(
      id: 'p',
      name: 'n',
      config: const AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'http://old-box:1234/v1',
        apiKey: '',
        model: 'm',
      ),
    ).withBaseUrl('http://new-box:1234');
    expect(
      channel.endpointFor(AiProviderType.openAi),
      'http://new-box:1234/v1',
    );
  });

  test('an endpoint of its own wins and may be another host', () {
    final channel =
        AiChannel.create(
          platform: PlatformProfiles.relay,
          name: 'r',
          baseUrl: 'https://relay.example.com',
        ).copyWith(
          routes: const [
            AiRoute(
              protocol: AiProviderType.openAi,
              endpoint: 'https://other.example.com/v1',
            ),
          ],
        );
    expect(
      channel.endpointFor(AiProviderType.openAi),
      'https://other.example.com/v1',
    );
    expect(channel.hasOwnHost(AiProviderType.openAi), isTrue);
  });

  test('switching route parks parameters and never copies them', () {
    final model =
        AiModelEntry.create(
          upstream: 'qwen-plus',
          route: AiProviderType.openAi,
        ).withCurrentParams(
          const RouteParams(temperature: 0.7, maxOutputTokens: 8192),
        );

    final moved = model.switchedTo(AiProviderType.anthropic);
    expect(moved.current.temperature, isNull);
    expect(moved.current.maxOutputTokens, isNull);
    expect(moved.hasParamsFor(AiProviderType.anthropic), isFalse);

    final back = moved.switchedTo(AiProviderType.openAi);
    expect(back.current.temperature, 0.7);
    expect(back.current.maxOutputTokens, 8192);
  });

  test('the flat view carries the model onto its route', () {
    final model = AiModelEntry.create(
      upstream: 'glm-4.6',
      route: AiProviderType.openAi,
    ).copyWith(contextWindow: () => 131072, imageInput: true);
    final channel = AiChannel.create(
      platform: PlatformProfiles.zhipu,
      name: 'z',
      apiKey: 'k',
    ).withModel(model);

    final config = channel.configFor(model);
    expect(config.provider, AiProviderType.openAi);
    expect(config.endpoint, 'https://open.bigmodel.cn/api/paas/v4');
    expect(config.model, 'glm-4.6');
    expect(config.platform, 'zhipu');
    expect(config.contextWindow, 131072);
    expect(config.imageInput, isTrue);
  });

  test('a model whose route is gone falls back to the primary route', () {
    final model = AiModelEntry.create(
      upstream: 'm',
      route: AiProviderType.anthropic,
    );
    final channel = AiChannel.create(
      platform: PlatformProfiles.dashScope,
      name: 'b',
    ).withModel(model);
    expect(channel.configFor(model).provider, AiProviderType.openAi);
  });

  test('channels round-trip through JSON', () {
    final model = AiModelEntry.create(
      upstream: 'm',
      route: AiProviderType.openAi,
    ).withCurrentParams(const RouteParams(topK: 20, thinkingEnabled: true));
    final channel = AiChannel.create(
      platform: PlatformProfiles.openRouter,
      name: 'OR',
      apiKey: 'sk',
    ).withModel(model);

    final restored = AiChannel.fromJson(channel.toJson())!;
    expect(restored.platformId, 'openrouter');
    expect(restored.models.single.current.topK, 20);
    expect(restored.models.single.current.thinkingEnabled, isTrue);
    expect(restored.routes.single.protocol, AiProviderType.openAi);
  });
}
