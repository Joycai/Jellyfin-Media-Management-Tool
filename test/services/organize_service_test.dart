import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/organize_service.dart';

import '../helpers/fs.dart';

OrganizeAction _act(String source, String target) => OrganizeAction(
  source: source,
  target: target,
  kind: 'video',
  confidence: 0.95,
  note: '',
);

void main() {
  late FileSystem fs;
  const base = '/work';

  setUp(() {
    fs = newMemoryFs();
  });

  group('applyOrganizeAction — happy path', () {
    test('renames a file in place', () async {
      seedFile(fs, '/work/Dune.2021.mkv', contents: 'video');
      final action = _act(
        'Dune.2021.mkv',
        'Movies/Dune (2021)/Dune (2021).mkv',
      );

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isTrue);
      expect(outcome.bytes, equals(5));
      expect(action.status, ActionStatus.applied);
      expect(
        fs.file('/work/Movies/Dune (2021)/Dune (2021).mkv').existsSync(),
        isTrue,
      );
      expect(fs.file('/work/Dune.2021.mkv').existsSync(), isFalse);
    });

    test('treats source==target as a no-op success', () async {
      seedFile(fs, '/work/a.mkv');
      final action = _act('a.mkv', 'a.mkv');

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isTrue);
      expect(action.status, ActionStatus.applied);
    });
  });

  group('applyOrganizeAction — failures', () {
    test('rejects target that escapes baseDir via ..', () async {
      seedFile(fs, '/work/a.mkv');
      final action = _act('a.mkv', '../escape.mkv');

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isFalse);
      expect(action.status, ActionStatus.failed);
      expect(outcome.error, contains('escapes'));
      // The would-be target stays unwritten.
      expect(fs.file('/escape.mkv').existsSync(), isFalse);
    });

    test('rejects target that is an absolute outside path', () async {
      seedFile(fs, '/work/a.mkv');
      final action = _act('a.mkv', '/etc/passwd');

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isFalse);
      expect(action.status, ActionStatus.failed);
      expect(outcome.error, contains('escapes'));
    });

    test('rejects source that escapes baseDir', () async {
      final action = _act('../outside.mkv', 'Movies/x.mkv');

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('escapes'));
    });

    test('fails when source is missing', () async {
      final action = _act('missing.mkv', 'Movies/x.mkv');

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isFalse);
      expect(action.status, ActionStatus.failed);
      expect(outcome.error, contains('Source'));
    });

    test('refuses to clobber an existing target file', () async {
      seedFile(fs, '/work/a.mkv', contents: 'src');
      seedFile(fs, '/work/Movies/a.mkv', contents: 'existing');
      final action = _act('a.mkv', 'Movies/a.mkv');

      final outcome = await applyOrganizeAction(action, baseDir: base, fs: fs);

      expect(outcome.ok, isFalse);
      expect(action.status, ActionStatus.failed);
      expect(outcome.error, contains('exists'));
      // Both files stay where they were.
      expect(fs.file('/work/a.mkv').readAsStringSync(), equals('src'));
      expect(
        fs.file('/work/Movies/a.mkv').readAsStringSync(),
        equals('existing'),
      );
    });
  });

  // The rest of the suite runs on a POSIX in-memory tree regardless of host, so
  // it only proves the service is not hardcoded to Windows. These prove the
  // reverse, and that both come from `fs.path` rather than the ambient style.
  group('applyOrganizeAction — Windows path style', () {
    late FileSystem winFs;
    const winBase = r'C:\work';

    setUp(() {
      winFs = newWindowsMemoryFs();
    });

    test('renames a file in place', () async {
      seedFile(winFs, r'C:\work\Dune.2021.mkv', contents: 'video');
      final action = _act(
        'Dune.2021.mkv',
        r'Movies\Dune (2021)\Dune (2021).mkv',
      );

      final outcome = await applyOrganizeAction(
        action,
        baseDir: winBase,
        fs: winFs,
      );

      expect(outcome.ok, isTrue);
      expect(action.status, ActionStatus.applied);
      expect(
        winFs.file(r'C:\work\Movies\Dune (2021)\Dune (2021).mkv').existsSync(),
        isTrue,
      );
      expect(winFs.file(r'C:\work\Dune.2021.mkv').existsSync(), isFalse);
    });

    test('rejects a target that escapes baseDir', () async {
      seedFile(winFs, r'C:\work\a.mkv');
      final action = _act('a.mkv', r'..\escape.mkv');

      final outcome = await applyOrganizeAction(
        action,
        baseDir: winBase,
        fs: winFs,
      );

      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('escapes'));
    });
  });
}
