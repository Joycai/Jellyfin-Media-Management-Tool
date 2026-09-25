import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/services/ai/thinking_dialect.dart';

AiConfig _at(String endpoint, {String? platform}) => AiConfig(
  provider: AiProviderType.openAi,
  endpoint: endpoint,
  apiKey: 'k',
  model: 'm',
  platform: platform,
);

void main() {
  test('platforms are recognised by host, subdomains included', () {
    expect(
      PlatformProfiles.forHost('https://open.bigmodel.cn/api/paas/v4')?.id,
      'zhipu',
    );
    expect(
      PlatformProfiles.forHost('https://api.deepseek.com')?.id,
      'deepseek',
    );
    for (final host in ['dashscope', 'dashscope-intl', 'dashscope-us']) {
      expect(
        PlatformProfiles.forHost(
          'https://$host.aliyuncs.com/compatible-mode',
        )?.id,
        'dashscope',
      );
    }
  });

  test('a look-alike host is no platform', () {
    expect(PlatformProfiles.forHost('https://notbigmodel.cn'), isNull);
    expect(PlatformProfiles.forHost('https://oss.aliyuncs.com'), isNull);
    expect(PlatformProfiles.forHost('http://localhost:1234'), isNull);
    expect(PlatformProfiles.forHost(''), isNull);
  });

  test('the reasoning switch comes from the platform, not the model name', () {
    expect(
      PlatformProfiles.dialectFor(_at('https://open.bigmodel.cn/api/paas/v4')),
      ThinkingDialect.thinkingType,
    );
    expect(
      PlatformProfiles.dialectFor(
        _at('https://dashscope.aliyuncs.com/compatible-mode/v1'),
      ),
      ThinkingDialect.enableThinking,
    );
    // A relay on its own host gets OpenRouter's switch only when the channel
    // says it is OpenRouter.
    expect(
      PlatformProfiles.dialectFor(
        _at('https://my-router.example/api/v1', platform: 'openrouter'),
      ),
      ThinkingDialect.reasoningObject,
    );
    expect(PlatformProfiles.dialectFor(_at('http://localhost:1234')), isNull);
  });

  test('every profile is well formed', () {
    final ids = <String>{};
    for (final profile in PlatformProfiles.all) {
      expect(ids.add(profile.id), isTrue, reason: 'duplicate ${profile.id}');
      expect(profile.routes, isNotEmpty, reason: profile.id);
      for (final spec in profile.routes.values) {
        expect(spec.source, isNotEmpty, reason: profile.id);
        expect(
          spec.defaultPath.isEmpty || spec.defaultPath.startsWith('/'),
          isTrue,
          reason: '${profile.id} ${spec.defaultPath}',
        );
      }
      if (profile.kind == PlatformKind.vendor) {
        expect(profile.hosts, isNotEmpty, reason: profile.id);
        expect(profile.needsKey, isTrue, reason: profile.id);
      }
    }
    expect(PlatformProfiles.byId('nope'), PlatformProfiles.custom);
  });

  test('only MiniMax declares a Messages thinking switch', () {
    // MiniMax-M3's /anthropic takes `adaptive | disabled` only (KB 03 §3).
    for (final profile in PlatformProfiles.all) {
      final spec = profile.routes[AiProviderType.anthropic];
      if (spec == null) continue;
      expect(
        spec.messagesThinkingSwitch,
        profile.id == 'minimax',
        reason: profile.id,
      );
    }
    AiConfig messages(String endpoint) => AiConfig(
      provider: AiProviderType.anthropic,
      endpoint: endpoint,
      apiKey: 'k',
      model: 'm',
    );
    expect(
      PlatformProfiles.messagesSwitchFor(
        messages('https://api.minimaxi.com/anthropic'),
      ),
      isTrue,
    );
    // The same host on Chat Completions has no such switch.
    expect(
      PlatformProfiles.messagesSwitchFor(_at('https://api.minimaxi.com/v1')),
      isFalse,
    );
    expect(
      PlatformProfiles.messagesSwitchFor(
        messages('https://open.bigmodel.cn/api/anthropic'),
      ),
      isFalse,
    );
  });

  test('reasoning is switchable where the route or its protocol can send '
      'both', () {
    AiConfig on(AiProviderType provider, String endpoint) => AiConfig(
      provider: provider,
      endpoint: endpoint,
      apiKey: 'k',
      model: 'm',
    );
    const custom = 'https://relay.example.com';
    // The protocol carries the switch, and names it.
    expect(
      PlatformProfiles.protocolSwitchFieldFor(
        on(AiProviderType.anthropic, custom),
      ),
      'thinking',
    );
    expect(
      PlatformProfiles.protocolSwitchFieldFor(
        on(AiProviderType.openAiResponses, custom),
      ),
      'reasoning.effort',
    );
    expect(
      PlatformProfiles.thinkingSwitchable(on(AiProviderType.anthropic, custom)),
      isTrue,
    );
    expect(
      PlatformProfiles.thinkingSwitchable(
        on(AiProviderType.openAiResponses, custom),
      ),
      isTrue,
    );
    // Only a documented field does.
    expect(
      PlatformProfiles.thinkingSwitchable(on(AiProviderType.openAi, custom)),
      isFalse,
    );
    expect(
      PlatformProfiles.thinkingSwitchable(
        on(
          AiProviderType.openAi,
          'https://dashscope.aliyuncs.com/compatible-mode/v1',
        ),
      ),
      isTrue,
    );
    expect(
      PlatformProfiles.thinkingSwitchable(
        on(AiProviderType.googleGenAi, custom),
      ),
      isFalse,
    );
  });

  test('a refused protocol field is no switch', () {
    AiConfig on(AiProviderType provider, String model) => AiConfig(
      provider: provider,
      endpoint: 'https://relay.example.com',
      apiKey: 'k',
      model: model,
    );
    final responses = on(AiProviderType.openAiResponses, 'gpt-4.1');
    expect(
      PlatformProfiles.thinkingSwitchable(responses, refused: {'reasoning'}),
      isFalse,
    );
    // Off refused alone: `effort: none` is left out, `medium` still sent.
    expect(
      PlatformProfiles.thinkingSwitchable(responses, refused: {'include'}),
      isTrue,
    );
    final claude = on(AiProviderType.anthropic, 'claude-sonnet-4-5');
    // One form refused: the other is still asked.
    expect(
      PlatformProfiles.protocolSwitchFieldFor(
        claude,
        refused: {'thinking:enabled'},
      ),
      'thinking',
    );
    expect(
      PlatformProfiles.protocolSwitchFieldFor(
        claude,
        refused: {'thinking:adaptive', 'thinking:enabled'},
      ),
      isNull,
    );
    // A bare legacy record where `enabled` is the model's first form.
    expect(
      PlatformProfiles.thinkingSwitchable(claude, refused: {'thinking'}),
      isFalse,
    );
  });
}
