import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';

OrganizeAction _action(String source, String target) => OrganizeAction(
  source: source,
  target: target,
  kind: 'video',
  confidence: 0.9,
  note: '',
);

OrganizePlan _plan({
  String mediaType = 'series',
  String targetRoot = 'Shows',
  List<String> reasoning = const [],
  List<OrganizeAction> actions = const [],
  int promptTokens = 0,
  int completionTokens = 0,
}) => OrganizePlan(
  mediaType: mediaType,
  targetRoot: targetRoot,
  reasoning: reasoning,
  actions: actions,
  promptTokens: promptTokens,
  completionTokens: completionTokens,
);

void main() {
  group('OrganizePlan.merge', () {
    test('a single batch comes back as it was', () {
      final only = _plan();
      expect(OrganizePlan.merge([only]), same(only));
    });

    test('joins batches, keeping the first answer for a repeated source', () {
      final merged = OrganizePlan.merge([
        _plan(
          reasoning: ['a', 'b'],
          actions: [
            _action('e1.mkv', 'Shows/S/e1.mkv'),
            _action('e2.mkv', 'Shows/S/e2.mkv'),
          ],
          promptTokens: 100,
          completionTokens: 50,
        ),
        _plan(
          mediaType: 'unknown',
          targetRoot: '',
          reasoning: ['b', 'c'],
          actions: [
            _action('e2.mkv', 'Elsewhere/e2.mkv'),
            _action('e3.mkv', 'Shows/S/e3.mkv'),
          ],
          promptTokens: 80,
          completionTokens: 40,
        ),
      ]);

      expect(merged.mediaType, 'series');
      expect(merged.targetRoot, 'Shows');
      expect(merged.reasoning, ['a', 'b', 'c']);
      expect(merged.actions.map((a) => a.target), [
        'Shows/S/e1.mkv',
        'Shows/S/e2.mkv',
        'Shows/S/e3.mkv',
      ]);
      expect(merged.promptTokens, 180);
      expect(merged.completionTokens, 90);
    });

    test('batches that disagree make a mixed plan', () {
      final merged = OrganizePlan.merge([
        _plan(mediaType: 'movie', targetRoot: 'Movies'),
        _plan(mediaType: 'series'),
      ]);

      expect(merged.mediaType, 'mixed');
      expect(merged.targetRoot, 'Movies');
    });
  });
}
