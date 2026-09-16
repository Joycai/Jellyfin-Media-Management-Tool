import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/transfer/file_transfer.dart';

import '../../helpers/fs.dart';

void main() {
  late FileSystem fs;

  setUp(() {
    fs = newMemoryFs();
    fs.directory('/work/dest').createSync(recursive: true);
  });

  Future<TransferResult> run(
    List<String> sources, {
    TransferMode mode = TransferMode.copy,
    ConflictPolicy policy = ConflictPolicy.keepBoth,
    String dest = '/work/dest',
    bool Function()? shouldStop,
    void Function(int)? onProgress,
  }) async {
    final plan = await planTransfer(
      sources: sources,
      destinationDir: dest,
      mode: mode,
      fs: fs,
    );
    return executeTransfer(
      plan,
      policy: policy,
      fs: fs,
      shouldStop: shouldStop,
      onProgress: onProgress,
    );
  }

  group('planTransfer', () {
    test('sizes files and trees, and flags existing targets', () async {
      seedFile(fs, '/work/a.mkv', contents: 'abcde');
      seedFile(fs, '/work/Show/S01/e1.mkv', contents: 'xyz');
      seedFile(fs, '/work/Show/S01/e2.mkv', contents: 'xy');
      seedFile(fs, '/work/dest/a.mkv');

      final plan = await planTransfer(
        sources: ['/work/a.mkv', '/work/Show'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );

      expect(plan.items.map((i) => i.bytes), [5, 5]);
      expect(plan.totalBytes, 10);
      expect(plan.conflicts.map((i) => i.source), ['/work/a.mkv']);
      expect(plan.items[1].target, '/work/dest/Show');
      expect(plan.refused, isEmpty);
    });

    test('refuses a folder pasted into itself or a child of itself', () async {
      seedFile(fs, '/work/Show/S01/e1.mkv');

      final self = await planTransfer(
        sources: ['/work/Show'],
        destinationDir: '/work/Show',
        mode: TransferMode.copy,
        fs: fs,
      );
      final child = await planTransfer(
        sources: ['/work/Show'],
        destinationDir: '/work/Show/S01',
        mode: TransferMode.move,
        fs: fs,
      );

      expect(self.items, isEmpty);
      expect(self.refused.single.reason, TransferRefusal.intoItself);
      expect(child.refused.single.reason, TransferRefusal.intoItself);
    });

    test('a move into the folder the item already lives in is refused, '
        'a copy there is a conflict', () async {
      seedFile(fs, '/work/dest/a.mkv');

      final move = await planTransfer(
        sources: ['/work/dest/a.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.move,
        fs: fs,
      );
      final copy = await planTransfer(
        sources: ['/work/dest/a.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );

      expect(move.refused.single.reason, TransferRefusal.sameFolder);
      expect(copy.conflicts, hasLength(1));
    });

    test('a missing source is refused, a duplicate is folded', () async {
      seedFile(fs, '/work/a.mkv');

      final plan = await planTransfer(
        sources: ['/work/a.mkv', '/work/a.mkv', '/work/gone.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );

      expect(plan.items, hasLength(1));
      expect(plan.refused.single.reason, TransferRefusal.missing);
    });

    test('a link source, or a folder holding one, is refused', () async {
      seedFile(fs, '/work/real.mkv');
      fs.link('/work/alias.mkv').createSync('/work/real.mkv');
      seedFile(fs, '/work/Show/e1.mkv');
      fs.link('/work/Show/poster.jpg').createSync('/work/real.mkv');

      final plan = await planTransfer(
        sources: ['/work/alias.mkv', '/work/Show', '/work/real.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.move,
        fs: fs,
      );

      expect(plan.items.map((i) => i.source), ['/work/real.mkv']);
      expect(
        plan.refused.map((r) => r.reason),
        everyElement(TransferRefusal.link),
      );
      expect(plan.refused, hasLength(2));
    });

    test('throws when the destination is not a directory', () async {
      seedFile(fs, '/work/a.mkv');
      expect(
        () => planTransfer(
          sources: ['/work/a.mkv'],
          destinationDir: '/work/nope',
          mode: TransferMode.copy,
          fs: fs,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('reads paths in the injected filesystem style', () async {
      final win = newWindowsMemoryFs();
      win.directory(r'C:\work\dest').createSync();
      seedFile(win, r'C:\work\a.mkv', contents: 'x');

      final plan = await planTransfer(
        sources: [r'C:\work\a.mkv'],
        destinationDir: r'C:\work\dest',
        mode: TransferMode.copy,
        fs: win,
      );

      expect(plan.items.single.target, r'C:\work\dest\a.mkv');
    });
  });

  group('executeTransfer — copy', () {
    test('copies a file and records it as created', () async {
      seedFile(fs, '/work/a.mkv', contents: 'video');
      final progress = <int>[];

      final r = await run(['/work/a.mkv'], onProgress: progress.add);

      expect(r.succeeded, 1);
      expect(fs.file('/work/a.mkv').existsSync(), isTrue);
      expect(fs.file('/work/dest/a.mkv').readAsStringSync(), 'video');
      expect(r.created, ['/work/dest/a.mkv']);
      expect(r.moves, isEmpty);
      expect(progress, [5]);
      expect(r.bytesDone, 5);
    });

    test('copies a tree, including empty folders', () async {
      seedFile(fs, '/work/Show/S01/e1.mkv', contents: '1');
      seedFile(fs, '/work/Show/S01/e2.mkv', contents: '22');
      fs.directory('/work/Show/extras').createSync();

      final r = await run(['/work/Show']);

      expect(r.succeeded, 1);
      expect(fs.file('/work/dest/Show/S01/e2.mkv').readAsStringSync(), '22');
      expect(fs.directory('/work/dest/Show/extras').existsSync(), isTrue);
      expect(
        r.created,
        unorderedEquals([
          '/work/dest/Show/S01/e1.mkv',
          '/work/dest/Show/S01/e2.mkv',
        ]),
      );
      expect(r.bytesDone, 3);
    });

    test(
      'keep-both numbers the copy, skip leaves the original alone',
      () async {
        seedFile(fs, '/work/a.mkv', contents: 'new');
        seedFile(fs, '/work/dest/a.mkv', contents: 'old');
        seedFile(fs, '/work/dest/a (2).mkv');

        final kept = await run(['/work/a.mkv']);
        expect(kept.succeeded, 1);
        expect(fs.file('/work/dest/a.mkv').readAsStringSync(), 'old');
        expect(fs.file('/work/dest/a (3).mkv').readAsStringSync(), 'new');

        final skipped = await run(['/work/a.mkv'], policy: ConflictPolicy.skip);
        expect(skipped.succeeded, 0);
        expect(skipped.skipped, 1);
        expect(fs.file('/work/dest/a (4).mkv').existsSync(), isFalse);
      },
    );

    test('a folder is numbered whole, not split at a dot', () async {
      seedFile(fs, '/work/Show.2024/e1.mkv', contents: '1');
      fs.directory('/work/dest/Show.2024').createSync();

      final r = await run(['/work/Show.2024']);

      expect(r.succeeded, 1);
      expect(fs.file('/work/dest/Show.2024 (2)/e1.mkv').existsSync(), isTrue);
    });

    test('two sources with the same name never share a target', () async {
      seedFile(fs, '/work/x/a.mkv', contents: '1');
      seedFile(fs, '/work/y/a.mkv', contents: '2');

      final r = await run(['/work/x/a.mkv', '/work/y/a.mkv']);

      expect(r.succeeded, 2);
      expect(fs.file('/work/dest/a.mkv').readAsStringSync(), '1');
      expect(fs.file('/work/dest/a (2).mkv').readAsStringSync(), '2');
    });

    test('a copy into the same folder gets a numbered name', () async {
      seedFile(fs, '/work/dest/a.mkv', contents: 'v');

      final r = await run(['/work/dest/a.mkv']);

      expect(r.succeeded, 1);
      expect(fs.file('/work/dest/a (2).mkv').readAsStringSync(), 'v');
    });
  });

  group('executeTransfer — move', () {
    test('moves a file and records the move for undo', () async {
      seedFile(fs, '/work/a.mkv', contents: 'video');

      final r = await run(['/work/a.mkv'], mode: TransferMode.move);

      expect(r.succeeded, 1);
      expect(fs.file('/work/a.mkv').existsSync(), isFalse);
      expect(fs.file('/work/dest/a.mkv').readAsStringSync(), 'video');
      expect(r.moves, [
        {'from': '/work/a.mkv', 'to': '/work/dest/a.mkv'},
      ]);
      expect(r.created, isEmpty);
    });

    test('a moved tree is recorded file by file', () async {
      seedFile(fs, '/work/Show/S01/e1.mkv', contents: '1');
      seedFile(fs, '/work/Show/S01/e2.mkv', contents: '22');

      final r = await run(['/work/Show'], mode: TransferMode.move);

      expect(r.succeeded, 1);
      expect(fs.directory('/work/Show').existsSync(), isFalse);
      expect(fs.file('/work/dest/Show/S01/e2.mkv').readAsStringSync(), '22');
      expect(
        r.moves,
        unorderedEquals([
          {'from': '/work/Show/S01/e1.mkv', 'to': '/work/dest/Show/S01/e1.mkv'},
          {'from': '/work/Show/S01/e2.mkv', 'to': '/work/dest/Show/S01/e2.mkv'},
        ]),
      );
      expect(r.bytesDone, 3);
    });

    test(
      'a move never overwrites: keep-both renames, skip leaves it',
      () async {
        seedFile(fs, '/work/a.mkv', contents: 'new');
        seedFile(fs, '/work/dest/a.mkv', contents: 'old');

        final r = await run(['/work/a.mkv'], mode: TransferMode.move);

        expect(fs.file('/work/dest/a.mkv').readAsStringSync(), 'old');
        expect(fs.file('/work/dest/a (2).mkv').readAsStringSync(), 'new');
        expect(r.moves.single['to'], '/work/dest/a (2).mkv');
      },
    );
  });

  group('executeTransfer — batch behaviour', () {
    test('one failure does not abort the batch', () async {
      seedFile(fs, '/work/a.mkv', contents: 'a');
      seedFile(fs, '/work/b.mkv', contents: 'b');
      final plan = await planTransfer(
        sources: ['/work/a.mkv', '/work/b.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );
      // Pull the rug from under the first item after planning.
      fs.file('/work/a.mkv').deleteSync();

      final r = await executeTransfer(
        plan,
        policy: ConflictPolicy.keepBoth,
        fs: fs,
      );

      expect(r.failed, 1);
      expect(r.succeeded, 1);
      expect(r.failures.single.source, '/work/a.mkv');
      expect(fs.file('/work/dest/b.mkv').existsSync(), isTrue);
    });

    test('a target escaping the destination is refused at run time', () async {
      seedFile(fs, '/work/a.mkv');
      final plan = await planTransfer(
        sources: ['/work/a.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );
      plan.items.single.target = '/work/escape.mkv';

      final r = await executeTransfer(
        plan,
        policy: ConflictPolicy.keepBoth,
        fs: fs,
      );

      expect(r.failed, 1);
      expect(r.failures.single.error, contains('escapes'));
      expect(fs.file('/work/escape.mkv').existsSync(), isFalse);
    });

    test('stopping ends the batch after the file in flight', () async {
      seedFile(fs, '/work/a.mkv', contents: 'a');
      seedFile(fs, '/work/b.mkv', contents: 'b');
      var calls = 0;

      final r = await run([
        '/work/a.mkv',
        '/work/b.mkv',
      ], shouldStop: () => ++calls > 1);

      expect(r.stopped, isTrue);
      expect(r.succeeded, 1);
      expect(fs.file('/work/dest/a.mkv').existsSync(), isTrue);
      expect(fs.file('/work/dest/b.mkv').existsSync(), isFalse);
    });

    test('stopping inside a tree removes the partial copy', () async {
      seedFile(fs, '/work/Show/e1.mkv', contents: '1');
      seedFile(fs, '/work/Show/e2.mkv', contents: '2');
      var calls = 0;

      final r = await run(['/work/Show'], shouldStop: () => ++calls > 1);

      expect(r.stopped, isTrue);
      expect(r.succeeded, 0);
      expect(fs.directory('/work/dest/Show').existsSync(), isFalse);
      expect(fs.file('/work/Show/e1.mkv').existsSync(), isTrue);
    });
  });

  group('numberedName', () {
    test('numbers a file before its extension and a folder whole', () {
      expect(numberedName('a.mkv', 2, isDirectory: false), 'a (2).mkv');
      expect(numberedName('a.tar.gz', 3, isDirectory: false), 'a.tar (3).gz');
      expect(numberedName('Show.2024', 2, isDirectory: true), 'Show.2024 (2)');
      expect(numberedName('README', 2, isDirectory: false), 'README (2)');
    });
  });
}
