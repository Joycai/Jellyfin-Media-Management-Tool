/// The sampling parameters model authors publish for their own models, and
/// how a request resolves them against what the user typed.
///
/// Every row cites its source, and a family with no published recommendation
/// is deliberately absent: an invented preset is worse than the server's
/// default, because it looks authoritative. A new family arrives with the URL
/// its values came from: `SamplingPreset.source` is that record, and the UI
/// links it so a user can check the numbers against the model card itself.
library;

/// How a model family's reasoning can be controlled.
enum ThinkingControl {
  /// The family has no reasoning mode.
  none,

  /// A hybrid model whose chat template takes `enable_thinking`
  /// (Qwen3.5 and later, GLM).
  templateSwitch,

  /// Qwen3's hybrid models: the template switch, plus the `/no_think` soft
  /// switch, which is plain prompt text and so reaches the model through any
  /// server.
  softSwitch,

  /// Reasoning is off unless the system prompt opens with a token (Gemma 4),
  /// so keeping it off needs nothing at all.
  promptToken,

  /// Reasoning cannot be removed, only lowered (gpt-oss).
  effortOnly,

  /// Reasoning is the only mode (DeepSeek-R1, QwQ, the Thinking-2507 models).
  alwaysOn,
}

class SamplingValues {
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? minP;
  final double? presencePenalty;
  final double? repeatPenalty;

  const SamplingValues({
    this.temperature,
    this.topP,
    this.topK,
    this.minP,
    this.presencePenalty,
    this.repeatPenalty,
  });

  static const empty = SamplingValues();
}

class SamplingPreset {
  final String id;

  /// Shown in settings. A product name, so not localised.
  final String label;
  final RegExp match;

  /// Values with reasoning off; null for a family that can only reason.
  final SamplingValues? nonThinking;

  /// Values with reasoning on; null for a family without a reasoning mode, or
  /// whose card gives one set for both.
  final SamplingValues? thinking;
  final ThinkingControl thinkingControl;

  /// The model card or official document the values come from.
  final String source;

  /// The card says the model needs its own system prompt, which this app does
  /// not send.
  final bool needsSystemPrompt;

  SamplingPreset({
    required this.id,
    required this.label,
    required String pattern,
    this.nonThinking,
    this.thinking,
    required this.thinkingControl,
    required this.source,
    this.needsSystemPrompt = false,
  }) : match = RegExp(pattern, caseSensitive: false);

  /// Whether reasoning actually runs, given what the user asked for.
  bool reasons({required bool requested}) => switch (thinkingControl) {
    ThinkingControl.none => false,
    ThinkingControl.alwaysOn || ThinkingControl.effortOnly => true,
    _ => requested,
  };

  /// Whether the user's thinking switch changes anything for this family.
  bool get thinkingIsOptional => switch (thinkingControl) {
    ThinkingControl.templateSwitch ||
    ThinkingControl.softSwitch ||
    ThinkingControl.promptToken => true,
    _ => false,
  };

  SamplingValues valuesFor({required bool thinking}) =>
      (thinking
          ? (this.thinking ?? nonThinking)
          : (nonThinking ?? this.thinking)) ??
      SamplingValues.empty;
}

// Shared value sets. Qwen3.5, 3.6 and 3.8 publish the same non-thinking
// ("instruct") values; their thinking values differ.
const _qwenInstruct = SamplingValues(
  temperature: 0.7,
  topP: 0.8,
  topK: 20,
  minP: 0,
  presencePenalty: 1.5,
  repeatPenalty: 1.0,
);
const _qwen3NonThinking = SamplingValues(
  temperature: 0.7,
  topP: 0.8,
  topK: 20,
  minP: 0,
);
const _qwen3Thinking = SamplingValues(
  temperature: 0.6,
  topP: 0.95,
  topK: 20,
  minP: 0,
);
const _gemma = SamplingValues(temperature: 1.0, topP: 0.95, topK: 64);

abstract final class SamplingPresets {
  /// Ordered: the first match wins, so a more specific family must come
  /// before any family whose pattern also matches it — `qwen3.8` before
  /// `qwen3`, `deepseek-r1-distill-qwen` before every `qwen`.
  static final List<SamplingPreset> all = [
    SamplingPreset(
      id: 'qwen3.8',
      label: 'Qwen3.8',
      pattern: r'qwen3\.8',
      nonThinking: _qwenInstruct,
      thinking: const SamplingValues(
        temperature: 1.0,
        topP: 0.95,
        topK: 20,
        minP: 0,
        presencePenalty: 0,
        repeatPenalty: 1.0,
      ),
      thinkingControl: ThinkingControl.templateSwitch,
      source: 'https://huggingface.co/Qwen/Qwen3.8-27B',
    ),
    SamplingPreset(
      id: 'qwen3.6',
      label: 'Qwen3.6',
      pattern: r'qwen3\.6',
      nonThinking: _qwenInstruct,
      thinking: const SamplingValues(
        temperature: 1.0,
        topP: 0.95,
        topK: 20,
        minP: 0,
        presencePenalty: 0,
        repeatPenalty: 1.0,
      ),
      thinkingControl: ThinkingControl.templateSwitch,
      source: 'https://huggingface.co/Qwen/Qwen3.6-27B',
    ),
    SamplingPreset(
      id: 'qwen3.5',
      label: 'Qwen3.5',
      pattern: r'qwen3\.5',
      nonThinking: _qwenInstruct,
      thinking: const SamplingValues(
        temperature: 1.0,
        topP: 0.95,
        topK: 20,
        minP: 0,
        presencePenalty: 1.5,
        repeatPenalty: 1.0,
      ),
      thinkingControl: ThinkingControl.templateSwitch,
      source: 'https://huggingface.co/Qwen/Qwen3.5-27B',
    ),
    SamplingPreset(
      id: 'qwen3-next-instruct',
      label: 'Qwen3-Next Instruct',
      pattern: r'qwen3-next.*instruct',
      nonThinking: _qwen3NonThinking,
      thinkingControl: ThinkingControl.none,
      source: 'https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct',
    ),
    SamplingPreset(
      id: 'qwen3-thinking-2507',
      label: 'Qwen3 Thinking-2507',
      pattern: r'qwen3-.*thinking-2507',
      thinking: _qwen3Thinking,
      thinkingControl: ThinkingControl.alwaysOn,
      source: 'https://huggingface.co/Qwen/Qwen3-30B-A3B-Thinking-2507',
    ),
    SamplingPreset(
      id: 'qwen3-instruct-2507',
      label: 'Qwen3 Instruct-2507',
      pattern: r'qwen3-.*instruct-2507',
      nonThinking: _qwen3NonThinking,
      thinkingControl: ThinkingControl.none,
      source: 'https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507',
    ),
    SamplingPreset(
      // "can be run in the same manner as Qwen3-8B" (DeepSeek-R1-0528 card).
      id: 'deepseek-r1-0528-qwen3',
      label: 'DeepSeek-R1-0528-Qwen3',
      pattern: r'deepseek-r1-0528-qwen3',
      nonThinking: _qwen3NonThinking,
      thinking: _qwen3Thinking,
      thinkingControl: ThinkingControl.softSwitch,
      source: 'https://huggingface.co/deepseek-ai/DeepSeek-R1-0528',
    ),
    SamplingPreset(
      id: 'deepseek-r1',
      label: 'DeepSeek-R1',
      pattern: r'deepseek-r1',
      thinking: const SamplingValues(temperature: 0.6, topP: 0.95),
      thinkingControl: ThinkingControl.alwaysOn,
      source: 'https://huggingface.co/deepseek-ai/DeepSeek-R1',
    ),
    SamplingPreset(
      id: 'qwq',
      label: 'QwQ',
      pattern: r'qwq',
      thinking: _qwen3Thinking,
      thinkingControl: ThinkingControl.alwaysOn,
      source: 'https://huggingface.co/Qwen/QwQ-32B',
    ),
    SamplingPreset(
      id: 'qwen3',
      label: 'Qwen3',
      pattern: r'qwen3',
      nonThinking: _qwen3NonThinking,
      thinking: _qwen3Thinking,
      thinkingControl: ThinkingControl.softSwitch,
      source: 'https://huggingface.co/Qwen/Qwen3-8B',
    ),
    SamplingPreset(
      id: 'galtransl',
      label: 'Sakura-GalTransl',
      pattern: r'galtransl',
      nonThinking: const SamplingValues(temperature: 0.3, topP: 0.8),
      thinkingControl: ThinkingControl.none,
      source: 'https://huggingface.co/SakuraLLM/Sakura-GalTransl-7B-v3.7',
    ),
    SamplingPreset(
      id: 'sakura',
      label: 'SakuraLLM',
      pattern: r'sakura.*v(0\.9|1\.0)',
      nonThinking: const SamplingValues(
        temperature: 0.1,
        topP: 0.3,
        repeatPenalty: 1.0,
      ),
      thinkingControl: ThinkingControl.none,
      source: 'https://github.com/SakuraLLM/SakuraLLM',
    ),
    SamplingPreset(
      id: 'qwen2.5-coder',
      label: 'Qwen2.5-Coder',
      pattern: r'qwen2\.5-coder',
      nonThinking: const SamplingValues(
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
        repeatPenalty: 1.1,
      ),
      thinkingControl: ThinkingControl.none,
      source:
          'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct/blob/main/generation_config.json',
    ),
    SamplingPreset(
      id: 'qwen2.5',
      label: 'Qwen2.5',
      pattern: r'qwen2\.5',
      nonThinking: const SamplingValues(
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
        repeatPenalty: 1.05,
      ),
      thinkingControl: ThinkingControl.none,
      source:
          'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct/blob/main/generation_config.json',
    ),
    SamplingPreset(
      id: 'gemma4',
      label: 'Gemma 4',
      pattern: r'gemma-?4',
      nonThinking: _gemma,
      thinkingControl: ThinkingControl.promptToken,
      source: 'https://ai.google.dev/gemma/docs/core/model_card_4',
    ),
    SamplingPreset(
      id: 'gemma3',
      label: 'Gemma 3',
      pattern: r'gemma-?3',
      nonThinking: _gemma,
      thinkingControl: ThinkingControl.none,
      source: 'https://huggingface.co/google/gemma-3-12b-it/discussions/25',
    ),
    SamplingPreset(
      id: 'gpt-oss',
      label: 'gpt-oss',
      pattern: r'gpt-oss',
      thinking: const SamplingValues(temperature: 1.0, topP: 1.0),
      thinkingControl: ThinkingControl.effortOnly,
      source: 'https://github.com/openai/gpt-oss/blob/main/README.md',
    ),
    SamplingPreset(
      id: 'phi-4-reasoning',
      label: 'Phi-4-reasoning',
      pattern: r'phi-4.*reasoning',
      thinking: const SamplingValues(temperature: 0.8, topP: 0.95, topK: 50),
      thinkingControl: ThinkingControl.alwaysOn,
      source: 'https://huggingface.co/microsoft/Phi-4-reasoning',
      needsSystemPrompt: true,
    ),
    SamplingPreset(
      id: 'magistral',
      label: 'Magistral',
      pattern: r'magistral',
      thinking: const SamplingValues(temperature: 0.7, topP: 0.95),
      thinkingControl: ThinkingControl.alwaysOn,
      source: 'https://huggingface.co/mistralai/Magistral-Small-2509',
      needsSystemPrompt: true,
    ),
    SamplingPreset(
      id: 'mistral-small',
      label: 'Mistral Small',
      pattern: r'mistral-small-3\.[12]',
      nonThinking: const SamplingValues(temperature: 0.15),
      thinkingControl: ThinkingControl.none,
      source:
          'https://huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506',
    ),
    SamplingPreset(
      id: 'mistral-nemo',
      label: 'Mistral Nemo',
      pattern: r'mistral-nemo',
      nonThinking: const SamplingValues(temperature: 0.3),
      thinkingControl: ThinkingControl.none,
      source: 'https://huggingface.co/mistralai/Mistral-Nemo-Instruct-2407',
    ),
    SamplingPreset(
      id: 'llama3',
      label: 'Llama 3',
      pattern: r'llama-?3\.[123]',
      nonThinking: const SamplingValues(temperature: 0.6, topP: 0.9),
      thinkingControl: ThinkingControl.none,
      source:
          'https://huggingface.co/unsloth/Llama-3.1-8B-Instruct/raw/main/generation_config.json',
    ),
    SamplingPreset(
      id: 'glm-4.7-flash',
      label: 'GLM-4.7-Flash',
      pattern: r'glm-4\.7-flash',
      nonThinking: const SamplingValues(temperature: 1.0, topP: 0.95),
      thinkingControl: ThinkingControl.templateSwitch,
      source: 'https://huggingface.co/zai-org/GLM-4.7-Flash',
    ),
    SamplingPreset(
      id: 'glm-4.6',
      label: 'GLM-4.6',
      pattern: r'glm-4\.6',
      nonThinking: const SamplingValues(temperature: 1.0),
      thinkingControl: ThinkingControl.templateSwitch,
      source: 'https://huggingface.co/zai-org/GLM-4.6',
    ),
  ];

  static SamplingPreset? forModel(String model) {
    final id = model.trim();
    if (id.isEmpty) return null;
    for (final preset in all) {
      if (preset.match.hasMatch(id)) return preset;
    }
    return null;
  }
}

/// What one request should send, after the preset and the user's overrides.
class ResolvedSampling {
  /// The matched family, or null for a model no preset covers.
  final SamplingPreset? preset;

  /// Whether this request expects reasoning to run.
  final bool thinking;
  final SamplingValues values;

  const ResolvedSampling({
    required this.preset,
    required this.thinking,
    required this.values,
  });

  /// The temperature every request carried before presets existed. Still what
  /// a model outside every preset gets, so nothing changes for those.
  static const double legacyTemperature = 0.2;

  /// Each field is the user's override, else the family's value for the mode
  /// reasoning will actually run in, else nothing — the server's default.
  static ResolvedSampling of({
    required String model,
    required bool thinkingRequested,
    required SamplingValues overrides,
  }) {
    final preset = SamplingPresets.forModel(model);
    final thinking =
        preset?.reasons(requested: thinkingRequested) ?? thinkingRequested;
    final base =
        preset?.valuesFor(thinking: thinking) ??
        const SamplingValues(temperature: legacyTemperature);
    return ResolvedSampling(
      preset: preset,
      thinking: thinking,
      values: SamplingValues(
        temperature: overrides.temperature ?? base.temperature,
        topP: overrides.topP ?? base.topP,
        topK: overrides.topK ?? base.topK,
        minP: overrides.minP ?? base.minP,
        presencePenalty: overrides.presencePenalty ?? base.presencePenalty,
        repeatPenalty: overrides.repeatPenalty ?? base.repeatPenalty,
      ),
    );
  }
}
