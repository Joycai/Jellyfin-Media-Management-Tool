import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/model_limits.dart';

void main() {
  test('llama.cpp props report the launch context', () {
    final limits = ModelLimits.fromLlamaCppProps({
      'default_generation_settings': {'n_ctx': 8192},
    });

    expect(limits?.contextWindow, 8192);
    expect(limits?.isModelMaximum, isFalse);
  });

  test('LM Studio: the loaded size wins, the maximum is flagged', () {
    final json = {
      'object': 'list',
      'data': [
        {
          'id': 'qwen/qwen3-8b',
          'state': 'loaded',
          'max_context_length': 40960,
          'loaded_context_length': 4096,
        },
        {
          'id': 'idle-model',
          'state': 'not-loaded',
          'max_context_length': 131072,
        },
      ],
    };

    final loaded = ModelLimits.fromLmStudioModels(json, 'qwen/qwen3-8b')!;
    expect(loaded.contextWindow, 4096);
    expect(loaded.isModelMaximum, isFalse);

    final idle = ModelLimits.fromLmStudioModels(json, 'idle-model')!;
    expect(idle.contextWindow, 131072);
    expect(idle.isModelMaximum, isTrue);
  });

  test('Ollama: ps and num_ctx are real sizes, model_info a maximum', () {
    expect(
      ModelLimits.fromOllamaPs({
        'models': [
          {'name': 'llama3:latest', 'context_length': 4096},
        ],
      }, 'llama3')?.contextWindow,
      4096,
    );

    final configured = ModelLimits.fromOllamaShow({
      'parameters': 'stop "<|eot_id|>"\nnum_ctx                        16384',
      'model_info': {'llama.context_length': 131072},
    })!;
    expect(configured.contextWindow, 16384);
    expect(configured.isModelMaximum, isFalse);

    final trained = ModelLimits.fromOllamaShow({
      'model_info': {
        'general.architecture': 'qwen2',
        'qwen2.context_length': 32768,
      },
    })!;
    expect(trained.contextWindow, 32768);
    expect(trained.isModelMaximum, isTrue);
  });

  test('/v1/models: vLLM max_model_len and OpenRouter limits', () {
    expect(
      ModelLimits.fromOpenAiModels({
        'data': [
          {'id': 'served', 'max_model_len': 32768},
        ],
      }, 'served')?.contextWindow,
      32768,
    );

    final routed = ModelLimits.fromOpenAiModels({
      'data': [
        {
          'id': 'vendor/model',
          'context_length': 200000,
          'top_provider': {'max_completion_tokens': 8192},
        },
      ],
    }, 'vendor/model')!;
    expect(routed.contextWindow, 200000);
    expect(routed.maxOutputTokens, 8192);
  });

  test('Google reports input and output limits', () {
    final limits = ModelLimits.fromGoogleModel({
      'name': 'models/gemini-2.0-flash',
      'inputTokenLimit': 1048576,
      'outputTokenLimit': 8192,
    })!;

    expect(limits.contextWindow, 1048576);
    expect(limits.maxOutputTokens, 8192);
  });

  test('pick prefers any loaded size over an earlier model maximum', () {
    final picked = ModelLimits.pick([
      null,
      const ModelLimits(contextWindow: 131072, isModelMaximum: true),
      ModelLimits.unknown,
      const ModelLimits(contextWindow: 4096),
    ]);

    expect(picked.contextWindow, 4096);
    expect(ModelLimits.pick([null, ModelLimits.unknown]).isEmpty, isTrue);
  });

  test('answers in another dialect are ignored', () {
    expect(
      ModelLimits.fromLlamaCppProps({'error': 'Unexpected endpoint'}),
      isNull,
    );
    expect(
      ModelLimits.fromLmStudioModels({'object': 'list', 'data': []}, 'm'),
      isNull,
    );
    expect(ModelLimits.fromOllamaShow('not a map'), isNull);
    expect(
      ModelLimits.fromOpenAiModels({
        'data': [
          {'id': 'other', 'max_model_len': 4096},
        ],
      }, 'mine'),
      isNull,
    );
  });
}
