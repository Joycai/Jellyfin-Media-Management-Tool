import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/history_entry.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/transfer/file_transfer.dart';
import 'package:jellyfin_media_management_tool/services/transfer/transfer_controller.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fs.dart';

void main() {
  late FileSystem fs;
  late HistoryService history;

  setUp(() {
    fs = newMemoryFs();
    fs.directory('/work/dest').createSync(recursive: true);
    fs.directory('/undo').createSync();
    history = HistoryService(fs: fs, undoDir: '/undo');
  });

  Future<TransferController> start(
    List<String> sources, {
    required TransferMode mode,
    HistoryService? withHistory,
  }) async {
    final plan = await planTransfer(
      sources: sources,
      destinationDir: '/work/dest',
      mode: mode,
      fs: fs,
    );
    final c = TransferController(
      plan: plan,
      policy: ConflictPolicy.keepBoth,
      history: withHistory,
      fs: fs,
    );
    await c.start();
    return c;
  }

  group('TransferController', () {
    test('runs to done with byte progress and a result', () async {
      seedFile(fs, '/work/a.mkv', contents: 'abc');
      final fractions = <double>[];

      final plan = await planTransfer(
        sources: ['/work/a.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );
      final c = TransferController(
        plan: plan,
        policy: ConflictPolicy.keepBoth,
        fs: fs,
      );
      c.addListener(() => fractions.add(c.fraction));
      await c.start();

      expect(c.status, TransferStatus.done);
      expect(c.bytesDone, 3);
      expect(c.bytesTotal, 3);
      expect(c.fraction, 1);
      expect(fractions.last, 1);
      expect(c.result!.succeeded, 1);
    });

    test('start is idempotent', () async {
      seedFile(fs, '/work/a.mkv', contents: 'abc');
      final c = await start(['/work/a.mkv'], mode: TransferMode.copy);

      await c.start();

      expect(fs.file('/work/dest/a (2).mkv').existsSync(), isFalse);
    });

    test(
      'a move writes a file_transfer manifest that undo can reverse',
      () async {
        seedFile(fs, '/work/Show/S01/e1.mkv', contents: '1');
        seedFile(fs, '/work/b.mkv', contents: 'b');

        final c = await start(
          ['/work/Show', '/work/b.mkv'],
          mode: TransferMode.move,
          withHistory: history,
        );

        expect(c.undoError, isNull);
        expect(c.undoUnavailable, isFalse);
        final entry = history.entries.single;
        expect(entry.kind, HistoryKind.fileTransfer);
        expect(entry.baseDir, '/work');
        expect(entry.itemCount, 2);
        expect(entry.moves, hasLength(2));

        final undo = await history.undo(entry);

        expect(undo.failures, isEmpty);
        expect(fs.file('/work/Show/S01/e1.mkv').readAsStringSync(), '1');
        expect(fs.file('/work/b.mkv').readAsStringSync(), 'b');
        expect(fs.file('/work/dest/b.mkv').existsSync(), isFalse);
      },
    );

    test(
      'a copy records the copies as created, and undo deletes them',
      () async {
        seedFile(fs, '/work/a.mkv', contents: 'a');

        await start(
          ['/work/a.mkv'],
          mode: TransferMode.copy,
          withHistory: history,
        );

        final entry = history.entries.single;
        expect(entry.created, ['/work/dest/a.mkv']);
        expect(entry.moves, isEmpty);

        await history.undo(entry);

        expect(fs.file('/work/dest/a.mkv').existsSync(), isFalse);
        expect(fs.file('/work/a.mkv').existsSync(), isTrue);
      },
    );

    test('an empty folder moves but says so: nothing to undo', () async {
      fs.directory('/work/Season 02').createSync();

      final c = await start(
        ['/work/Season 02'],
        mode: TransferMode.move,
        withHistory: history,
      );

      expect(c.status, TransferStatus.done);
      expect(c.result!.succeeded, 1);
      expect(fs.directory('/work/dest/Season 02').existsSync(), isTrue);
      expect(history.entries, isEmpty);
      expect(c.undoUnavailable, isTrue);
      expect(c.fraction, 1);
    });

    test('nothing transferred means no manifest', () async {
      final plan = await planTransfer(
        sources: ['/work/missing.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.copy,
        fs: fs,
      );
      final c = TransferController(
        plan: plan,
        policy: ConflictPolicy.keepBoth,
        history: history,
        fs: fs,
      );
      await c.start();

      expect(c.status, TransferStatus.done);
      expect(history.entries, isEmpty);
    });

    test('stop before start ends the batch without moving anything', () async {
      seedFile(fs, '/work/a.mkv', contents: 'a');
      final plan = await planTransfer(
        sources: ['/work/a.mkv'],
        destinationDir: '/work/dest',
        mode: TransferMode.move,
        fs: fs,
      );
      final c = TransferController(
        plan: plan,
        policy: ConflictPolicy.keepBoth,
        fs: fs,
      );

      c.stop();
      await c.start();

      expect(c.status, TransferStatus.stopped);
      expect(fs.file('/work/a.mkv').existsSync(), isTrue);
    });
  });

  group('commonRoot', () {
    test('is the deepest shared directory', () {
      expect(
        TransferController.commonRoot([
          '/work/a/x.mkv',
          '/work/b/c/y.mkv',
        ], context: p.posix),
        '/work',
      );
    });

    test('falls back to the filesystem root, never null, on one volume', () {
      expect(
        TransferController.commonRoot([
          '/movies/x.mkv',
          '/tv/y.mkv',
        ], context: p.posix),
        '/',
      );
    });

    test('is null across Windows drives', () {
      expect(
        TransferController.commonRoot([
          r'C:\a\x.mkv',
          r'D:\b\x.mkv',
        ], context: p.windows),
        isNull,
      );
      expect(
        TransferController.commonRoot([
          r'C:\a\x.mkv',
          r'C:\b\x.mkv',
        ], context: p.windows),
        r'C:\',
      );
    });
  });
}
