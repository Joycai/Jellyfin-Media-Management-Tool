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
