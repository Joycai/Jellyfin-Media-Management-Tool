import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/thinking_dialect.dart';

void main() {
  test('platforms are recognised by host, subdomains included', () {
    expect(
      ThinkingDialect.forEndpoint('https://open.bigmodel.cn/api/paas/v4'),
      ThinkingDialect.thinkingType,
    );
    expect(
      ThinkingDialect.forEndpoint('https://api.deepseek.com'),
      ThinkingDialect.thinkingType,
    );
    for (final host in ['dashscope', 'dashscope-intl', 'dashscope-us']) {
      expect(
        ThinkingDialect.forEndpoint(
          'https://$host.aliyuncs.com/compatible-mode/v1',
        ),
        ThinkingDialect.enableThinking,
      );
    }
  });

  test('a look-alike host is not the platform', () {
    expect(ThinkingDialect.forEndpoint('https://notbigmodel.cn'), isNull);
    expect(ThinkingDialect.forEndpoint('https://oss.aliyuncs.com'), isNull);
    expect(ThinkingDialect.forEndpoint('http://localhost:1234'), isNull);
    expect(ThinkingDialect.forEndpoint(''), isNull);
  });

  test('each dialect names its own field', () {
    final off = ThinkingDialect.thinkingType.field(thinking: false);
    expect(off.key, 'thinking');
    expect(off.value, {'type': 'disabled'});
    final on = ThinkingDialect.enableThinking.field(thinking: true);
    expect(on.key, 'enable_thinking');
    expect(on.value, isTrue);
  });
}
