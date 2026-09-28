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

  group('one sentence about thinking, another naming a value (#119 known '
      'issues 2 and 3)', () {
    // Recorded as the code reads them today; the next slice makes the
    // field a sentence names first the one it refuses.
    const optional = ['temperature', 'top_p', 'top_k'];

    test('a value named in passing is taken first', () {
      // today: OptionalRefused('temperature'); wanted: every form
      expect(
        read(
          'reasoning_effort is not supported; use temperature instead',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        const OptionalRefused('temperature'),
      );
      // today: OptionalRefused('temperature'); wanted: off refused
      expect(
        read(
          'reasoning is mandatory for this model; temperature is ignored',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        const OptionalRefused('temperature'),
      );
      // today: OptionalRefused('temperature'); wanted: every form
      expect(
        read(
          'Unsupported parameter: reasoning_effort. Supported parameters: '
          'temperature, top_p, top_k, max_tokens',
          sent: 'disabled',
          optional: optional,
          switchRoute: true,
        ),
        const OptionalRefused('temperature'),
      );
    });

    test('a value refused beside the word thinking gives thinking up', () {
      // today: every form; wanted: the value
      for (final message in [
        'temperature is not supported with thinking',
        'top_p is not supported in thinking mode',
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
  });
}
