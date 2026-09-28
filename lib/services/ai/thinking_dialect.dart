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

/// Whether [detail], an error message in lower case, refuses to stop
/// reasoning without naming the field. Zhipu's 5.3 generation answers every
/// thinking parameter it will not take with "该模型始终思考，不支持关闭思考"
/// (KB 03 §3.1). No `mandatory` here: without the field named beside it,
/// that word also turns up in unrelated errors ("messages is mandatory").
bool refusesThinkingOff(String detail) => thinkingOffWords.hasMatch(detail);

/// The words [refusesThinkingOff] reads, for a reader that needs to know
/// where in a sentence they stand.
final RegExp thinkingOffWords = RegExp(
  '始终思考|不支持关闭|无法关闭|不能关闭|'
  'cannot be (disabled|turned off)|always (thinks|reasons)',
);

/// Whether [detail], an error message in lower case, names [field] as one
/// of the request's. A plain substring for the sampling fields, whose
/// names do not occur in prose; `thinking` does ("… in thinking mode", a
/// docs link to `thinking_mode`), and so does `reasoning` (a prefix of
/// `reasoning_content`), and reading such an error as a refusal would drop
/// a platform's reasoning switch for a month — silently back to paid
/// reasoning. So those two count only when quoted or addressed as a
/// parameter.
///
/// A model whose reasoning cannot be switched off answers the platform's
/// switch with "reasoning is mandatory / cannot be disabled"; that too
/// names the field, or every request to it would fail — the whole word,
/// though: `reasoning_content` refused in the history is not the field.
bool namesField(String detail, String field) =>
    field == 'thinking' || field == 'reasoning'
    ? RegExp(
            '["\'`]$field["\'`.]|$field\\.(type|enabled)|'
            '$field (field|parameter)',
          ).hasMatch(detail) ||
          (RegExp('(?<![a-z_])$field(?![a-z_])').hasMatch(detail) &&
              RegExp(
                'mandatory|cannot be (disabled|turned off)|'
                'not supported|unsupported',
              ).hasMatch(detail))
    : detail.contains(field);

/// The request fields that ask for reasoning on the protocols this app
/// speaks, in lower case as a server spells them back: every platform
/// dialect's, the local-server ladder's two, Responses' `reasoning` (the
/// OpenRouter dialect's name), xAI's `reasoningEffort` and Gemini's
/// `thinkingConfig` with its sub-fields. A relay's translation layer may turn one protocol's field
/// into any of them before its upstream refuses it under that name, so an
/// adapter reads a refusal that names none of its own against this set
/// ([translatedFieldNamed]). Data: a name is added here and nowhere else.
final Set<String> reasoningFieldNames = {
  for (final dialect in ThinkingDialect.values)
    dialect.field(thinking: true).key,
  'reasoning_effort',
  'reasoningeffort',
  'chat_template_kwargs',
  'thinkingconfig',
  'thinking_config',
  'thinking_budget',
  'thinking_level',
  'includethoughts',
  'include_thoughts',
};

/// The name in [reasoningFieldNames] other than [own], the protocol's own
/// field, that [detail] names ([namesField]) — or null when it names none.
String? translatedFieldNamed(String detail, {required String own}) =>
    reasoningFieldNames
        .where((name) => name != own && namesField(detail, name))
        .firstOrNull;

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

  /// The forms a route refused, where [first] is the form it is asked in
  /// first. A bare `thinking` with neither form beside it was written before
  /// the forms were told apart, when `enabled` was the only one sent and
  /// only a refusal of thinking itself was recorded. Where `enabled` is also
  /// the first form, that is what a refusal of thinking records now: every
  /// form. Where adaptive comes first (Claude 4.6 and later, a switch
  /// route), adaptive was never asked, and the record is no verdict on it.
  static Set<MessagesThinking> refusedIn(
    Set<String> rejected, {
    required MessagesThinking first,
  }) {
    final forms = {
      for (final form in values)
        if (rejected.contains(form.refusedName)) form,
    };
    if (forms.isEmpty && rejected.contains('thinking')) {
      return first == adaptive ? {extended} : values.toSet();
    }
    return forms;
  }
}
