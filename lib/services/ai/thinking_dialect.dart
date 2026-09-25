/// How a cloud platform's OpenAI-compatible API switches reasoning on and off.
///
/// The field is the platform's, not the model's. Guessing it from the model
/// name — as the local-server ladder in `OpenAiProvider` does — fails silently
/// in the cloud: Zhipu lets `chat_template_kwargs` through unread and drops
/// `reasoning_effort: "none"` on GLM-4.x, so every request goes on reasoning
/// and is billed for it, and DashScope's commercial Qwen models never reason
/// unless `enable_thinking: true` is sent. Each ladder step there is also a
/// paid request. A platform with a documented switch therefore gets that
/// switch and no ladder.
library;

enum ThinkingDialect {
  /// `thinking: {"type": "enabled" | "disabled"}` — Zhipu BigModel, DeepSeek,
  /// Volcengine Ark.
  thinkingType,

  /// `enable_thinking: true | false` — Alibaba DashScope (Bailian).
  enableThinking,

  /// `reasoning: {"enabled": true | false}` — OpenRouter's unified switch,
  /// which it translates for whichever upstream serves the model.
  reasoningObject;

  /// The request field that asks for reasoning, or for none.
  MapEntry<String, Object> field({required bool thinking}) => switch (this) {
    thinkingType => MapEntry('thinking', {
      'type': thinking ? 'enabled' : 'disabled',
    }),
    enableThinking => MapEntry('enable_thinking', thinking),
    reasoningObject => MapEntry('reasoning', {'enabled': thinking}),
  };
}

/// The form a Messages (Anthropic) request asks for thinking in (KB 03 §3).
enum MessagesThinking {
  /// `{type: "adaptive"}` — Claude 4.6 and later, where the model sizes its
  /// own reasoning.
  adaptive,

  /// `{type: "enabled", budget_tokens: N}` — earlier Claude, and every
  /// non-Claude model a mirror serves, unless the mirror's route is declared
  /// a switch (`RouteSpec.messagesThinkingSwitch`), which takes adaptive.
  extended;

  /// The form [model] is asked in first.
  ///
  /// Claude from 4.6 on (`claude-opus-4-6…`, `claude-sonnet-5…`) takes
  /// adaptive. Everything else keeps extended, which is what every route
  /// sent before: whether a mirror's own models take adaptive has no
  /// evidence either way, and its bytes do not change. The id says only
  /// which generation a Claude model is — the same kind of fact as a
  /// sampling preset's family, not a vendor branch.
  static MessagesThinking forModel(String model) {
    final match = RegExp(
      r'claude-(?:[a-z]+-)?(\d+)(?:[-.](\d{1,2})(?!\d))?',
    ).firstMatch(model.toLowerCase());
    if (match == null) return extended;
    final major = int.parse(match.group(1)!);
    final minor = int.tryParse(match.group(2) ?? '') ?? 0;
    return major > 4 || (major == 4 && minor >= 6) ? adaptive : extended;
  }

  /// The other form, tried when a route refuses this one.
  MessagesThinking get other => this == adaptive ? extended : adaptive;

  /// The `thinking.type` this form sends.
  String get type => switch (this) {
    adaptive => 'adaptive',
    extended => 'enabled',
  };

  /// What `LearnedBehaviour.rejectedFields` records when a route refuses
  /// this form: the field and the type it was refused with.
  String get refusedName => 'thinking:$type';
}
