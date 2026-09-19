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
  /// `thinking: {"type": "enabled" | "disabled"}` — Zhipu BigModel, DeepSeek.
  thinkingType,

  /// `enable_thinking: true | false` — Alibaba DashScope (Bailian).
  enableThinking;

  /// The platform behind [endpoint], or null for any other server — which
  /// keeps the ladder.
  static ThinkingDialect? forEndpoint(String endpoint) {
    final host = Uri.tryParse(endpoint.trim())?.host.toLowerCase() ?? '';
    bool under(String domain) => host == domain || host.endsWith('.$domain');
    if (under('bigmodel.cn') || under('api.z.ai')) return thinkingType;
    if (under('api.deepseek.com')) return thinkingType;
    // One host per region: dashscope, dashscope-intl, dashscope-us, …
    final labels = host.split('.');
    if (under('aliyuncs.com') &&
        labels.length >= 3 &&
        labels[labels.length - 3].startsWith('dashscope')) {
      return enableThinking;
    }
    return null;
  }

  /// The request field that asks for reasoning, or for none.
  MapEntry<String, Object> field({required bool thinking}) => switch (this) {
    thinkingType => MapEntry('thinking', {
      'type': thinking ? 'enabled' : 'disabled',
    }),
    enableThinking => MapEntry('enable_thinking', thinking),
  };
}
