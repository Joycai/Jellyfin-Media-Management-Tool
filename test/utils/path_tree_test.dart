import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/utils/path_tree.dart';

void main() {
  group('buildPathTree', () {
    test('returns an empty list for no paths', () {
      expect(buildPathTree(const []), isEmpty);
    });

    test('flattens a single path into folder + leaf', () {
      final lines = buildPathTree(['Movies/Dune (2021)/Dune.mkv']);
      expect(lines.map((l) => l.name).toList(), [
        'Movies',
        'Dune (2021)',
        'Dune.mkv',
      ]);
      expect(lines.map((l) => l.depth).toList(), [0, 1, 2]);
      expect(lines.map((l) => l.isDir).toList(), [true, true, false]);
    });

    test('deduplicates shared ancestors across siblings', () {
      final lines = buildPathTree([
        'Movies/Dune (2021)/Dune.mkv',
        'Movies/Dune (2021)/Dune.zh-Hans.srt',
      ]);
      expect(lines.map((l) => l.name).toList(), [
        'Movies',
        'Dune (2021)',
        'Dune.mkv',
        'Dune.zh-Hans.srt',
      ]);
    });

    test('sorts paths so the tree is stable', () {
      final lines = buildPathTree(['Shows/B/file.mkv', 'Shows/A/file.mkv']);
      final names = lines.map((l) => l.name).toList();
      // A's branch before B's
      expect(names.indexOf('A'), lessThan(names.indexOf('B')));
    });
  });
}
