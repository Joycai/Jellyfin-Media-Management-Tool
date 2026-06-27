import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/history_entry.dart';

/// Stores and exposes the operation history (one manifest file per operation in
/// `<app-support>/undo/`). Entries older than [retentionDays] are pruned on
/// load so the 7-day promise in the UI is real.
class HistoryService extends ChangeNotifier {
  static const int retentionDays = 7;

  List<HistoryEntry> _entries = [];
  bool _loaded = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);
  bool get loaded => _loaded;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'undo'));
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

    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final entry = HistoryEntry.fromJson(f.path, json);
        if (entry.createdAt.isBefore(cutoff)) {
          stale.add(f);
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
    final file = File(p.join(dir.path, 'op-${createdAt.millisecondsSinceEpoch}.json'));
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

  /// Reverses [entry] and removes its manifest on success.
  Future<UndoResult> undo(HistoryEntry entry) async {
    final result = await undoFromManifest(entry);
    if (!result.hasFailures) {
      try {
        await File(entry.manifestPath).delete();
      } catch (_) {}
      _entries = _entries.where((e) => e.manifestPath != entry.manifestPath).toList();
      notifyListeners();
    } else {
      // Partial: keep the manifest in place so the user can retry.
      await refresh();
    }
    return result;
  }
}
