import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/messages_refusal.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';

/// What [MessagesRefusal.read] makes of [message] for a request that asked
/// for thinking as [sent] (`adaptive`, `enabled`, `disabled`, or null for
/// none) and carried the sampling fields [optional], on a route that already
/// refused [rejected] — a relay, or MiniMax's `/anthropic` when [switchRoute].
/// [least]: off said as the least reasoning, `output_config: {effort: low}`.
RefusalLesson? read(
  String message, {
  String? sent,
  bool least = false,
  List<String> optional = const [],
  Set<String> rejected = const {},
  bool switchRoute = false,
  String model = 'claude-opus-4-6',
  String? endpoint,
}) => MessagesRefusal.read(
  message,
  payload: {
    'model': model,
    if (sent != null) 'thinking': {'type': sent},
    if (least) 'output_config': {'effort': 'low'},
    for (final field in optional) field: 1,
  },
  learned: LearnedBehaviour(rejectedFields: rejected),
  config: AiConfig(
    provider: AiProviderType.anthropic,
    endpoint:
        endpoint ??
        (switchRoute
            ? 'https://api.minimaxi.com/anthropic'
            : 'https://relay.example'),
    apiKey: 'k',
    model: model,
  ),
);

final every = ThinkingFormsRefused(MessagesRefusal.everyThinkingForm);
const adaptive = ThinkingFormsRefused({'thinking:adaptive'});
const enabled = ThinkingFormsRefused({'thinking:enabled'});
const off = OffRefused(MessagesOff.disabled);

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
    expect(
      const OffRefused(
        MessagesOff.leastEffort,
      ).apply(off.apply(learned)).thinkingOffTried,
      {LearnedBehaviour.dialectOff, LearnedBehaviour.leastEffortOff},
    );
    expect(off, isNot(const OffRefused(MessagesOff.leastEffort)));
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
    expect(off, const OffRefused(MessagesOff.disabled));
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

  group('wordings measured on 2026-09-28', () {
    const dashScope = 'https://dashscope.aliyuncs.com/apps/anthropic';
    const zhipu = 'https://open.bigmodel.cn/api/anthropic';
    const sampling = ['temperature', 'top_p', 'top_k'];
    // DashScope translates `thinking` into its own `enable_thinking` and
    // passes the refusal back: MiniMax-M2.5 and glm-5.3 there told off.
    const restricted =
        '<400> InternalError.Algo.InvalidParameter: The value of the '
        'enable_thinking parameter is restricted to True.';
    // Zhipu's own Messages face, glm-5.3 told off: code 1210, the words
    // wrapped in brackets with the request id.
    const zhipu1210 =
        '[1210][该模型始终思考，不支持关闭思考；请使用 low、high 或 max。]'
        '[202609281155421633d5b34a1644c0]';

    test('a translated name "restricted to true" is the model that '
        'cannot stop', () {
      expect(
        read(
          restricted,
          sent: 'disabled',
          optional: sampling,
          endpoint: dashScope,
          model: 'MiniMax-M2.5',
        ),
        off,
      );
      // On a relay too: the words say what they say wherever they come from.
      expect(read(restricted, sent: 'disabled', optional: sampling), off);
      // Asked on, the same words name no form and refuse nothing: thrown.
      expect(read(restricted, sent: 'adaptive', endpoint: dashScope), isNull);
      // Without the name it is any parameter, not the model.
      expect(
        read(
          'The value of the frobnicate parameter is restricted to True.',
          sent: 'disabled',
          endpoint: dashScope,
        ),
        isNull,
      );
    });

    test('Zhipu 1210, wrapped, is the model that cannot stop', () {
      expect(
        read(
          zhipu1210,
          sent: 'disabled',
          optional: sampling,
          endpoint: zhipu,
          model: 'glm-5.3',
        ),
        off,
      );
      // Asked on (a bad type, which the adapter never sends), it names no
      // form: nothing learned.
      expect(read(zhipu1210, sent: 'adaptive', endpoint: zhipu), isNull);
    });

    test('a budget or a body error teaches nothing', () {
      expect(
        read(
          '<400> InternalError.Algo.InvalidParameter: max_completion_tokens '
          '[512] must be greater than thinking_budget [1024]',
          sent: 'enabled',
          endpoint: dashScope,
          model: 'qwen3.8-flash',
        ),
        isNull,
      );
      expect(
        read(
          'Request body format invalid',
          sent: 'adaptive',
          endpoint: dashScope,
          model: 'qwen3.8-flash',
        ),
        isNull,
      );
    });

    test('a sampling value out of range is that value refused', () {
      expect(
        read(
          '<400> InternalError.Algo.InvalidParameter: Temperature should be '
          'in [0.0, 2.0)',
          sent: 'disabled',
          optional: sampling,
          endpoint: dashScope,
          model: 'qwen3.8-flash',
        ),
        const OptionalRefused('temperature'),
      );
      expect(
        read(
          "invalid params, param 'top_p' should be in (0,1] (2013)",
          optional: sampling,
          switchRoute: true,
          model: 'MiniMax-M3',
        ),
        const OptionalRefused('top_p'),
      );
    });
  });
  group('off said as the least reasoning', () {
    const zhipu = 'https://open.bigmodel.cn/api/anthropic';
    const least = OffRefused(MessagesOff.leastEffort);
    RefusalLesson? readLeast(
      String message, {
      List<String> optional = const [],
    }) => read(
      message,
      least: true,
      optional: optional,
      endpoint: zhipu,
      model: 'glm-5.3',
    );

    test('refused in any words is that rung refused', () {
      for (final message in [
        // Zhipu's 5.3 answers every effort but low, high and max so
        // (measured 2026-09-28 for medium, minimal and none).
        '[1210][该模型始终思考，不支持关闭思考；请使用 low、high 或 max。][id]',
        // Zhipu's own name for the field (measured, for a bad value).
        '[1210][reasoning_effort 参数值非法，可选值为：none、minimal、low、medium、'
            'high、xhigh、max][id]',
        // DashScope's words (measured, for a bad value).
        "Invalid value 'low' for output_config.effort. Supported values are: "
            'medium, high, xhigh, max.',
        // Pydantic, a relay that does not know the field.
        '1 validation error for Request\noutput_config\n  Extra inputs are not '
            "permitted [type=extra_forbidden, input_value={'effort': 'low'}, "
            'input_type=dict]',
        'Unknown parameter: output_config.effort',
        "effort: unsupported value 'low'",
        // Another protocol's field, as a relay translated it.
        'Unrecognized request argument supplied: reasoning_effort',
      ]) {
        expect(readLeast(message), least, reason: message);
      }
    });

    test('what is about something else is not', () {
      // A sampling value named first is that value, as for any request.
      expect(
        readLeast(
          'Temperature should be in [0.0, 2.0) with output_config set',
          optional: ['temperature'],
        ),
        const OptionalRefused('temperature'),
      );
      // The thinking blocks in the history.
      expect(
        readLeast(
          'messages.1.content.0: Invalid `signature` in `thinking` block',
        ),
        isNull,
      );
      // The effort named, nothing refused.
      expect(
        readLeast(
          'max_tokens: 99999 > 8192, the maximum for this model at '
          'output_config.effort low',
        ),
        isNull,
      );
      // `effort` inside another word is no name of it.
      expect(readLeast('the best-efforts queue is full, retry later'), isNull);
      // Nothing about off at all.
      expect(readLeast('messages: at least one message is required'), isNull);
    });

    test('the effort is a name of thinking only where the request '
        'carried it', () {
      // Asked off as `disabled`, a sentence naming `output_config` is not
      // about thinking: nothing learned from it.
      expect(
        read(
          'Unknown parameter: output_config.effort',
          sent: 'disabled',
          endpoint: zhipu,
          model: 'glm-5.3',
        ),
        isNull,
      );
    });
  });
}
