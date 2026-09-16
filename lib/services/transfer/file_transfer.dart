import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../path_safety.dart';

/// Whether the transfer leaves the source in place.
enum TransferMode { copy, move }

/// What to do with an item whose name is already taken in the destination.
///
/// There is deliberately no *overwrite*: the browser's other write paths
/// (`applyOrganizeAction`, undo) refuse to clobber, and a paste that silently
/// replaced a 40 GB remux with a sample file would be the one destructive
/// action in the app with no confirmation and no undo.
enum ConflictPolicy { skip, keepBoth }

/// Why an item was dropped from the plan before anything ran.
enum TransferRefusal {
  /// The source is gone (deleted or moved since it was copied).
  missing,

  /// The destination is the source folder itself or inside it — a move
  /// there is either a no-op or would swallow the folder into its own child.
  intoItself,

  /// A move whose destination is the folder the item already lives in.
  sameFolder,

  /// The source is a symbolic link, or a folder holding one. A link copied as
  /// its target silently duplicates another library; a link dropped from a
  /// cross-volume move is lost with nothing for undo to restore.
  link,

  /// The source could not be read (permissions, a vanished subfolder).
  unreadable,
}

/// One top-level entry of a transfer, with the target it will land on.
class TransferItem {
  final String source;
  final bool isDirectory;

  /// Bytes under [source] — the file's size, or the sum of the tree's files.
  final int bytes;

  /// `<destinationDir>/<name>`; rewritten by keep-both when the name is taken.
  String target;

  /// The planned [target] already existed when the plan was built.
  final bool conflict;

  TransferItem({
    required this.source,
    required this.isDirectory,
    required this.bytes,
    required this.target,
    required this.conflict,
  });
}

/// A source that will not be transferred, and why.
class RefusedItem {
  final String source;
  final TransferRefusal reason;
  const RefusedItem(this.source, this.reason);
}

/// A transfer, resolved and checked but not yet run.
///
/// Built by [planTransfer] so the UI can ask about [conflicts] before a byte
/// moves; [executeTransfer] then runs it under one [ConflictPolicy].
class TransferPlan {
  final String destinationDir;
  final TransferMode mode;
  final List<TransferItem> items;
  final List<RefusedItem> refused;

  const TransferPlan({
    required this.destinationDir,
    required this.mode,
    required this.items,
    required this.refused,
  });

  /// Items whose target already exists in the destination.
  List<TransferItem> get conflicts => items.where((i) => i.conflict).toList();

  int get totalBytes => items.fold(0, (sum, i) => sum + i.bytes);
  bool get isEmpty => items.isEmpty;
}

/// One failed item.
class TransferFailure {
  final String source;
  final String error;
  const TransferFailure(this.source, this.error);
}

/// What [executeTransfer] did.
class TransferResult {
  final int succeeded;
  final int failed;
  final int skipped;
  final int bytesDone;

  /// `{'from': …, 'to': …}` per *file* that moved — a moved directory is
  /// expanded to its files so `HistoryService` can reverse it file by file.
  final List<Map<String, String>> moves;

  /// Every file a copy brought into existence, for undo to delete.
  final List<String> created;
  final List<TransferFailure> failures;
  final bool stopped;

  const TransferResult({
    required this.succeeded,
    required this.failed,
    required this.skipped,
    required this.bytesDone,
    required this.moves,
    required this.created,
    required this.failures,
    required this.stopped,
  });

  bool get hasFailures => failed > 0;
}

const FileSystem _defaultFs = LocalFileSystem();

/// Resolves [sources] against [destinationDir] and sizes them, refusing what
/// cannot go: a missing source, a folder pasted into itself or a child of
/// itself, and a move into the folder the item already sits in.
///
/// Throws a [FileSystemException] when [destinationDir] is not a directory —
/// that is the caller's mistake, not an item's.
///
/// [fs] is injected in tests; paths go through `fs.path` so an in-memory POSIX
/// tree is not parsed with Windows rules on a Windows host.
Future<TransferPlan> planTransfer({
  required Iterable<String> sources,
  required String destinationDir,
  required TransferMode mode,
  FileSystem fs = _defaultFs,
}) async {
  final path = fs.path;
  final dest = path.normalize(path.absolute(destinationDir));
  if (!await fs.directory(dest).exists()) {
    throw FileSystemException('Destination is not a directory', dest);
  }

  final items = <TransferItem>[];
  final refused = <RefusedItem>[];
  // Sources are de-duplicated: the same path twice would collide with itself.
  final seen = <String>{};

  for (final raw in sources) {
    final source = path.normalize(path.absolute(raw));
    if (!seen.add(source)) continue;

    final type = await fs.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      refused.add(RefusedItem(source, TransferRefusal.missing));
      continue;
    }
    if (type == FileSystemEntityType.link) {
      refused.add(RefusedItem(source, TransferRefusal.link));
      continue;
    }
    final isDir = type == FileSystemEntityType.directory;
    final sameFolder = path.equals(path.dirname(source), dest);

    if (isDir && PathSafety.isWithin(source, dest, context: path)) {
      // Covers dest == source too: copying a folder into itself recurses
      // forever, moving it there is a no-op that `rename` reports as an
      // error on some platforms.
      refused.add(RefusedItem(source, TransferRefusal.intoItself));
      continue;
    }
    if (sameFolder && mode == TransferMode.move) {
      refused.add(RefusedItem(source, TransferRefusal.sameFolder));
      continue;
    }

    // Sizing is the one step that reads the source; a folder the user cannot
    // list is that item's problem, not the batch's.
    final int bytes;
    try {
      if (isDir) {
        final tree = await _listTree(fs.directory(source));
        if (tree.hasLinks) {
          refused.add(RefusedItem(source, TransferRefusal.link));
          continue;
        }
        bytes = tree.bytes;
      } else {
        bytes = await fs.file(source).length();
      }
    } on FileSystemException {
      refused.add(RefusedItem(source, TransferRefusal.unreadable));
      continue;
    }
    final target = path.join(dest, path.basename(source));
    items.add(
      TransferItem(
        source: source,
        isDirectory: isDir,
        bytes: bytes,
        target: target,
        conflict: await _exists(fs, target),
      ),
    );
  }

  return TransferPlan(
    destinationDir: dest,
    mode: mode,
    items: items,
    refused: refused,
  );
}

/// Runs [plan]. Each item is independent — one failure never aborts the
/// batch — and the result carries counts plus everything undo needs.
///
/// Conflicting items are skipped or renamed per [policy] *at run time*, so a
/// file that appeared in the destination after planning is still never
/// overwritten. [onProgress] receives cumulative bytes; [shouldStop] is polled
/// between files, and a stop mid-directory removes that directory's partial
/// copy so the destination never holds half a season.
Future<TransferResult> executeTransfer(
  TransferPlan plan, {
  required ConflictPolicy policy,
  FileSystem fs = _defaultFs,
  void Function(int bytesDone)? onProgress,
  bool Function()? shouldStop,
}) async {
  final path = fs.path;
  var succeeded = 0;
  var failed = 0;
  var skipped = 0;
  var bytesDone = 0;
  var stopped = false;
  final moves = <Map<String, String>>[];
  final created = <String>[];
  final failures = <TransferFailure>[];
  // Targets claimed by this batch, so two "a.mkv" from different folders
  // pasted together do not both resolve to the same free name.
  final claimed = <String>{};

  void progress(int bytes) {
    bytesDone += bytes;
    onProgress?.call(bytesDone);
  }

  for (final item in plan.items) {
    if (shouldStop?.call() ?? false) {
      stopped = true;
      break;
    }
    try {
      if (!PathSafety.isWithin(
        plan.destinationDir,
        item.target,
        context: path,
      )) {
        throw FileSystemException('Target escapes destination', item.target);
      }
      var target = item.target;
      final taken = claimed.contains(target) || await _exists(fs, target);
      if (taken) {
        if (policy == ConflictPolicy.skip) {
          skipped++;
          continue;
        }
        target = await _freeName(
          fs,
          target,
          claimed,
          isDirectory: item.isDirectory,
        );
        item.target = target;
      }
      claimed.add(target);

      if (item.isDirectory) {
        final outcome = await _transferDirectory(
          fs,
          item.source,
          target,
          plan.mode,
          onFile: progress,
          shouldStop: shouldStop,
        );
        if (outcome.stopped) {
          stopped = true;
          break;
        }
        // Recorded even when the item then fails: a cross-volume move whose
        // source could not be fully removed still put every file at the
        // target, and that is what undo must know about.
        moves.addAll(outcome.moves);
        created.addAll(outcome.created);
        if (outcome.error != null) {
          throw FileSystemException(outcome.error!, item.source);
        }
      } else {
        await fs.directory(path.dirname(target)).create(recursive: true);
        if (plan.mode == TransferMode.copy) {
          await fs.file(item.source).copy(target);
          created.add(target);
        } else {
          await _moveFile(fs, fs.file(item.source), target);
          moves.add({'from': item.source, 'to': target});
        }
        progress(item.bytes);
      }
      succeeded++;
    } catch (e) {
      failed++;
      failures.add(TransferFailure(item.source, e.toString()));
    }
  }

  return TransferResult(
    succeeded: succeeded,
    failed: failed,
    skipped: skipped,
    bytesDone: bytesDone,
    moves: moves,
    created: created,
    failures: failures,
    stopped: stopped,
  );
}

class _DirOutcome {
  final List<Map<String, String>> moves;
  final List<String> created;
  final bool stopped;

  /// Set when the tree reached the target but the item still counts as
  /// failed — see [_transferDirectory].
  final String? error;
  const _DirOutcome({
    this.moves = const [],
    this.created = const [],
    this.stopped = false,
    this.error,
  });
}

/// Moves or copies a whole tree.
///
/// A move tries one `rename` first — free on the same volume — and records
/// every file inside so undo can put each back; when the volume differs the
/// tree is copied and the source removed only after the copy completed.
///
/// Removing the source is done file by file rather than with one recursive
/// delete: a recursive delete that fails halfway has already taken some
/// files, and rolling back the *copy* at that point would leave those files
/// nowhere. If any source file survives, the copy stays, the moves are
/// recorded (undo treats an existing `from` as already restored) and the item
/// is reported failed with the duplicate named.
Future<_DirOutcome> _transferDirectory(
  FileSystem fs,
  String source,
  String target,
  TransferMode mode, {
  required void Function(int bytes) onFile,
  bool Function()? shouldStop,
}) async {
  final path = fs.path;
  // Listed again at run time: the plan's walk is minutes old by the time a
  // long batch reaches this item.
  final tree = await _listTree(fs.directory(source));
  if (tree.hasLinks) {
    throw FileSystemException('Folder contains symbolic links', source);
  }

  if (mode == TransferMode.move) {
    try {
      await fs.directory(source).rename(target);
      final moves = <Map<String, String>>[];
      for (final f in tree.files) {
        final rel = path.relative(f.path, from: source);
        moves.add({'from': f.path, 'to': path.join(target, rel)});
        onFile(f.size);
      }
      return _DirOutcome(moves: moves);
    } on FileSystemException {
      // Cross-volume: fall through to copy + delete.
    }
  }

  final copied = <String>[];
  final moves = <Map<String, String>>[];
  await fs.directory(target).create(recursive: true);
  try {
    // Directories first so an empty folder survives the transfer too.
    for (final dir in tree.directories) {
      final rel = path.relative(dir, from: source);
      await fs.directory(path.join(target, rel)).create(recursive: true);
    }
    for (final f in tree.files) {
      if (shouldStop?.call() ?? false) {
        await _tryDelete(fs.directory(target));
        return const _DirOutcome(stopped: true);
      }
      final rel = path.relative(f.path, from: source);
      final to = path.join(target, rel);
      await fs.file(f.path).copy(to);
      copied.add(to);
      moves.add({'from': f.path, 'to': to});
      onFile(f.size);
    }
  } catch (_) {
    // A half-copied tree is worse than none: the user sees a folder that
    // looks complete and is not. Roll it back, then report the failure.
    await _tryDelete(fs.directory(target));
    rethrow;
  }

  if (mode == TransferMode.copy) return _DirOutcome(created: copied);

  String? firstError;
  for (final f in tree.files) {
    try {
      await fs.file(f.path).delete();
    } catch (e) {
      firstError ??= '$e';
    }
  }
  if (firstError != null) {
    return _DirOutcome(
      moves: moves,
      error:
          'Copied to $target but the source could not be fully removed: '
          '$firstError',
    );
  }
  try {
    // Only empty folders are left; a failure here leaves debris, not data.
    await fs.directory(source).delete(recursive: true);
  } catch (e) {
    return _DirOutcome(
      moves: moves,
      error:
          'Copied to $target but the source folder could not be removed: '
          '$e',
    );
  }
  return _DirOutcome(moves: moves);
}

class _SizedFile {
  final String path;
  final int size;
  const _SizedFile(this.path, this.size);
}

/// One walk of a tree: its regular files with sizes, its directories
/// (shallowest first, as `list` yields them), and whether any symlink sits
/// inside. Links are neither sized nor copied — see [TransferRefusal.link].
class _Tree {
  final List<_SizedFile> files;
  final List<String> directories;
  final bool hasLinks;
  const _Tree(this.files, this.directories, this.hasLinks);

  int get bytes => files.fold<int>(0, (sum, f) => sum + f.size);
}

Future<_Tree> _listTree(Directory dir) async {
  final files = <_SizedFile>[];
  final dirs = <String>[];
  var links = false;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      files.add(_SizedFile(entity.path, await entity.length()));
    } else if (entity is Directory) {
      dirs.add(entity.path);
    } else {
      links = true;
    }
  }
  return _Tree(files, dirs, links);
}

Future<bool> _exists(FileSystem fs, String target) async =>
    await fs.type(target, followLinks: false) != FileSystemEntityType.notFound;

/// The keep-both spelling of [name]: `name (n).ext` for a file, and the
/// whole name numbered for a folder — `Show.2024 (2)`, not `Show (2).2024`.
/// One definition, used by the executor and by the conflict dialog's preview.
String numberedName(
  String name,
  int n, {
  required bool isDirectory,
  p.Context? context,
}) {
  final path = context ?? p.context;
  if (isDirectory) return '$name ($n)';
  return '${path.basenameWithoutExtension(name)} ($n)${path.extension(name)}';
}

/// `name (2).ext`, `name (3).ext`, … — the first that is neither on disk nor
/// already claimed by this batch.
Future<String> _freeName(
  FileSystem fs,
  String target,
  Set<String> claimed, {
  required bool isDirectory,
}) async {
  final path = fs.path;
  final dir = path.dirname(target);
  final name = path.basename(target);
  for (var n = 2; ; n++) {
    final candidate = path.join(
      dir,
      numberedName(name, n, isDirectory: isDirectory, context: path),
    );
    if (!claimed.contains(candidate) && !await _exists(fs, candidate)) {
      return candidate;
    }
  }
}

/// Same contract as the organize chokepoint's move: rename in place, fall
/// back to copy + delete across volumes, and remove the copy if the source
/// then cannot be deleted so nothing is silently duplicated.
Future<void> _moveFile(FileSystem fs, File source, String target) async {
  try {
    await source.rename(target);
  } on FileSystemException {
    await source.copy(target);
    try {
      await source.delete();
    } catch (_) {
      await _tryDelete(fs.file(target));
      rethrow;
    }
  }
}

Future<void> _tryDelete(FileSystemEntity entity) async {
  try {
    if (await entity.exists()) await entity.delete(recursive: true);
  } catch (_) {
    // Best effort — the caller is already reporting the primary failure.
  }
}
