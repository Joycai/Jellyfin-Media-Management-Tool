import 'package:path/path.dart' as p;

/// Coarse kind for visual styling and grouping in the history list.
/// [aiOrganize] comes from the organize pipeline and [metadataRefresh] from a
/// scrape commit; the remaining two are placeholders.
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

  /// `{'from': …, 'to': …}` per relocated file. Undo renames back.
  final List<Map<String, String>> moves;

  /// Files this operation brought into existence (a written NFO, a downloaded
  /// poster). Undo deletes exactly these — nothing else in the folder.
  final List<String> created;

  /// Files this operation overwrote, mapped to the copy of the original. Undo
  /// copies the backup back over the current content.
  ///
  /// This is the half of undo that moves alone cannot express: replacing an
  /// NFO's *content* is not reversible by relocating a file, which is why
  /// `MetadataWriter.backup` genuinely copies where the organize pipeline's
  /// `backup` flag only gates whether a manifest is written at all.
  final Map<String, String> restored;

  /// Directory holding the copies named in [restored]. Removed together with
  /// the manifest so backups can't outlive the entry that explains them.
  final String? backupDir;

  /// Whether undo is still possible — i.e. the manifest still describes work
  /// that can be reversed.
  bool get canUndo =>
      moves.isNotEmpty || created.isNotEmpty || restored.isNotEmpty;

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
    this.created = const [],
    this.restored = const {},
    this.backupDir,
  });

  /// Returns a copy with the reversible work replaced by whatever is left after
  /// a partial undo. Counts are left untouched — callers rendering the card
  /// should treat them as the original op size.
  HistoryEntry copyWithRemaining({
    List<Map<String, String>>? moves,
    List<String>? created,
    Map<String, String>? restored,
  }) => HistoryEntry(
    manifestPath: manifestPath,
    kind: kind,
    createdAt: createdAt,
    baseDir: baseDir,
    itemCount: itemCount,
    moveCount: moveCount,
    renameCount: renameCount,
    totalBytes: totalBytes,
    moves: moves ?? this.moves,
    created: created ?? this.created,
    restored: restored ?? this.restored,
    backupDir: backupDir,
  );

  /// [fallbackCreatedAt] stands in when the manifest's own date is missing or
  /// unparseable. Callers that can, pass the file's mtime so the entry ages
  /// out on its real age; the default (epoch) marks it immediately stale.
  factory HistoryEntry.fromJson(
    String path,
    Map<String, dynamic> json, {
    DateTime? fallbackCreatedAt,
  }) {
    final movesRaw = (json['moves'] as List?) ?? const [];
    final moves = movesRaw
        .whereType<Map>()
        .map(
          (m) => {
            'from': (m['from'] as String?) ?? '',
            'to': (m['to'] as String?) ?? '',
          },
        )
        .where((m) => m['from']!.isNotEmpty && m['to']!.isNotEmpty)
        .toList();

    // Back-compat: derive counts from the moves list if the manifest predates
    // the enriched format.
    final renamesFromMoves = moves
        .where((m) => p.basename(m['from']!) != p.basename(m['to']!))
        .length;
    final movesFromMoves = moves.length - renamesFromMoves;

    return HistoryEntry(
      manifestPath: path,
      kind: HistoryKind.fromId(json['kind'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          fallbackCreatedAt ??
          DateTime.fromMillisecondsSinceEpoch(0),
      baseDir: (json['baseDir'] as String?) ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? moves.length,
      moveCount: (json['moveCount'] as num?)?.toInt() ?? movesFromMoves,
      renameCount: (json['renameCount'] as num?)?.toInt() ?? renamesFromMoves,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      moves: moves,
      created: [
        for (final c in (json['created'] as List?) ?? const [])
          if (c is String && c.isNotEmpty) c,
      ],
      restored: {
        for (final e in ((json['restored'] as Map?) ?? const {}).entries)
          if (e.value is String && (e.value as String).isNotEmpty)
            e.key.toString(): e.value as String,
      },
      backupDir: (json['backupDir'] as String?)?.trim(),
    );
  }

  /// Builds the on-disk manifest.
  ///
  /// The scrape-only keys are omitted when empty so an organize manifest is
  /// byte-for-byte what it always was — a reader on an older build sees the
  /// same document it expects.
  static Map<String, dynamic> buildManifest({
    required HistoryKind kind,
    required DateTime createdAt,
    required String baseDir,
    required int itemCount,
    required int moveCount,
    required int renameCount,
    required int totalBytes,
    required List<Map<String, String>> moves,
    List<String> created = const [],
    Map<String, String> restored = const {},
    String? backupDir,
  }) => {
    'kind': kind.id,
    'createdAt': createdAt.toIso8601String(),
    'baseDir': baseDir,
    'itemCount': itemCount,
    'moveCount': moveCount,
    'renameCount': renameCount,
    'totalBytes': totalBytes,
    'moves': moves,
    if (created.isNotEmpty) 'created': created,
    if (restored.isNotEmpty) 'restored': restored,
    if (backupDir != null && backupDir.isNotEmpty) 'backupDir': backupDir,
  };
}

/// Outcome of reversing a recorded operation.
///
/// The three `remaining*` lists are the work that was *not* undone (it failed,
/// or it was refused); the service rewrites the manifest with exactly them, so
/// a retry picks up where this left off instead of replaying what already
/// worked.
class UndoResult {
  final int succeeded;
  final List<String> failures;

  /// Moves still to reverse — the subset of [HistoryEntry.moves].
  final List<Map<String, String>> remaining;

  /// Created files still to delete.
  final List<String> remainingCreated;

  /// Overwritten files still to restore from their backup.
  final Map<String, String> remainingRestored;

  const UndoResult({
    required this.succeeded,
    required this.failures,
    required this.remaining,
    this.remainingCreated = const [],
    this.remainingRestored = const {},
  });

  bool get hasFailures => failures.isNotEmpty;

  /// True when there is nothing left to reverse, so the manifest can go.
  bool get isComplete =>
      remaining.isEmpty &&
      remainingCreated.isEmpty &&
      remainingRestored.isEmpty;
}
