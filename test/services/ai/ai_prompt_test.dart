import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_prompt.dart';
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

List<MediaEntryInput> _episodes(int count) => [
  for (var i = 1; i <= count; i++)
    MediaEntryInput(
      relativePath: 'Some.Show.S01E${'$i'.padLeft(2, '0')}.1080p.WEB-DL.mkv',
      sizeBytes: 1000000000,
      kind: 'Video',
    ),
];

int _replyCost(List<MediaEntryInput> batch) => batch.fold(
  0,
  (sum, e) => sum + 2 * TokenBudget.estimate(e.relativePath) + 60,
);

void main() {
  group('batchEntries', () {
    test('without a budget the folder is one request, as before', () {
      final entries = _episodes(400);

      final batches = AiPrompt.batchEntries(
        entries,
        config: _config(),
        folderName: 'Some Show',
      );

      expect(batches, hasLength(1));
      expect(batches.single, same(entries));
    });

    test('a small window splits the folder so every request fits', () {
      const window = 4096;
      final entries = _episodes(60);

      final batches = AiPrompt.batchEntries(
        entries,
        config: _config(window: window),
        folderName: 'Some Show',
      );

      expect(batches.length, greaterThan(1));
      expect(batches.expand((b) => b).toList(), entries);
      for (final batch in batches) {
        final prompt = AiPrompt.buildUserPrompt(
          folderName: 'Some Show',
          entries: batch,
          knownFolders: const ['Shows/Some Show (2020)'],
        );
        final sent =
            TokenBudget.estimate(AiPrompt.systemPrompt) +
            TokenBudget.estimate(prompt);
        expect(sent + _replyCost(batch), lessThan(window));
      }
    });

    test('an output cap alone splits too', () {
      final batches = AiPrompt.batchEntries(
        _episodes(40),
        config: _config(maxOutput: 1000),
        folderName: 'Some Show',
      );

      expect(batches.length, greaterThan(1));
      for (final batch in batches) {
        expect(_replyCost(batch), lessThanOrEqualTo(1000));
      }
    });

    test('a file too large for any batch still goes, alone', () {
      const huge = MediaEntryInput(
        relativePath: 'An.Extremely.Long.Name.mkv',
        sizeBytes: 1,
        kind: 'Video',
      );
      final oversized = MediaEntryInput(
        relativePath: '${'x' * 30000}.mkv',
        sizeBytes: 1,
        kind: 'Video',
      );

      final batches = AiPrompt.batchEntries(
        [huge, oversized, huge],
        config: _config(window: 2048),
        folderName: 'Some Show',
      );

      expect(batches.expand((b) => b), contains(oversized));
      expect(batches.firstWhere((b) => b.contains(oversized)), hasLength(1));
    });
  });

  test('titleFolders keeps the root and title folder of each target', () {
    expect(
      AiPrompt.titleFolders([
        'Shows/Some Show (2020)/Season 01/Some Show S01E01.mkv',
        'Shows/Some Show (2020)/Season 01/Some Show S01E02.mkv',
        r'Movies\Film (1999)\Film (1999).mkv',
        'Movies/loose.mkv',
        'loose.mkv',
      ]),
      ['Shows/Some Show (2020)', 'Movies/Film (1999)'],
    );
  });

  test('later batches are told the folders earlier ones chose', () {
    final prompt = AiPrompt.buildUserPrompt(
      folderName: 'Some Show',
      entries: const [],
      knownFolders: const ['Shows/Some Show (2020)'],
    );

    expect(prompt, contains('"Shows/Some Show (2020)"'));
    expect(
      AiPrompt.buildUserPrompt(folderName: 'Some Show', entries: const []),
      isNot(contains('batches')),
    );
  });
}
