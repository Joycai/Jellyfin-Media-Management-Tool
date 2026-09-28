import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/messages_refusal.dart';

/// What [MessagesRefusal.read] makes of [message] for a request that asked
/// for thinking as [sent] (`adaptive`, `enabled`, `disabled`, or null for
/// none) and carried the sampling fields [optional], on a route that already
/// refused [rejected] — a relay, or MiniMax's `/anthropic` when [switchRoute].
RefusalLesson? read(
  String message, {
  String? sent,
  List<String> optional = const [],
  Set<String> rejected = const {},
  bool switchRoute = false,
  String model = 'claude-opus-4-6',
}) => MessagesRefusal.read(
  message,
  payload: {
    'model': model,
    if (sent != null) 'thinking': {'type': sent},
    for (final field in optional) field: 1,
  },
  learned: LearnedBehaviour(rejectedFields: rejected),
  config: AiConfig(
    provider: AiProviderType.anthropic,
    endpoint: switchRoute
        ? 'https://api.minimaxi.com/anthropic'
        : 'https://relay.example',
    apiKey: 'k',
    model: model,
  ),
);

final every = ThinkingFormsRefused(MessagesRefusal.everyThinkingForm);
const adaptive = ThinkingFormsRefused({'thinking:adaptive'});
const enabled = ThinkingFormsRefused({'thinking:enabled'});
const off = OffRefused();

void main() {
  test('a lesson is what it records', () {
    final learned = LearnedBehaviour(rejectedFields: {'top_k'});
    expect(const OptionalRefused('top_p').apply(learned).rejectedFields, {
      'top_k',
      'top_p',
    });
    expect(every.apply(learned).rejectedFields, {
      'top_k',
      'thinking',
      'thinking:adaptive',
      'thinking:enabled',
    });
    expect(off.apply(learned).thinkingOffTried, {LearnedBehaviour.dialectOff});
    expect(off.apply(learned).rejectedFields, {'top_k'});
    // Value equality, for the tables below.
    expect(const OptionalRefused('top_p'), const OptionalRefused('top_p'));
    expect(
      const OptionalRefused('top_p'),
      isNot(const OptionalRefused('top_k')),
    );
    expect(
      const ThinkingFormsRefused({'a', 'b'}),
      const ThinkingFormsRefused({'b', 'a'}),
    );
    expect(off, const OffRefused());
  });

  group('asked on, on a route that swaps forms', () {
    test('the field unknown or the feature refused gives up every form', () {
      for (final message in [
        'thinking: Extra inputs are not permitted',
        'Unrecognized request argument supplied: thinking',
        'this model does not support thinking',
        'Unrecognized request argument supplied: reasoning_effort',
        "Unsupported parameter: 'reasoning_effort' is not supported with "
            'this model.',
      ]) {
        expect(read(message, sent: 'adaptive'), every, reason: message);
        expect(read(message, sent: 'enabled'), every, reason: message);
      }
    });

    test('the form refused or named is swapped, then given up', () {
      const refusedForm = "thinking.type: unsupported value 'adaptive'";
      const namedForm =
          "thinking.type: Input tag 'adaptive' found using 'type' does not "
          "match any of the expected tags: 'disabled', 'enabled'";
      expect(read(refusedForm, sent: 'adaptive'), adaptive);
      expect(read(namedForm, sent: 'adaptive'), adaptive);
      // The other form already refused: refused in so many words gives
      // every form up; merely named teaches nothing.
      expect(
        read(refusedForm, sent: 'adaptive', rejected: {'thinking:enabled'}),
        every,
      );
      expect(
        read(namedForm, sent: 'adaptive', rejected: {'thinking:enabled'}),
        isNull,
      );
      expect(
        read("thinking.type: unsupported value 'enabled'", sent: 'enabled'),
        enabled,
      );
    });

    test('nothing is learned from what is not a refusal', () {
      for (final message in [
        'max_tokens must be greater than thinking.budget_tokens',
        'messages.3.content.0: Invalid `signature` in `thinking` block',
        'this model always thinks',
        'the model was reasoning about the request and found it invalid',
        'reasoning_effort was set to medium; the upstream timed out',
        'reasoning is mandatory for this model',
        'model claude-opus-4-6 is not supported',
      ]) {
        expect(read(message, sent: 'adaptive'), isNull, reason: message);
      }
    });
  });

  group('asked off, on a switch route', () {
    test(
      'the model that cannot stop, or the value refused, is off refused',
      () {
        for (final message in [
          '该模型始终思考，不支持关闭思考',
          'this model always thinks',
          "thinking.type: unsupported value 'disabled'",
          'thinking is disabled for this account',
          'reasoning is mandatory for this model',
        ]) {
          expect(
            read(message, sent: 'disabled', switchRoute: true),
            off,
            reason: message,
          );
        }
      },
    );

    test('the field unknown gives up every form', () {
      for (final message in [
        'thinking: Extra inputs are not permitted',
        'Unrecognized request argument supplied: reasoning_effort',
        'this model does not support thinking',
      ]) {
        expect(
          read(message, sent: 'disabled', switchRoute: true),
          every,
          reason: message,
        );
      }
    });

    test('a switch route refused a form keeps that form only', () {
      // Its one form: no other to swap to, and off still says `disabled`.
      const refusedForm = "thinking.type: unsupported value 'adaptive'";
      const namedForm =
          "thinking.type: Input tag 'adaptive' found using 'type' does not "
          "match any of the expected tags: 'disabled', 'enabled'";
      expect(read(refusedForm, sent: 'adaptive', switchRoute: true), adaptive);
      expect(
        read(
          refusedForm,
          sent: 'adaptive',
          switchRoute: true,
          rejected: {'thinking:enabled'},
        ),
        adaptive,
      );
      // Merely named: nothing to swap to, so nothing is learned.
      expect(read(namedForm, sent: 'adaptive', switchRoute: true), isNull);
    });

    test('every form recorded is a copy no one can change', () {
      expect(
        () => MessagesRefusal.everyThinkingForm.add('x'),
        throwsUnsupportedError,
      );
    });
  });

  group('a sampling field', () {
    test('refused by name is dropped, whether or not thinking was asked', () {
      expect(
        read('top_k: Extra inputs are not permitted', optional: ['top_k']),
        const OptionalRefused('top_k'),
      );
      expect(
        read(
          'top_k: Extra inputs are not permitted',
          sent: 'disabled',
          optional: ['temperature', 'top_p', 'top_k'],
          switchRoute: true,
        ),
        const OptionalRefused('top_k'),
      );
      // Not sent, or already refused: not this request's.
      expect(read('top_k: Extra inputs are not permitted'), isNull);
      expect(
        read(
          'top_k: Extra inputs are not permitted',
          optional: ['top_k'],
          rejected: {'top_k'},
        ),
        isNull,
      );
    });

    test("Anthropic's own temperature rule is the value, not thinking", () {
      expect(
        read(
          '`temperature` may only be set to 1 when thinking is enabled',
          sent: 'disabled',
          optional: ['temperature'],
          switchRoute: true,
        ),
        const OptionalRefused('temperature'),
      );
    });

    test('named beside a word of reasoning is the value', () {
      for (final message in [
        "'top_p' is not supported with reasoning models.",
        'top_k is not supported when reasoning is enabled',
        'temperature is not supported when reasoning_effort is set',
      ]) {
        final lesson = read(
          message,
          sent: 'disabled',
          optional: ['temperature', 'top_p', 'top_k'],
          switchRoute: true,
        );
        expect(lesson, isA<OptionalRefused>(), reason: message);
        expect(message, contains((lesson! as OptionalRefused).field));
      }
    });

    test('a translated name refused when no thinking was sent is nothing', () {
      expect(
        read(
          'Unrecognized request argument supplied: reasoning_effort',
          optional: ['temperature'],
        ),
        isNull,
      );
    });
  });

  group('a sentence is about the field it names first (#119 known issues '
      '2 and 3)', () {
    const optional = ['temperature', 'top_p', 'top_k'];

    test('thinking named first keeps a value named in passing', () {
      expect(
        read(
          'reasoning_effort is not supported; use temperature instead',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        every,
      );
      expect(
        read(
          'reasoning is mandatory for this model; temperature is ignored',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        off,
      );
      expect(
        read(
          'Unsupported parameter: reasoning_effort. Supported parameters: '
          'temperature, top_p, top_k, max_tokens',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        every,
      );
      // The model that cannot stop, said in words that name no field, is
      // about thinking whatever the sentence names after.
      expect(
        read(
          '该模型始终思考，不支持关闭思考；temperature 无效',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        off,
      );
    });

    test('a value named first is the value, beside the word thinking', () {
      for (final (message, field) in [
        ('temperature is not supported with thinking', 'temperature'),
        ('top_p is not supported in thinking mode', 'top_p'),
        ('`top_k` cannot be used with thinking enabled', 'top_k'),
        // The words of a model that cannot stop count where they stand.
        ('temperature is required and cannot be disabled', 'temperature'),
      ]) {
        expect(
          read(
            message,
            sent: 'disabled',
            optional: optional,
            switchRoute: true,
          ),
          OptionalRefused(field),
          reason: message,
        );
      }
    });

    test('thinking named first is about thinking, whatever follows', () {
      // The order of the names and nothing finer: what the sentence goes
      // on to refuse is not read. A known limit, the same for `thinking`
      // and a translated name.
      for (final message in [
        'thinking mode does not support top_p',
        'in thinking mode, top_p is not supported',
        'thinking is not supported with temperature',
        'reasoning_effort is not supported with temperature',
        'thinking is not supported. top_p: Extra inputs are not permitted',
      ]) {
        expect(
          read(
            message,
            sent: 'disabled',
            optional: optional,
            switchRoute: true,
          ),
          every,
          reason: message,
        );
      }
    });

    test('an error about the history rules every sentence out', () {
      expect(
        read(
          'messages.1.content.0: thinking blocks cannot be modified. '
          'thinking: Extra inputs are not permitted',
          sent: 'adaptive',
        ),
        isNull,
      );
    });

    test('the first sentence with a lesson decides', () {
      expect(
        read(
          'top_k: Extra inputs are not permitted. thinking: Extra inputs are '
          'not permitted',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        const OptionalRefused('top_k'),
      );
      expect(
        read(
          'Invalid request. thinking: Extra inputs are not permitted',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        every,
      );
    });

    test('a value named where thinking says nothing is still the value', () {
      // Asked on, thinking named but neither refused nor the form named:
      // the old fallback, kept — and the value named first, not the first
      // in the adapter's list.
      expect(
        read(
          'with thinking on, top_k must be unset',
          sent: 'adaptive',
          optional: ['top_k'],
        ),
        const OptionalRefused('top_k'),
      );
      expect(
        read(
          'with thinking on, top_k and temperature must be unset',
          sent: 'adaptive',
          optional: ['temperature', 'top_k'],
        ),
        const OptionalRefused('top_k'),
      );
      // A translated name stands where it is itself: the `reasoning` of
      // an earlier `reasoning_content` is not it.
      expect(
        read(
          "reasoning_content: top_k is not supported alongside 'reasoning.effort'",
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        const OptionalRefused('top_k'),
      );
      // A semicolon ends a sentence: the refusal in the next one is not
      // thinking's.
      expect(
        read('thinking is enabled; top_k unsupported', sent: 'adaptive'),
        isNull,
      );
    });

    test('the echoed input is cut before a sentence is read', () {
      expect(
        read(
          "Value error, 'auto' tool choice is not supported [type=value_error, "
          "input_value={'messages': [{'role': 'user'}], 'reasoning_effort': "
          "'high', 'temperature': 0.7}, input_type=dict]",
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        isNull,
      );
      // An echo with no `input_type` after it ends at the line's end, so
      // the next field's line is still read — the budget refused as an
      // extra input, which gives every form up once the other is refused.
      expect(
        read(
          "thinking.type\n  Input should be 'adaptive' or 'disabled' "
          "[type=literal_error, input_value='enabled']\nthinking.budget_tokens\n"
          '  Extra inputs are not permitted [type=extra_forbidden]',
          sent: 'enabled',
          rejected: {'thinking:adaptive'},
        ),
        every,
      );
      // `thinking` only inside the echo is not the field named.
      expect(
        read(
          'tools.0.input_schema\n  Field required [type=missing, '
          "input_value={'thinking': {'type': 'adaptive'}}, input_type=dict]",
          sent: 'adaptive',
        ),
        isNull,
      );
    });
  });
}
