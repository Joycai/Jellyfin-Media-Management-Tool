import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/path_safety.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PathSafety.isWithin', () {
    test('accepts a direct child', () {
      expect(PathSafety.isWithin('/work', p.join('/work', 'a.mkv')), isTrue);
    });

    test('accepts a deep descendant', () {
      expect(
        PathSafety.isWithin('/work', '/work/Movies/Dune (2021)/Dune.mkv'),
        isTrue,
      );
    });

    test('treats the base itself as within', () {
      expect(PathSafety.isWithin('/work', '/work'), isTrue);
      expect(PathSafety.isWithin('/work', '/work/'), isTrue);
    });

    test('rejects traversal via ..', () {
      expect(
        PathSafety.isWithin(
          '/work',
          p.normalize(p.join('/work', '../etc/passwd')),
        ),
        isFalse,
      );
      expect(
        PathSafety.isWithin(
          '/work',
          p.normalize(p.join('/work', '../../tmp/x.mkv')),
        ),
        isFalse,
      );
    });

    test('rejects unrelated absolute paths', () {
      expect(PathSafety.isWithin('/work', '/etc/passwd'), isFalse);
      expect(PathSafety.isWithin('/work', '/tmp/x.mkv'), isFalse);
    });

    test('rejects sibling directory with shared prefix', () {
      // /workshop starts with /work but isn't inside it
      expect(PathSafety.isWithin('/work', '/workshop/x.mkv'), isFalse);
    });
  });
}
