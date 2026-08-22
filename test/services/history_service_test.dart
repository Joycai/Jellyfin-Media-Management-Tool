import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/history_entry.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';

import '../helpers/fs.dart';

void main() {
  late FileSystem fs;
  late HistoryService svc;
  const baseDir = '/work';
  const undoDir = '/undo';

  setUp(() {
    fs = newMemoryFs();
    fs.directory(undoDir).createSync(recursive: true);
    svc = HistoryService(fs: fs, undoDir: undoDir);
  });

  Future<HistoryEntry> seedManifest(List<List<String>> moves) async {
    // Create the `to` files so undo can move them back.
    for (final m in moves) {
      seedFile(fs, m[1], contents: 'x');
    }
    return svc.record(
      kind: HistoryKind.aiOrganize,
      baseDir: baseDir,
      itemCount: moves.length,
      moveCount: moves.length,
      renameCount: 0,
      totalBytes: moves.length,
      moves: moves.map((m) => {'from': m[0], 'to': m[1]}).toList(),
    );
  }

  group('HistoryService.undo — full success', () {
    test('reverses every move, deletes manifest, drops the entry', () async {
      final entry = await seedManifest([
        ['/work/a.mkv', '/work/Movies/A/a.mkv'],
        ['/work/b.mkv', '/work/Movies/B/b.mkv'],
      ]);
      expect(svc.entries.length, 1);

      final result = await svc.undo(entry);

      expect(result.succeeded, 2);
      expect(result.failures, isEmpty);
      expect(result.remaining, isEmpty);
      expect(svc.entries, isEmpty);
      expect(fs.file(entry.manifestPath).existsSync(), isFalse);
      expect(fs.file('/work/a.mkv').existsSync(), isTrue);
      expect(fs.file('/work/b.mkv').existsSync(), isTrue);
      expect(fs.file('/work/Movies/A/a.mkv').existsSync(), isFalse);
    });
  });

  group('HistoryService.undo — partial', () {
    test(
      'rewrites manifest with only unrecovered moves; retry finishes',
      () async {
        final entry = await seedManifest([
          ['/work/a.mkv', '/work/Movies/A/a.mkv'],
          ['/work/b.mkv', '/work/Movies/B/b.mkv'],
          ['/work/c.mkv', '/work/Movies/C/c.mkv'],
        ]);
        // Sabotage: delete c's "to" file so undo reports "missing" on c only.
        fs.file('/work/Movies/C/c.mkv').deleteSync();

        final first = await svc.undo(entry);

        expect(first.succeeded, 2);
        expect(first.failures, hasLength(1));
        expect(first.failures.single, contains('missing'));
        expect(first.remaining, hasLength(1));
        expect(first.remaining.single['from'], '/work/c.mkv');

        // Manifest still on disk, rewritten with only c.
        final reread =
            jsonDecode(fs.file(entry.manifestPath).readAsStringSync())
                as Map<String, dynamic>;
        expect((reread['moves'] as List).length, 1);

        // In-memory entry reflects the rewrite.
        expect(svc.entries, hasLength(1));
        expect(svc.entries.single.moves, hasLength(1));
        expect(svc.entries.single.moves.single['from'], '/work/c.mkv');

        // Repair c and retry: the second undo should clear everything.
        seedFile(fs, '/work/Movies/C/c.mkv');
        final second = await svc.undo(svc.entries.single);
        expect(second.succeeded, 1);
        expect(second.remaining, isEmpty);
        expect(svc.entries, isEmpty);
      },
    );
  });

  group('HistoryService.undo — already-undone moves', () {
    test('treats pre-existing `from` as success, not failure', () async {
      final entry = await seedManifest([
        ['/work/a.mkv', '/work/Movies/A/a.mkv'],
      ]);
      // Simulate the user having manually moved the file back already.
      seedFile(fs, '/work/a.mkv', contents: 'restored');

      final result = await svc.undo(entry);

      expect(result.succeeded, 1);
      expect(result.failures, isEmpty);
      expect(result.remaining, isEmpty);
      // Original is preserved (not overwritten by the rename).
      expect(fs.file('/work/a.mkv').readAsStringSync(), 'restored');
      expect(svc.entries, isEmpty);
    });
  });

  group('HistoryService.recordScrape', () {
    test('does not record an entry when nothing is reversible', () async {
      final entry = await svc.recordScrape(
        baseDir: baseDir,
        created: const [],
        restored: const {},
      );

      expect(entry, isNull);
      expect(svc.entries, isEmpty);
    });

    test('deletes created files and restores replaced ones', () async {
      seedFile(fs, '/work/SPSF-43.nfo', contents: '<movie>new</movie>');
      seedFile(fs, '/work/poster.jpg', contents: 'jpeg');
      seedFile(fs, '/work/extrafanart/backdrop-1.jpg', contents: 'jpeg');
      seedFile(fs, '$undoDir/blobs/op-1/a.nfo', contents: '<movie>old</movie>');
      seedFile(fs, '/work/a.nfo', contents: '<movie>replaced</movie>');

      final entry = (await svc.recordScrape(
        baseDir: baseDir,
        created: const [
          '/work/SPSF-43.nfo',
          '/work/poster.jpg',
          '/work/extrafanart/backdrop-1.jpg',
        ],
        restored: const {'/work/a.nfo': '$undoDir/blobs/op-1/a.nfo'},
        backupDir: '$undoDir/blobs/op-1',
      ))!;
      expect(entry.canUndo, isTrue);

      final result = await svc.undo(entry);

      expect(result.failures, isEmpty);
      expect(result.succeeded, 4);
      expect(fs.file('/work/SPSF-43.nfo').existsSync(), isFalse);
      expect(fs.file('/work/poster.jpg').existsSync(), isFalse);
      expect(fs.file('/work/extrafanart/backdrop-1.jpg').existsSync(), isFalse);
      // The replaced file is back to its pre-scrape content.
      expect(fs.file('/work/a.nfo').readAsStringSync(), '<movie>old</movie>');
      // Manifest and its backups are both gone.
      expect(fs.file(entry.manifestPath).existsSync(), isFalse);
      expect(fs.directory('$undoDir/blobs/op-1').existsSync(), isFalse);
      expect(svc.entries, isEmpty);
    });

    test('a created file the user already deleted counts as undone', () async {
      final entry = (await svc.recordScrape(
        baseDir: baseDir,
        created: const ['/work/gone.nfo'],
        restored: const {},
      ))!;

      final result = await svc.undo(entry);

      expect(result.succeeded, 1);
      expect(result.failures, isEmpty);
      expect(svc.entries, isEmpty);
    });

    test('a missing backup is reported and kept for a retry', () async {
      seedFile(fs, '/work/a.nfo', contents: 'current');
      final entry = (await svc.recordScrape(
        baseDir: baseDir,
        created: const [],
        restored: const {'/work/a.nfo': '$undoDir/blobs/op-2/a.nfo'},
      ))!;

      final result = await svc.undo(entry);

      expect(result.succeeded, 0);
      expect(result.failures.single, contains('missing backup'));
      expect(result.remainingRestored, hasLength(1));
      // Entry survives so the user can retry once the backup is back.
      expect(svc.entries, hasLength(1));
      expect(fs.file('/work/a.nfo').readAsStringSync(), 'current');
    });
  });

  group('HistoryService.refresh — round trip', () {
    test('re-reads a manifest it wrote, scrape keys included', () async {
      await svc.recordScrape(
        baseDir: baseDir,
        created: const ['/work/a.nfo'],
        restored: const {'/work/b.nfo': '$undoDir/blobs/op-1/b.nfo'},
        backupDir: '$undoDir/blobs/op-1',
      );

      // A second service reads from disk with nothing in memory, which is what
      // a fresh app launch does.
      final reopened = HistoryService(fs: fs, undoDir: undoDir);
      await reopened.refresh();

      expect(reopened.entries, hasLength(1));
      final entry = reopened.entries.single;
      expect(entry.kind, HistoryKind.metadataRefresh);
      expect(entry.created, ['/work/a.nfo']);
      expect(entry.restored, {'/work/b.nfo': '$undoDir/blobs/op-1/b.nfo'});
      expect(entry.backupDir, '$undoDir/blobs/op-1');
      expect(entry.canUndo, isTrue);
    });

    test('an organize manifest still round-trips unchanged', () async {
      final written = await seedManifest([
        ['/work/a.mkv', '/work/Movies/A/a.mkv'],
      ]);

      final reopened = HistoryService(fs: fs, undoDir: undoDir);
      await reopened.refresh();

      expect(reopened.entries, hasLength(1));
      expect(reopened.entries.single.moves, written.moves);
      // The scrape-only keys are omitted when empty, so an older reader sees
      // exactly the document it always did.
      final raw =
          jsonDecode(fs.file(written.manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      expect(raw.containsKey('created'), isFalse);
      expect(raw.containsKey('restored'), isFalse);
      expect(raw.containsKey('backupDir'), isFalse);
    });
  });

  group('HistoryService.refresh — retention', () {
    test('prunes backup folders past the window, keeps fresh ones', () async {
      final old = seedFile(fs, '$undoDir/blobs/op-old/a.nfo', contents: 'x');
      seedFile(fs, '$undoDir/blobs/op-new/a.nfo', contents: 'x');
      old.setLastModifiedSync(
        DateTime.now().subtract(
          const Duration(days: HistoryService.retentionDays + 1),
        ),
      );

      await svc.refresh();

      // Otherwise the 7-day promise would hold for manifests while the copies
      // they reference grew without bound.
      expect(fs.directory('$undoDir/blobs/op-old').existsSync(), isFalse);
      expect(fs.directory('$undoDir/blobs/op-new').existsSync(), isTrue);
    });

    test('a manifest with a corrupt date survives on its file mtime', () async {
      final entry = await seedManifest([
        ['/work/a.mkv', '/work/Movies/A/a.mkv'],
      ]);
      final file = fs.file(entry.manifestPath);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      json['createdAt'] = 'not-a-date';
      file.writeAsStringSync(jsonEncode(json));

      await svc.refresh();

      // A mangled date field alone must not destroy the undo — the file is
      // fresh, so the entry stays until its real age passes the window.
      expect(svc.entries, hasLength(1));
      expect(file.existsSync(), isTrue);
      expect(svc.entries.single.canUndo, isTrue);
    });

    test('a corrupt-date manifest still ages out by file mtime', () async {
      final entry = await seedManifest([
        ['/work/a.mkv', '/work/Movies/A/a.mkv'],
      ]);
      final file = fs.file(entry.manifestPath);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      json['createdAt'] = 'not-a-date';
      file.writeAsStringSync(jsonEncode(json));
      file.setLastModifiedSync(
        DateTime.now().subtract(
          const Duration(days: HistoryService.retentionDays + 1),
        ),
      );

      await svc.refresh();

      expect(svc.entries, isEmpty);
      expect(file.existsSync(), isFalse);
    });
  });

  group('HistoryService.undo — defense in depth', () {
    test('refuses to delete a created file outside baseDir', () async {
      seedFile(fs, '/etc/passwd', contents: 'root');
      final entry = (await svc.recordScrape(
        baseDir: baseDir,
        created: const ['/etc/passwd'],
        restored: const {},
      ))!;

      final result = await svc.undo(entry);

      expect(result.succeeded, 0);
      expect(result.failures.single, contains('escapes'));
      expect(fs.file('/etc/passwd').existsSync(), isTrue);
    });

    test('refuses a backup sourced from outside the undo directory', () async {
      // A tampered manifest naming an arbitrary file as the "backup" would
      // otherwise copy its contents straight into the user's library.
      seedFile(fs, '/elsewhere/evil', contents: 'payload');
      seedFile(fs, '/work/a.nfo', contents: 'current');
      final entry = (await svc.recordScrape(
        baseDir: baseDir,
        created: const [],
        restored: const {'/work/a.nfo': '/elsewhere/evil'},
      ))!;

      final result = await svc.undo(entry);

      expect(result.succeeded, 0);
      expect(result.failures.single, contains('escapes'));
      expect(fs.file('/work/a.nfo').readAsStringSync(), 'current');
    });

    test('refuses to reverse a move whose paths escape baseDir', () async {
      final entry = await seedManifest([
        ['/etc/passwd', '/work/Movies/A/a.mkv'],
      ]);

      final result = await svc.undo(entry);

      expect(result.succeeded, 0);
      expect(result.failures, hasLength(1));
      expect(result.failures.single, contains('escapes'));
      expect(result.remaining, hasLength(1));
      // /etc/passwd untouched.
      expect(fs.file('/etc/passwd').existsSync(), isFalse);
    });
  });
}
