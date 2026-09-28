/// What a Messages (Anthropic) 400 teaches a route, read in one place.
///
/// `AnthropicProvider.chat` sends a request, and when the server refuses it
/// asks [MessagesRefusal.read] what to remember — a sampling field to drop,
/// a form of thinking to give up, a way of saying off refused — records
/// that and sends again, or throws when nothing was learned. Every reading
/// of the error text lives here, and the learned state is written by one
/// method, [RefusalLesson.apply].
library;

import 'ai_provider.dart';
import 'learned_behaviour.dart';
import 'platform_profiles.dart';
import 'thinking_dialect.dart';

/// What a sentence of a 400 says about a request for thinking, read the
/// same way whether on or off was asked ([MessagesRefusal.readThinkingRefusal]).
enum ThinkingRefusal {
  /// The model cannot stop reasoning ("该模型始终思考，不支持关闭思考"). Read
  /// only when off was asked: it answers that question alone.
  cannotStop,

  /// The server does not know the `thinking` field.
  fieldUnknown,

  /// The server knows the field — the value sent or a sub-field is named
  /// — and refuses in so many words ("unsupported value 'adaptive'",
  /// "thinking.budget_tokens: Extra inputs are not permitted").
  valueRefused,

  /// The value sent, or a sub-field, is named without thinking being
  /// refused ("Input tag 'adaptive' … does not match … 'enabled'").
  valueNamed,

  /// Thinking itself refused, in words that name no field or value ("this
  /// model does not support thinking").
  featureRefused,

  /// Not about the request for thinking: the history, the budget, or
  /// something else.
  unrelated,
}

/// What a 400 taught the route: the one thing recorded before the request
/// is sent again. [MessagesRefusal.read] returns null when nothing was, and
/// the error is thrown as it is.
sealed class RefusalLesson {
  const RefusalLesson();

  /// [learned] with this lesson added.
  LearnedBehaviour apply(LearnedBehaviour learned);
}

/// A sampling field this route refuses by name — `top_k` on a mirror,
/// `temperature` beside `top_p` — dropped and remembered.
final class OptionalRefused extends RefusalLesson {
  final String field;

  const OptionalRefused(this.field);

  @override
  LearnedBehaviour apply(LearnedBehaviour learned) =>
      learned.copyWith(rejectedFields: {...learned.rejectedFields, field});

  @override
  bool operator ==(Object other) =>
      other is OptionalRefused && other.field == field;

  @override
  int get hashCode => Object.hash(OptionalRefused, field);

  @override
  String toString() => 'OptionalRefused($field)';
}

/// Thinking refused in one form (`thinking:adaptive`), or in every form
/// and the field by name.
final class ThinkingFormsRefused extends RefusalLesson {
  final Set<String> forms;

  const ThinkingFormsRefused(this.forms);

  @override
  LearnedBehaviour apply(LearnedBehaviour learned) =>
      learned.copyWith(rejectedFields: {...learned.rejectedFields, ...forms});

  @override
  bool operator ==(Object other) =>
      other is ThinkingFormsRefused &&
      other.forms.length == forms.length &&
      other.forms.containsAll(forms);

  @override
  int get hashCode => Object.hash(ThinkingFormsRefused, forms.length);

  @override
  String toString() => 'ThinkingFormsRefused(${forms.toList()..sort()})';
}

/// A rung of off refused ([MessagesOff]): `disabled`, because the model
/// cannot stop or the server knows the field and not that value —
/// remembered as on Chat Completions — or then the least reasoning. The
/// rung is left off later requests and the next one tried. Always the rung
/// the request carried, so its marker was not yet recorded and the lesson
/// changes what the route knows: the resend is never the same request.
final class OffRefused extends RefusalLesson {
  final MessagesOff rung;

  const OffRefused(this.rung);

  @override
  LearnedBehaviour apply(LearnedBehaviour learned) => learned.copyWith(
    thinkingOffTried: {...learned.thinkingOffTried, rung.triedMarker},
  );

  @override
  bool operator ==(Object other) => other is OffRefused && other.rung == rung;

  @override
  int get hashCode => Object.hash(OffRefused, rung);

  @override
  String toString() => 'OffRefused(${rung.name})';
}

/// The readings of a Messages 400, and the one arbitration between them.
abstract final class MessagesRefusal {
  /// Sampling fields the adapter may leave out when a route refuses them;
  /// `thinking` has its own rules.
  static const optionalFields = ['temperature', 'top_p', 'top_k'];

  /// What the 400 [error] teaches, or null when nothing. Pure: the text,
  /// what the request [payload] carried, what the route already [learned],
  /// and the route's shape from [config].
  ///
  /// The text is read once — lower case, the model id taken out, Pydantic's
  /// echoed input cut, split into sentences — and sentence by sentence. A
  /// sentence is about the field it names first: `thinking`, another
  /// protocol's name for it, or a sampling value this request sent. About
  /// a sampling value, it is that value's refusal, whatever else it
  /// mentions ("'top_p' is not supported with reasoning models",
  /// "`temperature` may only be set to 1 when thinking is enabled"). About
  /// thinking, it is read for what it says of the form asked
  /// (the reading [readThinkingRefusal] holds) and mapped by the direction
  /// asked; where that records nothing, a sampling value named in it still
  /// is. Off said as the least reasoning (`output_config.effort`, the
  /// second rung of [MessagesOff]) is read against the one thing that
  /// request said of reasoning: a sentence that names the least's field
  /// first — or another protocol's name for thinking, or the words of a
  /// model that cannot stop — is that rung refused, as a sampling value
  /// named first is that value ([_effort]); one about `thinking` is read as
  /// for off, and whatever it refuses ("thinking cannot be disabled for
  /// this model") is that rung too; where it refuses nothing, what else it
  /// names still counts. The first sentence with a lesson decides. So
  /// "reasoning_effort is not supported; use temperature instead" gives
  /// thinking up and keeps `temperature`, while "temperature is not
  /// supported with thinking" drops `temperature` and keeps asking. The rule
  /// is the order of the names and nothing finer: "thinking mode does not
  /// support top_p" is about thinking, and gives it up (or, asked off as the
  /// least, gives the least up) — the price of one rule that reads
  /// `thinking`, a translated name and a value alike.
  static RefusalLesson? read(
    String error, {
    required Map<String, Object?> payload,
    required LearnedBehaviour learned,
    required AiConfig config,
  }) {
    final rejected = learned.rejectedFields;
    // The model id is not the message: a relay's `…-thinking` model named
    // in an unrelated error must not read as a refusal.
    final about = error.toLowerCase().replaceAll(
      config.model.toLowerCase(),
      '',
    );
    final sentType = switch (payload['thinking']) {
      {'type': final String type} => type,
      _ => null,
    };
    // Off said as the least reasoning ([_effort]).
    final least = MessagesOff.sentIn(payload) == MessagesOff.leastEffort;
    final sentOptional = optionalFields
        .where((f) => payload.containsKey(f) && !rejected.contains(f))
        .toList();
    // An error about the thinking blocks in the history says nothing about
    // the request for thinking, whichever sentence says it.
    final history = _aboutHistory(about);
    // A field the request sent, named: the least's (never over the
    // history), or a sampling value's.
    RefusalLesson? namedLesson(String? subject) => switch (subject) {
      null => null,
      _effort => history ? null : const OffRefused(MessagesOff.leastEffort),
      _ => OptionalRefused(subject),
    };
    for (final sentence in _sentences(about)) {
      final subject = _subjectOf(sentence, sentOptional, least: least);
      if (subject != _thinking) {
        final lesson = namedLesson(subject);
        if (lesson != null) return lesson;
        continue;
      }
      if (!history) {
        final lesson = least
            // The least is the one thing this request said of reasoning:
            // whatever the sentence says of thinking, read as for off, is
            // said of it.
            ? _readSentence(sentence, sentType: 'disabled') ==
                      ThinkingRefusal.unrelated
                  ? null
                  : const OffRefused(MessagesOff.leastEffort)
            : sentType == null
            ? null
            : _lessonFor(
                _readSentence(sentence, sentType: sentType),
                sentType: sentType,
                sent: sentForm(payload),
                refused: MessagesThinking.refusedIn(
                  rejected,
                  first: PlatformProfiles.messagesFirstFormFor(config),
                ),
                swap: !PlatformProfiles.messagesSwitchFor(config),
              );
        if (lesson != null) return lesson;
      }
      // Thinking recorded nothing: a field the request sent, named in the
      // sentence, still is — the first named, as above.
      final lesson = namedLesson(
        least
            ? _subjectOf(sentence, sentOptional, least: true, thinking: false)
            : _first(sentence, sentOptional),
      );
      if (lesson != null) return lesson;
    }
    return null;
  }

  /// The marker [_subjectOf] returns for a sentence about thinking, under
  /// its own name or another protocol's.
  static const _thinking = 'thinking';

  /// The marker [_subjectOf] returns, where the request said off as the
  /// least reasoning (`output_config: {effort: "low"}`, no `thinking`), for
  /// a sentence that names what was sent: `output_config` or its `effort`
  /// written as a field ([_effortField]), another protocol's name for
  /// thinking (the least is all that could have been translated — Zhipu's
  /// "reasoning_effort 参数值非法"), or the words of a model that cannot stop
  /// (Zhipu's 5.3 answers `medium`, `minimal` and `none` with its
  /// "始终思考"). Like a sampling value named first, it is that rung refused
  /// whatever the words: `low` is all that was sent. `thinking` itself is a
  /// word of prose too ("thinking mode", a docs link), and stays [_thinking]:
  /// [read] takes it for the least by what the sentence says of it.
  static const _effort = 'output_config';

  /// The field [sentence] names first — [_thinking], under its own name
  /// (unless not [thinking]), another protocol's, or the words of a model
  /// that cannot stop, where they stand (all but `thinking` itself are
  /// [_effort] where the request said off as the least reasoning, [least],
  /// and so is the least's own field); or one of [sentOptional] — or null
  /// when it names none.
  static String? _subjectOf(
    String sentence,
    List<String> sentOptional, {
    bool least = false,
    bool thinking = true,
  }) {
    int? at(String name) {
      final index = sentence.indexOf(name);
      return index < 0 ? null : index;
    }

    String? subject;
    var first = sentence.length;
    void consider(String field, int? index) {
      if (index != null && index < first) {
        first = index;
        subject = field;
      }
    }

    final translated = least ? _effort : _thinking;
    // "The model cannot stop" names no field: the words stand for it.
    consider(translated, thinkingOffWords.firstMatch(sentence)?.start);
    if (thinking) consider(_thinking, at('thinking'));
    for (final name in reasoningFieldNames) {
      if (name != 'thinking' && namesField(sentence, name)) {
        // Where the name stands as itself: `reasoning` is not the
        // `reasoning` in an earlier `reasoning_content`.
        consider(
          translated,
          RegExp(
            '${RegExp.escape(name)}(?![a-z_])',
          ).firstMatch(sentence)?.start,
        );
      }
    }
    if (least) consider(_effort, _effortField.firstMatch(sentence)?.start);
    for (final field in sentOptional) {
      consider(field, at(field));
    }
    return subject;
  }

  /// The least's field as a field is written: `output_config`, a dotted
  /// `.effort`, a quoted one, one given a value (`effort=low`, "effort
  /// 'low'", "effort: 'low'"), or `effort:` opening a line — not the word
  /// in prose ("despite our best effort"), and not the end of
  /// `reasoning_effort`, which is another protocol's name for thinking and
  /// counts as that.
  static final _effortField = RegExp(
    r'''output_config|\.effort\b|["'`]effort["'`]|(?<![a-z_-])effort(=|\s*:?\s*["'`])|^\s*effort\s*:''',
    multiLine: true,
  );

  /// The one of [fields] that [sentence] names first, or null.
  static String? _first(String sentence, List<String> fields) {
    String? first;
    var at = sentence.length;
    for (final field in fields) {
      final index = sentence.indexOf(field);
      if (index >= 0 && index < at) {
        at = index;
        first = field;
      }
    }
    return first;
  }

  /// What [reading], of a sentence about thinking, records for the
  /// direction asked — the one table both directions share.
  ///
  /// Asked off (`disabled`): the model cannot stop, or the server knows the
  /// field and not `disabled`, is off refused; the field unknown, or the
  /// feature, is every form. Asked on: a field the server does not know,
  /// or thinking itself refused, gives thinking up, every form at once. A
  /// refusal that names the form ("thinking.type: Input tag 'adaptive' …
  /// does not match … 'disabled', 'enabled'", an older Claude; "…enabled is
  /// not supported", a newer one) swaps it for the other: dropping thinking
  /// over it would switch reasoning off for a month without a word. With no
  /// other form left to swap to, only a refusal of the feature may switch
  /// reasoning off: one that refuses the form in so many words gives up
  /// every form on a route that swaps, and just that form on a route
  /// declared as a switch ([swap] false — its one form, and off still says
  /// `disabled`, since the server knows the field); one that merely names
  /// it is thrown as it is.
  static RefusalLesson? _lessonFor(
    ThinkingRefusal reading, {
    required String sentType,
    required MessagesThinking? sent,
    required Set<MessagesThinking> refused,
    required bool swap,
  }) {
    if (sentType == 'disabled') {
      return switch (reading) {
        ThinkingRefusal.cannotStop ||
        ThinkingRefusal.valueRefused ||
        ThinkingRefusal.valueNamed => const OffRefused(MessagesOff.disabled),
        ThinkingRefusal.fieldUnknown || ThinkingRefusal.featureRefused =>
          ThinkingFormsRefused(everyThinkingForm),
        ThinkingRefusal.unrelated => null,
      };
    }
    if (sent == null) return null;
    return switch (reading) {
      ThinkingRefusal.fieldUnknown ||
      ThinkingRefusal.featureRefused => ThinkingFormsRefused(everyThinkingForm),
      ThinkingRefusal.valueRefused || ThinkingRefusal.valueNamed
          when swap && !refused.contains(sent.other) =>
        ThinkingFormsRefused({sent.refusedName}),
      ThinkingRefusal.valueRefused => ThinkingFormsRefused(
        swap ? everyThinkingForm : {sent.refusedName},
      ),
      ThinkingRefusal.valueNamed ||
      ThinkingRefusal.cannotStop ||
      ThinkingRefusal.unrelated => null,
    };
  }

  /// Whether a rejection refuses extended thinking itself — "does not
  /// support thinking", "thinking: Extra inputs are not permitted" — rather
  /// than only mentioning it. The budget error ("max_tokens must be greater
  /// than thinking.budget_tokens") is about the numbers, not the feature,
  /// and dropping thinking over it would switch reasoning off unasked.
  static bool refusesThinking(String detail) {
    if (!detail.contains('thinking')) return false;
    if (detail.contains('budget_tokens') && detail.contains('max_tokens')) {
      return false;
    }
    return RegExp('$_refusalWords|["\'`]thinking["\'`]').hasMatch(detail);
  }

  /// OpenAI's "Unrecognized request argument supplied: thinking" — and not
  /// "unrecognized model: …-thinking", which is about the model.
  static const _unrecognizedField =
      'unrecognized (request )?(argument|field|parameter|key)';

  /// The words of a field the server does not know: Pydantic's
  /// (`extra_forbidden`), OpenAI's, Google's ("Unknown name") and a plain
  /// "unknown field".
  static const _unknownFieldWords =
      'extra inputs|extra_forbidden|unknown (field|parameter|name)|'
      '$_unrecognizedField';

  /// The words of a refusal — of a value or a feature, and those of a
  /// field unknown, which are a kind of refusal.
  static const _refusalWords =
      'not support|unsupported|not permitted|not allowed|$_unknownFieldWords';

  /// Whether [detail] refuses `thinking` in the words of a field the server
  /// does not know — Pydantic's "Extra inputs are not permitted"
  /// (`extra_forbidden`), "unknown field" — as against a value it will not
  /// take. A sub-field named (`thinking.type`, `thinking.budget_tokens`)
  /// says the server knows the field, whatever the words: it is the value.
  static bool refusesThinkingField(String detail) =>
      detail.contains('thinking') &&
      !_subField.hasMatch(detail) &&
      RegExp(_unknownFieldWords).hasMatch(detail);

  /// Whether [sentence], one that does not say `thinking`, refuses the
  /// field under the name a relay's translation layer gave it — its upstream's
  /// `reasoning_effort`, `chat_template_kwargs`, `thinkingConfig`, a quoted
  /// `reasoning` — in the words of a refusal or of an unknown field, or
  /// with the name quoted (an "Invalid value for 'reasoning_effort'" is
  /// the relay's value, not ours). What the relay sends instead is not
  /// this adapter's to know or change, so the one thing to learn is that
  /// the route cannot carry a request for thinking: the field unknown,
  /// every form given up. A name merely mentioned, with nothing refused, is
  /// about something else — as is one named in another sentence than the
  /// refusal ("unsupported parameter: top_k. Supported parameters:
  /// reasoning_effort, …"), or inside the input Pydantic echoes (the
  /// relay's whole translated body, when the error is about something
  /// else in it), which [_sentences] keeps out.
  static bool refusesThinkingTranslated(String sentence) =>
      translatedFieldNamed(sentence, own: 'thinking') != null &&
      (RegExp(_refusalWords).hasMatch(sentence) ||
          _quotedTranslated.hasMatch(sentence));

  /// Pydantic's echo of the refused input, `input_value=…, input_type=…`.
  /// It ends at `input_type`, or at a `]` that ends the line — not at one
  /// inside the echoed body, which has lists in it (`'messages': [{…}]`).
  static final _echoedInput = RegExp(
    r'input_value=.*?(?=, input_type=|\]\s*(\n|$)|$)',
    dotAll: true,
  );

  /// [text] as the sentences read one by one: the echoed input cut out,
  /// then split at each sentence end.
  static Iterable<String> _sentences(String text) =>
      text.replaceAll(_echoedInput, '').split(_sentenceEnd);

  /// Another protocol's name for the field, quoted or dotted
  /// (`'reasoning_effort'`, `'reasoning.effort'`).
  static final _quotedTranslated = () {
    final names = reasoningFieldNames
        .where((name) => name != 'thinking')
        .map(RegExp.escape)
        .join('|');
    return RegExp('["\'`]($names)["\'`.]');
  }();

  /// A sentence end: a full stop or semicolon followed by space. Not a
  /// newline — Pydantic puts the field on its own line above the words.
  static final _sentenceEnd = RegExp(r'[.;]\s+');

  /// Whether [detail], answering a request to turn thinking off, says the
  /// model's reasoning is mandatory in another protocol's name for the
  /// field — the model cannot stop, as [refusesThinkingOff] reads the words
  /// that name no field. The words count only beside a name: on their own
  /// they turn up in unrelated errors ("messages is mandatory", any
  /// parameter "restricted to" a value).
  static bool _cannotStopTranslated(String detail) =>
      _cannotStopWords.hasMatch(detail) &&
      translatedFieldNamed(detail, own: 'thinking') != null;

  /// "reasoning is mandatory for this model"; DashScope's Messages face
  /// told off for a model that only thinks, in its own name for the field
  /// (【实测 2026-09-28】MiniMax-M2.5 and glm-5.3 there: "The value of the
  /// enable_thinking parameter is restricted to True.").
  static final _cannotStopWords = RegExp('mandatory|restricted to true');

  /// A sub-field of `thinking` named — the ones a request carries, so that
  /// "thinking.Please", a docs URL ending in `thinking.html` or a relay's
  /// `…-thinking.v2` alias do not read as one.
  static final _subField = RegExp(r'thinking\.(type|budget_tokens|display)\b');

  /// What a 400 [detail] says about the request for thinking that sent
  /// [sentType] (`adaptive`, `enabled` or `disabled`), the one reading of
  /// the words for both directions — [read] applies it to each sentence
  /// about thinking and maps it by the direction; this whole-message form
  /// is what the vocabulary tests hold. Words for a field the server
  /// does not know are read before the value is looked for, since Pydantic
  /// echoes the refused input (`input_value={'type': 'disabled'}`) beside
  /// them. One that does not say `thinking` at all can still refuse it
  /// under another protocol's name for the field, a relay's translation
  /// ([refusesThinkingTranslated]): the field unknown, nothing finer —
  /// except "mandatory" or "restricted to true" beside such a name in
  /// answer to off, which is the model that cannot stop
  /// ([_cannotStopTranslated]). A budget error is about the numbers, never the
  /// form, and an error about the thinking blocks in the conversation
  /// ("`thinking` or `redacted_thinking` blocks … cannot be modified",
  /// "messages.3.content.0: Invalid `signature` in `thinking` block") says
  /// the history is wrong, whichever form was asked for: both are
  /// unrelated. A whole message is read with the history ruled out, then
  /// sentence by sentence with the echoed input cut, the first sentence
  /// that says something deciding.
  static ThinkingRefusal readThinkingRefusal(
    String detail, {
    required String sentType,
  }) {
    if (_aboutHistory(detail)) return ThinkingRefusal.unrelated;
    return _sentences(detail)
        .map((sentence) => _readSentence(sentence, sentType: sentType))
        .firstWhere(
          (reading) => reading != ThinkingRefusal.unrelated,
          orElse: () => ThinkingRefusal.unrelated,
        );
  }

  /// [readThinkingRefusal] of one sentence, the history already ruled out.
  static ThinkingRefusal _readSentence(
    String detail, {
    required String sentType,
  }) {
    // Said without naming the field ("始终思考"): read before the field is
    // looked for. It answers off alone: asked on, the same words beside a
    // form or the field are read as those.
    if (sentType == 'disabled' &&
        (refusesThinkingOff(detail) || _cannotStopTranslated(detail))) {
      return ThinkingRefusal.cannotStop;
    }
    // Said of another protocol's field: a relay translated `thinking` and
    // was refused under that name. Only the field can be read from it.
    if (!detail.contains('thinking')) {
      return refusesThinkingTranslated(detail)
          ? ThinkingRefusal.fieldUnknown
          : ThinkingRefusal.unrelated;
    }
    if (detail.contains('budget_tokens') && detail.contains('max_tokens')) {
      return ThinkingRefusal.unrelated;
    }
    if (refusesThinkingField(detail)) return ThinkingRefusal.fieldUnknown;
    // The value sent, or a sub-field, named: the server knows the field.
    // A sub-field other than the type named on its own, with no refusal
    // beside it — a budget out of range — is about the numbers.
    final namesValue =
        detail.contains(sentType) || detail.contains('thinking.type');
    if (namesValue || _subField.hasMatch(detail)) {
      if (refusesThinking(detail)) return ThinkingRefusal.valueRefused;
      return namesValue
          ? ThinkingRefusal.valueNamed
          : ThinkingRefusal.unrelated;
    }
    if (refusesThinking(detail)) return ThinkingRefusal.featureRefused;
    return ThinkingRefusal.unrelated;
  }

  /// What a refusal of the `thinking` field itself records: every form, and
  /// the field by name.
  static final everyThinkingForm = Set<String>.unmodifiable({
    for (final form in MessagesThinking.values) form.refusedName,
    'thinking',
  });

  /// Whether [detail] is about the thinking blocks already in the
  /// conversation rather than about the request for thinking.
  static bool _aboutHistory(String detail) =>
      RegExp(r'redacted_thinking|signature|messages\.\d').hasMatch(detail);

  /// The form [payload] asked for thinking in, if it did.
  static MessagesThinking? sentForm(Map<String, Object?> payload) =>
      switch (payload['thinking']) {
        {'type': final String type} =>
          MessagesThinking.values
              .where((form) => form.type == type)
              .firstOrNull,
        _ => null,
      };
}
