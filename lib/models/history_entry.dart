import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../services/path_safety.dart';

/// Coarse kind for visual styling and grouping in the history list. The current
/// app only emits [aiOrganize] entries; other kinds are placeholders that
/// downstream features will populate.
enum HistoryKind {
  aiOrganize,
  manualRename,
  metadataRefresh,
  batchImport;

  String get id => switch (this) {
        HistoryKind.aiOrganize => 'ai_organize',
        HistoryKind.manualRename => 'manual_rename',
        HistoryKind.metadataRefresh => 'metadata_refresh',
        HistoryKind.batchImport => 'batch_import',
      };

  static HistoryKind fromId(String? id) => switch (id) {
        'manual_rename' => HistoryKind.manualRename,
        'metadata_refresh' => HistoryKind.metadataRefresh,
        'batch_import' => HistoryKind.batchImport,
        _ => HistoryKind.aiOrganize,
      };
}

/// One row in the operation history: enough metadata to render the card and,
/// if [manifestPath] points at a valid file, drive undo.
class HistoryEntry {
  /// Absolute path to the JSON manifest backing this entry.
  final String manifestPath;
  final HistoryKind kind;
  final DateTime createdAt;
  final String baseDir;

  /// Total file ops the operation involved (moves + renames; ≥ moves.length).
  final int itemCount;
  final int moveCount;
  final int renameCount;
  final int totalBytes;
  final List<Map<String, String>> moves;

  /// Whether undo is still possible — i.e. the manifest has moves to reverse.
  bool get canUndo => moves.isNotEmpty;

  const HistoryEntry({
    required this.manifestPath,
    required this.kind,
    required this.createdAt,
    required this.baseDir,
    required this.itemCount,
    required this.moveCount,
    required this.renameCount,
    required this.totalBytes,
    required this.moves,
  });

  /// Returns a copy with [moves] replaced (counts left untouched — callers
  /// rendering the card should treat them as the original op size).
  HistoryEntry copyWithMoves(List<Map<String, String>> newMoves) => HistoryEntry(
        manifestPath: manifestPath,
        kind: kind,
        createdAt: createdAt,
        baseDir: baseDir,
        itemCount: itemCount,
        moveCount: moveCount,
        renameCount: renameCount,
        totalBytes: totalBytes,
        moves: newMoves,
      );

  factory HistoryEntry.fromJson(String path, Map<String, dynamic> json) {
    final movesRaw = (json['moves'] as List?) ?? const [];
    final moves = movesRaw
        .whereType<Map>()
        .map((m) => {
              'from': (m['from'] as String?) ?? '',
              'to': (m['to'] as String?) ?? '',
            })
        .where((m) => m['from']!.isNotEmpty && m['to']!.isNotEmpty)
        .toList();

    // Back-compat: derive counts from the moves list if the manifest predates
    // the enriched format.
    final renamesFromMoves =
        moves.where((m) => p.basename(m['from']!) != p.basename(m['to']!)).length;
    final movesFromMoves = moves.length - renamesFromMoves;

    return HistoryEntry(
      manifestPath: path,
      kind: HistoryKind.fromId(json['kind'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      baseDir: (json['baseDir'] as String?) ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? moves.length,
      moveCount: (json['moveCount'] as num?)?.toInt() ?? movesFromMoves,
      renameCount: (json['renameCount'] as num?)?.toInt() ?? renamesFromMoves,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      moves: moves,
    );
  }

  static Map<String, dynamic> buildManifest({
    required HistoryKind kind,
    required DateTime createdAt,
    required String baseDir,
    required int itemCount,
    required int moveCount,
    required int renameCount,
    required int totalBytes,
    required List<Map<String, String>> moves,
  }) =>
      {
        'kind': kind.id,
        'createdAt': createdAt.toIso8601String(),
        'baseDir': baseDir,
        'itemCount': itemCount,
        'moveCount': moveCount,
        'renameCount': renameCount,
        'totalBytes': totalBytes,
        'moves': moves,
      };
}

/// Outcome of reversing a recorded operation. [remaining] is the subset of
/// [HistoryEntry.moves] that weren't reversed (either because they failed or
/// because they were skipped); the caller can rewrite the manifest with this
/// list so the next undo retries only the still-broken moves.
class UndoResult {
  final int succeeded;
  final List<String> failures;
  final List<Map<String, String>> remaining;
  const UndoResult({
    required this.succeeded,
    required this.failures,
    required this.remaining,
  });
  bool get hasFailures => failures.isNotEmpty;
}

/// Reverses a recorded operation by renaming each target back to its original
/// source path. Treats a move whose source already exists at `from` as
/// already-undone (counts as success). Rejects any move whose paths escape
/// [HistoryEntry.baseDir] — defense in depth against tampered manifests.
Future<UndoResult> undoFromManifest(
  HistoryEntry entry, {
  FileSystem fs = const LocalFileSystem(),
}) async {
  var succeeded = 0;
  final failures = <String>[];
  final remaining = <Map<String, String>>[];

  // Track which moves to keep in the manifest. We iterate in reverse (so
  // newly-created subfolders are emptied before parents) but `remaining` is
  // returned in the original order to keep the manifest stable.
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

    if (!PathSafety.isWithin(entry.baseDir, from) ||
        !PathSafety.isWithin(entry.baseDir, to)) {
      failures.add('escapes base: $from');
      keptIndices.add(i);
      continue;
    }

    try {
      // If the user manually moved the file back already, count as undone.
      if (await fs.file(from).exists() || await fs.directory(from).exists()) {
        succeeded++;
        continue;
      }
      final file = fs.file(to);
      if (!await file.exists()) {
        failures.add('missing $to');
        keptIndices.add(i);
        continue;
      }
      await fs.directory(p.dirname(from)).create(recursive: true);
      await file.rename(from);
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
