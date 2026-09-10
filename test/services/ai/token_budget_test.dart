import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/token_budget.dart';

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
}
