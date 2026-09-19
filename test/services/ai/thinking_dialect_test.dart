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
}
