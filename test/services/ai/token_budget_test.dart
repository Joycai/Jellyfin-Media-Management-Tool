import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/token_budget.dart';

AiConfig _config({int? window, int? maxOutput}) => AiConfig(
  provider: AiProviderType.openAi,
  endpoint: 'http://localhost:1234',
  apiKey: '',
  model: 'local-model',
  contextWindow: window,
  maxOutputTokens: maxOutput,
);

void main() {
  group('estimate', () {
    test('charges ASCII at three characters per token', () {
      expect(TokenBudget.estimate(''), 0);
      expect(TokenBudget.estimate('abc'), 1);
      expect(TokenBudget.estimate('abcd'), 2);
    });

    test('charges every other character a whole token', () {
      expect(TokenBudget.estimate('作品番号'), 4);
      // One code point, two UTF-16 units.
      expect(TokenBudget.estimate('😀'), 1);
    });
  });

  group('truncate', () {
    test('leaves text that fits untouched', () {
      expect(TokenBudget.truncate('short', 10, marker: '…'), 'short');
    });

    test('cuts to the budget with the marker counted', () {
      final cut = TokenBudget.truncate('x' * 300, 20, marker: '!!!');

      expect(cut, '${'x' * 57}!!!');
      expect(TokenBudget.estimate(cut), lessThanOrEqualTo(20));
    });

    test('never splits a surrogate pair', () {
      expect(TokenBudget.truncate('😀' * 10, 3), '😀' * 3);
    });
  });

  group('inputAllowance', () {
    test('is null without a context window', () {
      expect(
        TokenBudget.inputAllowance(
          _config(),
          fixedPrompt: 'x',
          reservedOutput: 100,
        ),
        isNull,
      );
    });

    test('subtracts margin, template, prompt and reply', () {
      // 90% of 8000, less the template, a 100-token prompt, the reply.
      expect(
        TokenBudget.inputAllowance(
          _config(window: 8000),
          fixedPrompt: 'x' * 300,
          reservedOutput: 1000,
        ),
        7200 - 64 - 100 - 1000,
      );
    });

    test('an output cap replaces the reserve, up to half the window', () {
      expect(
        TokenBudget.inputAllowance(
          _config(window: 8000, maxOutput: 500),
          fixedPrompt: '',
          reservedOutput: 1000,
        ),
        7200 - 64 - 500,
      );
      expect(
        TokenBudget.inputAllowance(
          _config(window: 8000, maxOutput: 7000),
          fixedPrompt: '',
          reservedOutput: 1000,
        ),
        7200 - 64 - 4000,
      );
    });

    test('never drops below the floor', () {
      expect(
        TokenBudget.inputAllowance(
          _config(window: 1000),
          fixedPrompt: 'x' * 3000,
          reservedOutput: 400,
        ),
        TokenBudget.minimumInput,
      );
    });
  });
}
