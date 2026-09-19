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
}
