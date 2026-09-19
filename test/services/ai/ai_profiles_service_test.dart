import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/google_genai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';

/// A flat profile as every build before channels saved it.
Map<String, dynamic> _legacy(
  String id,
  String endpoint, {
  String provider = 'openai',
  String model = 'qwen3.6-27b',
  String key = 'sk-legacy',
}) => {
  'id': id,
  'name': 'Profile $id',
  'provider': provider,
  'endpoint': endpoint,
  'api_key': key,
  'model': model,
  'temperature_override': 0.6,
  'top_k': 20,
  'thinking_enabled': false,
  'context_window': 32768,
  'max_output_tokens': 4096,
  'tool_support': {'for': '$provider|$endpoint|$model', 'supported': true},
};

/// URL, headers and body of the one request [config] sends for a chat turn.
Future<({String url, Map<String, String> headers, String body})> _sent(
  AiConfig config,
) async {
  late http.Request seen;
  final client = MockClient((request) async {
    seen = request;
    if (config.provider == AiProviderType.googleGenAi) {
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': 'ok'},
            'finish_reason': 'stop',
          },
        ],
      }),
      200,
    );
  });
  final provider = config.provider == AiProviderType.googleGenAi
      ? GoogleGenAiProvider(config, client: client)
      : OpenAiProvider(config, client: client);
  await provider.chat(
    messages: const [SystemMessage('s'), UserMessage('u')],
    tools: const [],
  );
  return (url: seen.url.toString(), headers: seen.headers, body: seen.body);
}

void main() {
  group('reading a file from before channels', () {
    // Every shape of endpoint a profile could hold, each on its own host so
    // no learned behaviour carries between cases.
    final shapes = {
      'bare origin': _legacy('a', 'http://bare-origin:1234'),
      'with /v1': _legacy('b', 'http://with-v1:1234/v1'),
      'relay prefix': _legacy('c', 'https://relay-prefix.example/api/openai'),
      'trailing slash': _legacy('d', 'http://trailing-slash:1234/v1/'),
      'cloud platform': _legacy(
        'e',
        'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4.6',
      ),
      'Google root': _legacy(
        'f',
        'https://generativelanguage.googleapis.com',
        provider: 'google',
        model: 'gemini-2.5-flash',
      ),
    };

    for (final MapEntry(key: shape, value: json) in shapes.entries) {
      test('sends byte-identical requests: $shape', () async {
        final service = AiProfilesService()
          ..loadFromMap({
            'ai_services': [json],
            'active_ai_service': json['id'],
          });

        final before = await _sent(AiConfig.fromJson(json));
        final after = await _sent(service.aiConfig);

        expect(after.url, before.url);
        expect(after.headers, before.headers);
        expect(after.body, before.body);
      });
    }

    test('keeps ids, the active profile and tool support', () {
      final service = AiProfilesService()
        ..loadFromMap({
          'ai_services': [
            _legacy('one', 'http://keeps-ids:1234/v1'),
            _legacy('two', 'http://keeps-ids-2:1234/v1'),
          ],
          'active_ai_service': 'two',
        });

      expect(service.channels, hasLength(2));
      expect(service.resolve(AiTask.organize)?.model.id, 'two');
      // Scraping follows organize until it is given a model of its own.
      expect(service.resolve(AiTask.scrapeLearn)?.model.id, 'two');
      expect(service.isAssigned(AiTask.scrapeLearn), isFalse);
      expect(service.aiConfig.supportsTools, isTrue);
      expect(service.aiConfig.contextWindow, 32768);
    });

    test('an unknown active id falls back to the first model', () {
      final service = AiProfilesService()
        ..loadFromMap({
          'ai_services': [_legacy('x', 'http://fallback:1234/v1')],
          'active_ai_service': 'gone',
        });
      expect(service.resolve(AiTask.organize)?.model.id, 'x');
    });
  });

  group('the file it writes', () {
    test('round-trips channels and task assignments', () {
      final channel = AiChannel.create(
        platform: PlatformProfiles.dashScope,
        name: 'Bailian',
        apiKey: 'sk-x',
      );
      final model = AiModelEntry.create(
        upstream: 'qwen-plus',
        route: AiProviderType.openAi,
      );
      final service = AiProfilesService();
      service.loadFromMap({
        'channels': [channel.withModel(model).toJson()],
        'tasks': {'organize': model.id, 'vision': model.id},
      });

      final restored = AiProfilesService()
        ..loadFromMap(jsonDecode(jsonEncode(service.toMap())));

      expect(restored.channels.single.platform.id, 'dashscope');
      expect(restored.resolve(AiTask.vision)?.model.id, model.id);
      expect(
        restored.aiConfig.endpoint,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
    });

    test('an older build is only shown models it can drive', () {
      final chat = AiModelEntry.create(
        upstream: 'qwen-plus',
        route: AiProviderType.openAi,
      );
      final claude = AiModelEntry.create(
        upstream: 'claude',
        route: AiProviderType.anthropic,
      );
      final channel =
          AiChannel.create(
            platform: PlatformProfiles.dashScope,
            name: 'b',
            apiKey: 'k',
          ).copyWith(
            routes: const [
              AiRoute(protocol: AiProviderType.openAi),
              AiRoute(protocol: AiProviderType.anthropic),
            ],
            models: [chat, claude],
          );
      final service = AiProfilesService()
        ..loadFromMap({
          'channels': [channel.toJson()],
          'tasks': {'organize': claude.id},
        });
      final map = service.toMap();
      final flat = map['ai_services'] as List;
      expect(flat.map((p) => (p as Map)['id']), [chat.id]);
      expect(map['active_ai_service'], chat.id);
    });

    test('still carries flat profiles for an older build', () {
      final service = AiProfilesService()
        ..loadFromMap({
          'ai_services': [_legacy('old', 'http://older-build:1234/v1')],
          'active_ai_service': 'old',
        });
      final map = service.toMap();
      final flat = (map['ai_services'] as List).single as Map<String, dynamic>;

      expect(map['v'], AiProfilesService.schemaVersion);
      expect(map['active_ai_service'], 'old');
      expect(flat['id'], 'old');
      expect(flat['endpoint'], 'http://older-build:1234/v1');
      expect(AiConfig.fromJson(flat).model, 'qwen3.6-27b');
    });
  });

  group('tasks', () {
    test(
      'deleting the organize model hands organize to the next one',
      () async {
        final service = AiProfilesService()
          ..loadFromMap({
            'ai_services': [
              _legacy('a', 'http://tasks-a:1/v1'),
              _legacy('b', 'http://tasks-b:1/v1'),
            ],
            'active_ai_service': 'a',
          });
        await service.assign(AiTask.scrapeDirect, 'a');
        await service.deleteChannel('a');

        expect(service.resolve(AiTask.organize)?.model.id, 'b');
        // A task pointed at a model that is gone follows organize again.
        expect(service.isAssigned(AiTask.scrapeDirect), isFalse);
      },
    );

    test('organize cannot be unassigned', () async {
      final service = AiProfilesService()
        ..loadFromMap({
          'ai_services': [_legacy('a', 'http://organize-stays:1/v1')],
        });
      await service.assign(AiTask.organize, null);
      expect(service.resolve(AiTask.organize)?.model.id, 'a');
    });
  });

  test('tool support is recorded on every model with the same route', () {
    final service = AiProfilesService()
      ..loadFromMap({
        'ai_services': [
          _legacy('a', 'http://shared:1/v1', key: 'k1')..remove('tool_support'),
          _legacy('b', 'http://shared:1/v1', key: 'k2')..remove('tool_support'),
        ],
      });
    final tested = service.modelById('a')!;
    final changed = service.recordToolSupport(
      tested.channel.configFor(tested.model),
      false,
    );
    expect(changed, isTrue);
    for (final (:channel, :model) in service.allModels) {
      expect(channel.configFor(model).supportsTools, isFalse);
    }
  });

  group('merging', () {
    test('offers two channels on one host and key, then merges them', () async {
      final service = AiProfilesService()
        ..loadFromMap({
          'ai_services': [
            _legacy('chat', 'https://relay.example.com/v1'),
            _legacy(
              'claude',
              'https://relay.example.com',
              provider: 'google',
              model: 'gemini-2.5-pro',
            ),
          ],
          'active_ai_service': 'claude',
        });

      final groups = service.mergeCandidates;
      expect(groups, hasLength(1));
      final before = {
        for (final (:channel, :model) in service.allModels)
          model.id: channel.configFor(model).endpoint,
      };

      await service.merge([for (final c in groups.single) c.id]);

      final merged = service.channels.single;
      expect(merged.routes.map((r) => r.protocol), [
        AiProviderType.openAi,
        AiProviderType.googleGenAi,
      ]);
      expect(merged.models, hasLength(2));
      // Each model still talks to exactly the URL it did.
      for (final model in merged.models) {
        expect(merged.configFor(model).endpoint, before[model.id]);
      }
      expect(service.resolve(AiTask.organize)?.model.id, 'claude');
    });

    test('different platforms are never offered', () {
      final service = AiProfilesService()
        ..loadFromMap({
          'channels': [
            AiChannel.fromLegacyProfile(
              id: 'a',
              name: 'a',
              config: const AiConfig(
                provider: AiProviderType.openAi,
                endpoint: 'https://relay.example.com/v1',
                apiKey: 'same',
                model: 'm',
              ),
            ).toJson(),
            AiChannel.fromLegacyProfile(
              id: 'b',
              name: 'b',
              config: const AiConfig(
                provider: AiProviderType.openAi,
                endpoint: 'https://relay.example.com/v1',
                apiKey: 'same',
                model: 'n',
              ),
            ).copyWith(platformId: () => 'openrouter').toJson(),
          ],
        });
      expect(service.mergeCandidates, isEmpty);
    });

    test('different keys are never offered', () {
      final service = AiProfilesService()
        ..loadFromMap({
          'ai_services': [
            _legacy('a', 'https://relay.example.com/v1', key: 'one'),
            _legacy('b', 'https://relay.example.com/v1', key: 'two'),
          ],
        });
      expect(service.mergeCandidates, isEmpty);
    });
  });
}
