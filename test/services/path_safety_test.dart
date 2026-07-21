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

  // Without an explicit context the host's style decides, which on Windows
  // reads `/work` as root-relative and resolves it against the current drive.
  group('PathSafety.isWithin — explicit context', () {
    test('honours a posix context on any host', () {
      expect(
        PathSafety.isWithin('/work', '/work/Movies/Dune.mkv', context: p.posix),
        isTrue,
      );
      expect(
        PathSafety.isWithin('/work', '/etc/passwd', context: p.posix),
        isFalse,
      );
    });

    test('honours a windows context on any host', () {
      expect(
        PathSafety.isWithin(
          r'C:\work',
          r'C:\work\Movies\Dune.mkv',
          context: p.windows,
        ),
        isTrue,
      );
      expect(
        PathSafety.isWithin(
          r'C:\work',
          r'C:\workshop\Dune.mkv',
          context: p.windows,
        ),
        isFalse,
      );
    });
  });
}
