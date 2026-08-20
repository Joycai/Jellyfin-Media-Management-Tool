import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/history_entry.dart';
import 'path_safety.dart';

/// Stores and exposes the operation history (one manifest file per operation in
/// `<app-support>/undo/`). Entries older than [retentionDays] are pruned on
/// load so the 7-day promise in the UI is real.
class HistoryService extends ChangeNotifier {
  static const int retentionDays = 7;

  final FileSystem _fs;
  final String? _explicitUndoDir;

  /// [fs] and [undoDir] are injected in tests; production callers leave them
  /// at the defaults (real local FS + `<app-support>/undo/`).
  HistoryService({FileSystem fs = const LocalFileSystem(), String? undoDir})
    : _fs = fs,
      _explicitUndoDir = undoDir;

  List<HistoryEntry> _entries = [];
  bool _loaded = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);
  bool get loaded => _loaded;

  /// Backup copies live under here, one directory per operation.
  static const String blobsDirName = 'blobs';

  Future<Directory> _dir() async {
    final path =
        _explicitUndoDir ??
        _fs.path.join((await getApplicationSupportDirectory()).path, 'undo');
    final dir = _fs.directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Re-reads the manifest directory. Cheap enough to call when the History
  /// screen opens and after each apply / undo.
  Future<void> refresh() async {
    final dir = await _dir();
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    final loaded = <HistoryEntry>[];
    final stale = <File>[];

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final entry = HistoryEntry.fromJson(entity.path, json);
        if (entry.createdAt.isBefore(cutoff)) {
          stale.add(entity);
        } else {
          loaded.add(entry);
        }
      } catch (_) {
        // Best-effort: ignore manifests we can't parse.
      }
    }

    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _entries = loaded;
    _loaded = true;
    notifyListeners();

    // Best-effort cleanup of old manifests (fire and forget).
    for (final f in stale) {
      try {
        await f.delete();
      } catch (_) {}
    }
    await _pruneBlobs(dir, cutoff);
  }

  /// Drops backup directories past the retention window.
  ///
  /// Keyed on the directory's own timestamp rather than on a surviving
  /// manifest, so a blob folder orphaned by a crash between the write and the
  /// manifest is collected too. Without this the 7-day promise would hold for
  /// manifests while the copies they reference grew without bound.
  Future<void> _pruneBlobs(Directory undoDir, DateTime cutoff) async {
    final blobs = _fs.directory(_fs.path.join(undoDir.path, blobsDirName));
    if (!await blobs.exists()) return;
    await for (final entity in blobs.list()) {
      if (entity is! Directory) continue;
      try {
        if ((await _newestWrite(entity)).isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// When [dir] was last written to.
  ///
  /// Taken from the newest file inside rather than the directory's own stat:
  /// a backup folder is written once and never touched again, but directory
  /// timestamps are the first thing a sync client or an archive extraction
  /// rewrites, and an aged-out folder that looks fresh would never be pruned.
  /// Falls back to the directory's own stat when it holds no files.
  Future<DateTime> _newestWrite(Directory dir) async {
    DateTime? newest;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final modified = (await entity.stat()).modified;
      if (newest == null || modified.isAfter(newest)) newest = modified;
    }
    return newest ?? (await dir.stat()).modified;
  }

  /// Writes a new manifest. Returns the resulting [HistoryEntry].
  Future<HistoryEntry> record({
    required HistoryKind kind,
    required String baseDir,
    required int itemCount,
    required int moveCount,
    required int renameCount,
    required int totalBytes,
    required List<Map<String, String>> moves,
  }) async {
    final dir = await _dir();
    final createdAt = DateTime.now();
    final file = _fs.file(
      _fs.path.join(dir.path, 'op-${createdAt.millisecondsSinceEpoch}.json'),
    );
    final manifest = HistoryEntry.buildManifest(
      kind: kind,
      createdAt: createdAt,
      baseDir: baseDir,
      itemCount: itemCount,
      moveCount: moveCount,
      renameCount: renameCount,
      totalBytes: totalBytes,
      moves: moves,
    );
    await file.writeAsString(jsonEncode(manifest));

    final entry = HistoryEntry.fromJson(file.path, manifest);
    _entries = [entry, ..._entries];
    notifyListeners();
    return entry;
  }

  /// Writes a manifest for one scrape commit.
  ///
  /// Separate from [record] rather than a pile of defaulted arguments on it:
  /// a scrape moves nothing, so every move-shaped count would be zero and the
  /// call site would read as if it were saying something it isn't.
  ///
  /// [created] and [restored] come straight off `MetadataWriteResult`.
  Future<HistoryEntry?> recordScrape({
    required String baseDir,
    required List<String> created,
    required Map<String, String> restored,
    String? backupDir,
  }) async {
    // Nothing reversible happened — an entry offering an undo that would do
    // nothing is worse than no entry.
    if (created.isEmpty && restored.isEmpty) return null;

    final dir = await _dir();
    final createdAt = DateTime.now();
    final file = _fs.file(
      _fs.path.join(dir.path, 'op-${createdAt.millisecondsSinceEpoch}.json'),
    );
    final manifest = HistoryEntry.buildManifest(
      kind: HistoryKind.metadataRefresh,
      createdAt: createdAt,
      baseDir: baseDir,
      itemCount: created.length + restored.length,
      moveCount: 0,
      renameCount: 0,
      totalBytes: 0,
      moves: const [],
      created: created,
      restored: restored,
      backupDir: backupDir,
    );
    await file.writeAsString(jsonEncode(manifest));

    final entry = HistoryEntry.fromJson(file.path, manifest);
    _entries = [entry, ..._entries];
    notifyListeners();
    return entry;
  }

  /// Reverses [entry]: moves back, created files deleted, overwritten files
  /// restored from their backup.
  ///
  /// On full success the manifest — and any backup directory it owns — is
  /// deleted. On partial success the manifest is **rewritten** with only the
  /// work that still needs reversing, so the user can retry and make further
  /// progress instead of replaying what already succeeded.
  Future<UndoResult> undo(HistoryEntry entry) async {
    final moves = await _reverseMoves(entry);
    final created = await _deleteCreated(entry);
    final restored = await _restoreBackups(entry);

    final result = UndoResult(
      succeeded: moves.succeeded + created.succeeded + restored.succeeded,
      failures: [...moves.failures, ...created.failures, ...restored.failures],
      remaining: moves.remaining,
      remainingCreated: created.remainingCreated,
      remainingRestored: restored.remainingRestored,
    );

    if (result.isComplete) {
      try {
        await _fs.file(entry.manifestPath).delete();
      } catch (_) {}
      await _deleteBackupDir(entry);
      _entries = _entries
          .where((e) => e.manifestPath != entry.manifestPath)
          .toList();
      notifyListeners();
      return result;
    }

    // Partial: rewrite the manifest with only the unrecovered work and update
    // the in-memory entry to match.
    final rewritten = HistoryEntry.buildManifest(
      kind: entry.kind,
      createdAt: entry.createdAt,
      baseDir: entry.baseDir,
      itemCount: entry.itemCount,
      moveCount: entry.moveCount,
      renameCount: entry.renameCount,
      totalBytes: entry.totalBytes,
      moves: result.remaining,
      created: result.remainingCreated,
      restored: result.remainingRestored,
      backupDir: entry.backupDir,
    );
    try {
      await _fs.file(entry.manifestPath).writeAsString(jsonEncode(rewritten));
    } catch (_) {
      // If we can't rewrite, fall back to a full refresh so the UI matches disk.
      await refresh();
      return result;
    }
    _entries = _entries
        .map(
          (e) => e.manifestPath == entry.manifestPath
              ? e.copyWithRemaining(
                  moves: result.remaining,
                  created: result.remainingCreated,
                  restored: result.remainingRestored,
                )
              : e,
        )
        .toList();
    notifyListeners();
    return result;
  }

  /// Deletes the files the operation created, newest path first so a file
  /// inside `extrafanart/` goes before anything that might sit above it.
  ///
  /// A file that is already gone counts as success — the user deleting it by
  /// hand achieved the same end. Directories the write created are left
  /// behind, matching how move-undo behaves.
  Future<UndoResult> _deleteCreated(HistoryEntry entry) async {
    var succeeded = 0;
    final failures = <String>[];
    final remaining = <String>[];

    for (final path in entry.created.reversed) {
      if (!PathSafety.isWithin(entry.baseDir, path, context: _fs.path)) {
        failures.add('escapes base: $path');
        remaining.add(path);
        continue;
      }
      try {
        final file = _fs.file(path);
        if (await file.exists()) await file.delete();
        succeeded++;
      } catch (e) {
        failures.add('$path: $e');
        remaining.add(path);
      }
    }

    return UndoResult(
      succeeded: succeeded,
      failures: failures,
      remaining: const [],
      // Original order, so a rewritten manifest stays stable.
      remainingCreated: entry.created.where(remaining.contains).toList(),
    );
  }

  /// Copies each backup back over the file that replaced it.
  ///
  /// Both ends are checked: the destination must be inside the operation's
  /// `baseDir`, and the source must be inside the undo directory. The second
  /// check is the one that matters — without it a tampered manifest could name
  /// any file on the system as a "backup" and have its contents copied into
  /// the user's library.
  Future<UndoResult> _restoreBackups(HistoryEntry entry) async {
    if (entry.restored.isEmpty) {
      return const UndoResult(succeeded: 0, failures: [], remaining: []);
    }
    final undoDir = (await _dir()).path;

    var succeeded = 0;
    final failures = <String>[];
    final remaining = <String, String>{};

    for (final e in entry.restored.entries) {
      final target = e.key;
      final backup = e.value;
      if (!PathSafety.isWithin(entry.baseDir, target, context: _fs.path) ||
          !PathSafety.isWithin(undoDir, backup, context: _fs.path)) {
        failures.add('escapes base: $target');
        remaining[target] = backup;
        continue;
      }
      try {
        final source = _fs.file(backup);
        if (!await source.exists()) {
          failures.add('missing backup for $target');
          remaining[target] = backup;
          continue;
        }
        await _fs.directory(_fs.path.dirname(target)).create(recursive: true);
        await source.copy(target);
        succeeded++;
      } catch (err) {
        failures.add('$backup → $target: $err');
        remaining[target] = backup;
      }
    }

    return UndoResult(
      succeeded: succeeded,
      failures: failures,
      remaining: const [],
      remainingRestored: remaining,
    );
  }

  Future<void> _deleteBackupDir(HistoryEntry entry) async {
    final path = entry.backupDir;
    if (path == null || path.isEmpty) return;
    try {
      final undoDir = (await _dir()).path;
      if (!PathSafety.isWithin(undoDir, path, context: _fs.path)) return;
      final dir = _fs.directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Reverses each move in [entry] by renaming target → source. A pre-existing
  /// `from` (file already restored manually) counts as success; a move whose
  /// paths escape `entry.baseDir` is refused — defense in depth against
  /// tampered manifests.
  Future<UndoResult> _reverseMoves(HistoryEntry entry) async {
    var succeeded = 0;
    final failures = <String>[];
    final remaining = <Map<String, String>>[];

    // Iterate in reverse so newly-created subfolders are emptied before parents.
    // `remaining` is returned in original order to keep the manifest stable.
    final keptIndices = <int>{};
    final reversedIndexed = entry.moves
        .asMap()
        .entries
        .toList()
        .reversed
        .toList(growable: false);

    for (final indexed in reversedIndexed) {
      final i = indexed.key;
      final move = indexed.value;
      final from = move['from']!;
      final to = move['to']!;

      if (!PathSafety.isWithin(entry.baseDir, from, context: _fs.path) ||
          !PathSafety.isWithin(entry.baseDir, to, context: _fs.path)) {
        failures.add('escapes base: $from');
        keptIndices.add(i);
        continue;
      }

      try {
        // If the user manually moved the file back already, count as undone.
        if (await _fs.file(from).exists() ||
            await _fs.directory(from).exists()) {
          succeeded++;
          continue;
        }
        final file = _fs.file(to);
        if (!await file.exists()) {
          failures.add('missing $to');
          keptIndices.add(i);
          continue;
        }
        await _fs.directory(_fs.path.dirname(from)).create(recursive: true);
        await _moveFile(file, from);
        succeeded++;
      } catch (e) {
        failures.add('$to → $from: $e');
        keptIndices.add(i);
      }
    }

    for (var i = 0; i < entry.moves.length; i++) {
      if (keptIndices.contains(i)) remaining.add(entry.moves[i]);
    }

    return UndoResult(
      succeeded: succeeded,
      failures: failures,
      remaining: remaining,
    );
  }

  Future<void> _moveFile(File source, String targetPath) async {
    try {
      await source.rename(targetPath);
    } on FileSystemException {
      await source.copy(targetPath);
      try {
        await source.delete();
      } catch (_) {
        try {
          await _fs.file(targetPath).delete();
        } catch (_) {}
        rethrow;
      }
    }
  }
}
