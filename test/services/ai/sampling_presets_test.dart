import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';

String? _family(String model) => SamplingPresets.forModel(model)?.id;

ResolvedSampling _resolve(
  String model, {
  bool thinking = false,
  SamplingValues overrides = SamplingValues.empty,
}) => ResolvedSampling.of(
  model: model,
  thinkingRequested: thinking,
  overrides: overrides,
);

List<num?> _values(SamplingValues v) => [
  v.temperature,
  v.topP,
  v.topK,
  v.minP,
  v.presencePenalty,
  v.repeatPenalty,
];

void main() {
  group('family matching', () {
    test('a more specific family wins over one that also matches', () {
      expect(_family('qwen3.8-27b-uncensored'), 'qwen3.8');
      expect(_family('qwen/qwen3.6-27b'), 'qwen3.6');
      expect(_family('Qwen3.5-9B-GGUF'), 'qwen3.5');
      expect(_family('qwen3-next-80b-a3b-instruct'), 'qwen3-next-instruct');
      expect(_family('qwen3-30b-a3b-thinking-2507'), 'qwen3-thinking-2507');
      expect(_family('qwen3-30b-a3b-instruct-2507'), 'qwen3-instruct-2507');
      expect(_family('deepseek-r1-0528-qwen3-8b'), 'deepseek-r1-0528-qwen3');
      expect(_family('deepseek-r1-distill-qwen-14b'), 'deepseek-r1');
      expect(_family('qwq-32b'), 'qwq');
      expect(_family('qwen3-8b'), 'qwen3');
      expect(_family('sakura-galtransl-7b-v3.7'), 'galtransl');
      expect(_family('sakura-14b-qwen2.5-v1.0'), 'sakura');
      expect(_family('qwen2.5-coder-7b-instruct'), 'qwen2.5-coder');
      expect(_family('qwen2.5-7b-instruct'), 'qwen2.5');
      expect(_family('gemma4-26b-a4b-uncensored'), 'gemma4');
      expect(_family('gemma-3-12b-it'), 'gemma3');
      expect(_family('openai/gpt-oss-20b'), 'gpt-oss');
      expect(_family('phi-4-reasoning-plus'), 'phi-4-reasoning');
      expect(_family('magistral-small-2509'), 'magistral');
      expect(_family('mistral-small-3.2-24b-instruct-2506'), 'mistral-small');
      expect(_family('mistral-nemo-instruct-2407'), 'mistral-nemo');
      expect(_family('Meta-Llama-3.1-8B-Instruct'), 'llama3');
      expect(_family('glm-4.7-flash'), 'glm-4.7-flash');
      expect(_family('glm-4.6'), 'glm-4.6');
    });

    test('a family with no published values gets no preset', () {
      expect(_family('spark-x2.5-4b'), isNull);
      expect(_family('gpt-4o-mini'), isNull);
      expect(_family('phi-4'), isNull);
      expect(_family('gemini-2.0-flash'), isNull);
      expect(_family(''), isNull);
    });
  });

  group('resolution', () {
    test('thinking off takes the family\'s non-thinking values', () {
      final s = _resolve('qwen3.8-27b-uncensored');

      expect(s.thinking, isFalse);
      expect(_values(s.values), [0.7, 0.8, 20, 0, 1.5, 1.0]);
    });

    test('thinking on switches to the thinking values', () {
      final s = _resolve('qwen3.8-27b-uncensored', thinking: true);

      expect(s.thinking, isTrue);
      expect(_values(s.values), [1.0, 0.95, 20, 0, 0, 1.0]);
    });

    test('an override beats the preset, field by field', () {
      final s = _resolve(
        'qwen3.8-27b-uncensored',
        overrides: const SamplingValues(temperature: 0.5, topK: 40),
      );

      expect(_values(s.values), [0.5, 0.8, 40, 0, 1.5, 1.0]);
    });

    test('a reasoning-only family reasons whatever was asked', () {
      final s = _resolve('deepseek-r1-distill-qwen-14b');

      expect(s.thinking, isTrue);
      expect(s.values.temperature, 0.6);
      expect(s.values.topP, 0.95);
    });

    test('a family with one value set uses it in both modes', () {
      expect(
        _values(_resolve('gemma4-26b', thinking: true).values),
        _values(_resolve('gemma4-26b').values),
      );
    });

    test(
      'an unknown model keeps the old fixed temperature and nothing else',
      () {
        final s = _resolve('spark-x2.5-4b');

        expect(s.preset, isNull);
        expect(_values(s.values), [0.2, null, null, null, null, null]);
      },
    );
  });

  group('stored settings', () {
    test('the old fixed temperature reads as unset (D1)', () {
      expect(AiConfig.fromJson({'temperature': 0.2}).temperature, isNull);
      expect(AiConfig.fromJson({'temperature': 0.9}).temperature, 0.9);
    });

    test('a temperature saved by this version survives, even 0.2', () {
      const config = AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'http://localhost:1234/v1',
        apiKey: '',
        model: 'qwen3-8b',
        temperature: 0.2,
        topK: 20,
        minP: 0,
        thinkingEnabled: true,
      );

      final restored = AiConfig.fromJson(config.toJson());

      expect(restored.temperature, 0.2);
      expect(restored.topK, 20);
      expect(restored.minP, 0);
      expect(restored.thinkingEnabled, isTrue);
    });

    test('thinking is off unless it was saved on (D2)', () {
      expect(AiConfig.fromJson(const {}).thinkingEnabled, isFalse);
    });
  });
}
