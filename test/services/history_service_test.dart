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
      moves: moves
          .map((m) => {'from': m[0], 'to': m[1]})
          .toList(),
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
    test('rewrites manifest with only unrecovered moves; retry finishes', () async {
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
      final reread = jsonDecode(fs.file(entry.manifestPath).readAsStringSync()) as Map<String, dynamic>;
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
    });
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

  group('HistoryService.undo — defense in depth', () {
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
