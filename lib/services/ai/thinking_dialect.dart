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
