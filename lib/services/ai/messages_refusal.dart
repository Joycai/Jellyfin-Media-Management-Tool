/// What a Messages (Anthropic) 400 teaches a route, read in one place.
///
/// `AnthropicProvider.chat` sends a request, and when the server refuses it
/// asks [MessagesRefusal.read] what to remember — a sampling field to drop,
/// a form of thinking to give up, the switch set to off refused — records
/// that and sends again, or throws when nothing was learned. Every reading
/// of the error text lives here, and the learned state is written by one
/// method, [RefusalLesson.apply].
library;

import 'ai_provider.dart';
import 'learned_behaviour.dart';
import 'platform_profiles.dart';
import 'thinking_dialect.dart';

/// What a 400 says about a request for thinking, read the same way whether
/// on or off was asked ([MessagesRefusal.readThinkingRefusal]).
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

/// The switch set to off refused — the model cannot stop, or the server
/// knows the field and not `disabled`: remembered as on Chat Completions,
/// and `disabled` left off later requests.
final class OffRefused extends RefusalLesson {
  const OffRefused();

  @override
  LearnedBehaviour apply(LearnedBehaviour learned) => learned.copyWith(
    thinkingOffTried: {
      ...learned.thinkingOffTried,
      LearnedBehaviour.dialectOff,
    },
  );

  @override
  bool operator ==(Object other) => other is OffRefused;

  @override
  int get hashCode => (OffRefused).hashCode;

  @override
  String toString() => 'OffRefused()';
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
  /// A sampling field this request sent, refused in words that only mention
  /// reasoning in passing ("'top_p' is not supported with reasoning
  /// models"), is that field's refusal: the request is read for thinking
  /// then only where the words say `thinking`. (A request that asks for
  /// thinking sends no sampling values, so this is a switch route told off,
  /// with its values beside it.) Otherwise a switch route told off is read
  /// first, then the form asked for, then a sampling field.
  static RefusalLesson? read(
    String error, {
    required Map<String, Object?> payload,
    required LearnedBehaviour learned,
    required AiConfig config,
  }) {
    final rejected = learned.rejectedFields;
    final detail = error.toLowerCase();
    // The model id is not the message: a relay's `…-thinking` model named
    // in an unrelated error must not read as a refusal.
    final about = detail.replaceAll(config.model.toLowerCase(), '');
    final refusedOptional = optionalFields
        .where(
          (f) =>
              payload.containsKey(f) &&
              !rejected.contains(f) &&
              detail.contains(f),
        )
        .firstOrNull;
    final readForThinking =
        refusedOptional == null || about.contains('thinking');
    if (readForThinking) {
      // A switch route told off: what the refusal says decides what is
      // remembered, in the one reading both directions share.
      if (payload['thinking'] case {'type': 'disabled'}) {
        switch (readThinkingRefusal(about, sentType: 'disabled')) {
          // The model cannot stop, or the server knows the field and not
          // `disabled`.
          case ThinkingRefusal.cannotStop:
          case ThinkingRefusal.valueRefused:
          case ThinkingRefusal.valueNamed:
            return const OffRefused();
          // The server does not know the field, or refuses thinking
          // itself: refused by name, every form with it, so neither way
          // sends it and nothing fails over it — which says nothing about
          // whether the model reasons.
          case ThinkingRefusal.fieldUnknown:
          case ThinkingRefusal.featureRefused:
            return ThinkingFormsRefused(everyThinkingForm);
          case ThinkingRefusal.unrelated:
            break;
        }
      }
      final forms = thinkingForms(
        about,
        sent: sentForm(payload),
        refused: MessagesThinking.refusedIn(
          rejected,
          first: PlatformProfiles.messagesFirstFormFor(config),
        ),
        swap: !PlatformProfiles.messagesSwitchFor(config),
      );
      if (forms != null) return ThinkingFormsRefused(forms);
    }
    if (refusedOptional != null) return OptionalRefused(refusedOptional);
    return null;
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

  /// Whether [detail], which does not say `thinking`, refuses the field
  /// under the name a relay's translation layer gave it — its upstream's
  /// `reasoning_effort`, `chat_template_kwargs`, `thinkingConfig`, a quoted
  /// `reasoning` — in the words of a refusal or of an unknown field, or
  /// with the name quoted (an "Invalid value for 'reasoning_effort'" is
  /// the relay's value, not ours). What the relay sends instead is not
  /// this adapter's to know or change, so the one thing to learn is that
  /// the route cannot carry a request for thinking: the field unknown,
  /// every form given up. A name merely mentioned, with nothing refused, is
  /// about something else, and so is one named in another sentence than
  /// the refusal ("unsupported parameter: top_k. Supported parameters:
  /// reasoning_effort, …") or inside the input Pydantic echoes — the
  /// relay's whole translated body, when the error is about something
  /// else in it.
  static bool refusesThinkingTranslated(String detail) {
    final text = detail.replaceAll(_echoedInput, '');
    return text
        .split(_sentenceEnd)
        .any(
          (sentence) =>
              translatedFieldNamed(sentence, own: 'thinking') != null &&
              (RegExp(_refusalWords).hasMatch(sentence) ||
                  _quotedTranslated.hasMatch(sentence)),
        );
  }

  /// Pydantic's echo of the refused input, `input_value=…, input_type=…`.
  /// It ends at `input_type`, never at a `]` — the echoed body has lists
  /// in it (`'messages': [{…}]`).
  static final _echoedInput = RegExp(
    r'input_value=.*?(?=, input_type=|$)',
    dotAll: true,
  );

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
  /// that name no field. `mandatory` counts only beside a name: on its own
  /// it turns up in unrelated errors ("messages is mandatory").
  static bool _mandatoryTranslated(String detail) =>
      detail.contains('mandatory') &&
      translatedFieldNamed(detail, own: 'thinking') != null;

  /// A sub-field of `thinking` named — the ones a request carries, so that
  /// "thinking.Please", a docs URL ending in `thinking.html` or a relay's
  /// `…-thinking.v2` alias do not read as one.
  static final _subField = RegExp(r'thinking\.(type|budget_tokens|display)\b');

  /// What a 400 [detail] says about the request for thinking that sent
  /// [sentType] (`adaptive`, `enabled` or `disabled`): the one reading both
  /// directions map to what they remember. Words for a field the server
  /// does not know are read before the value is looked for, since Pydantic
  /// echoes the refused input (`input_value={'type': 'disabled'}`) beside
  /// them. One that does not say `thinking` at all can still refuse it
  /// under another protocol's name for the field, a relay's translation
  /// ([refusesThinkingTranslated]): the field unknown, nothing finer —
  /// except "mandatory" beside such a name in answer to off, which is the
  /// model that cannot stop. A budget error is about the numbers, never the
  /// form, and an error about the thinking blocks in the conversation
  /// ("`thinking` or `redacted_thinking` blocks … cannot be modified",
  /// "messages.3.content.0: Invalid `signature` in `thinking` block") says
  /// the history is wrong, whichever form was asked for: both are
  /// unrelated.
  static ThinkingRefusal readThinkingRefusal(
    String detail, {
    required String sentType,
  }) {
    if (_aboutHistory(detail)) return ThinkingRefusal.unrelated;
    // Said without naming the field ("始终思考"): read before the field is
    // looked for. It answers off alone: asked on, the same words beside a
    // form or the field are read as those.
    if (sentType == 'disabled' &&
        (refusesThinkingOff(detail) || _mandatoryTranslated(detail))) {
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

  /// What to remember when a request that asked for thinking in [sent] is
  /// refused with [detail], or null when nothing is: the on direction's
  /// mapping of [readThinkingRefusal].
  ///
  /// A field the server does not know, or thinking itself refused, gives
  /// thinking up, every form at once. A refusal that names the form
  /// ("thinking.type: Input tag 'adaptive' … does not match … 'disabled',
  /// 'enabled'", an older Claude; "…enabled is not supported", a newer one)
  /// swaps it for the other: dropping thinking over it would switch
  /// reasoning off for a month without a word. With no other form left to
  /// swap to, only a refusal of the feature may switch reasoning off: one
  /// that refuses the form in so many words gives up every form on a route
  /// that swaps, and just that form on a route declared as a switch
  /// ([swap] false — its one form, and off still says `disabled`, since the
  /// server knows the field); one that merely names it is thrown as it is.
  static Set<String>? thinkingForms(
    String detail, {
    required MessagesThinking? sent,
    required Set<MessagesThinking> refused,
    required bool swap,
  }) {
    if (sent == null) return null;
    return switch (readThinkingRefusal(detail, sentType: sent.type)) {
      ThinkingRefusal.fieldUnknown ||
      ThinkingRefusal.featureRefused => everyThinkingForm,
      ThinkingRefusal.valueRefused || ThinkingRefusal.valueNamed
          when swap && !refused.contains(sent.other) =>
        {sent.refusedName},
      ThinkingRefusal.valueRefused =>
        swap ? everyThinkingForm : {sent.refusedName},
      ThinkingRefusal.valueNamed ||
      ThinkingRefusal.cannotStop ||
      ThinkingRefusal.unrelated => null,
    };
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
