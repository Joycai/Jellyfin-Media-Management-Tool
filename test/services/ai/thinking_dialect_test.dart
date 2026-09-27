import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/thinking_dialect.dart';

void main() {
  test('each dialect names its own field, both ways', () {
    final off = ThinkingDialect.thinkingType.field(thinking: false);
    expect(off.key, 'thinking');
    expect(off.value, {'type': 'disabled'});
    final on = ThinkingDialect.enableThinking.field(thinking: true);
    expect(on.key, 'enable_thinking');
    expect(on.value, isTrue);
    final router = ThinkingDialect.reasoningObject.field(thinking: false);
    expect(router.key, 'reasoning');
    expect(router.value, {'enabled': false});
  });

  test('a prose word names a field only quoted, dotted or as refused', () {
    // `thinking` and `reasoning` turn up in errors about other things; a
    // refusal read from one would drop a platform's switch for a month.
    for (final detail in [
      "'reasoning' is not a valid parameter",
      'reasoning.enabled: extra inputs are not permitted',
      'the reasoning parameter is not supported',
      'reasoning is mandatory for this model',
      'reasoning cannot be disabled on this model',
    ]) {
      expect(namesField(detail, 'reasoning'), isTrue, reason: detail);
    }
    for (final detail in [
      'reasoning_content is empty',
      "'reasoning_content' must be a string",
      'the model was reasoning about the request',
      'messages is mandatory',
    ]) {
      expect(namesField(detail, 'reasoning'), isFalse, reason: detail);
    }
    expect(namesField('`thinking` is not supported', 'thinking'), isTrue);
    expect(namesField('thinking.type: unsupported value', 'thinking'), isTrue);
    expect(
      namesField('see https://docs.example/thinking_mode', 'thinking'),
      isFalse,
    );
    // Any other name does not occur in prose: a plain substring.
    expect(
      namesField('unrecognized request argument supplied: top_k', 'top_k'),
      isTrue,
    );
    expect(
      namesField('reasoning_effort was set to medium', 'reasoning_effort'),
      isTrue,
    );
    expect(namesField('nothing about it', 'top_k'), isFalse);
  });

  test('every field that asks for reasoning is a name to read for', () {
    // What a relay may have translated one protocol's field into: each
    // dialect's, the ladder's, Gemini's — spelled as a server says it back.
    for (final dialect in ThinkingDialect.values) {
      expect(reasoningFieldNames, contains(dialect.field(thinking: true).key));
    }
    expect(
      reasoningFieldNames,
      containsAll([
        'reasoning_effort',
        'chat_template_kwargs',
        'thinkingconfig',
      ]),
    );
    for (final name in reasoningFieldNames) {
      expect(name, name.toLowerCase());
    }
  });

  test("the translated name is any of them but the protocol's own", () {
    String? named(String detail, {String own = 'thinking'}) =>
        translatedFieldNamed(detail, own: own);

    expect(
      named('unrecognized request argument supplied: reasoning_effort'),
      'reasoning_effort',
    );
    expect(
      named('unrecognized request argument supplied: enable_thinking'),
      'enable_thinking',
    );
    expect(named("'reasoning' is not a valid parameter"), 'reasoning');
    expect(named('unrecognized request argument supplied: thinking'), isNull);
    expect(named("'thinking' is not supported"), isNull);
    expect(named("'reasoning' is not supported", own: 'reasoning'), isNull);
    expect(named('the model was reasoning about it'), isNull);
    expect(named('top_k: extra inputs are not permitted'), isNull);
    expect(
      named("'thinking' is not supported", own: 'reasoning_effort'),
      'thinking',
    );
  });

  test('an old bare `thinking` record still lets adaptive be asked', () {
    // Written before the forms were told apart, when `enabled` was the
    // only one sent: no verdict on adaptive where adaptive comes first.
    const adaptive = MessagesThinking.adaptive;
    const extended = MessagesThinking.extended;
    expect(MessagesThinking.refusedIn({'thinking'}, first: adaptive), {
      extended,
    });
    // Where `enabled` comes first it was the model's own form, refused as
    // a feature: what such a refusal records now.
    expect(
      MessagesThinking.refusedIn({'thinking'}, first: extended),
      MessagesThinking.values.toSet(),
    );
    expect(
      MessagesThinking.refusedIn({
        'thinking',
        'thinking:adaptive',
      }, first: extended),
      {adaptive},
    );
    expect(
      MessagesThinking.refusedIn({
        'thinking',
        'thinking:adaptive',
        'thinking:enabled',
      }, first: adaptive),
      MessagesThinking.values.toSet(),
    );
  });
}
