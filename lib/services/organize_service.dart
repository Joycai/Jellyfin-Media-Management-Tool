import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../models/organize_plan.dart';
import 'path_safety.dart';

/// Outcome of applying a plan.
class ApplyResult {
  final int succeeded;
  final int failed;
  final List<OrganizeAction> failures;

  const ApplyResult({
    required this.succeeded,
    required this.failed,
    required this.failures,
  });

  bool get hasFailures => failed > 0;
}

/// Outcome of applying a single action.
class MoveOutcome {
  final bool ok;
  final int bytes;
  final String? error;
  final String? fromPath;
  final String? toPath;
  const MoveOutcome({required this.ok, this.bytes = 0, this.error, this.fromPath, this.toPath});
}

/// Executes an [OrganizePlan] against the filesystem. All paths are resolved
/// relative to [baseDir] (the folder that was organized) and go through the
/// `path` package. Each action is applied independently and reports its own
/// success/failure so a single bad move never aborts the batch.
class OrganizeService {
  static const FileSystem _defaultFs = LocalFileSystem();

  /// Applies one pending action: validates the resolved paths stay under
  /// [baseDir], creates the target folder, and moves the file. Sets
  /// [action.status] and returns the bytes moved (for progress reporting).
  ///
  /// [fs] is injected in tests; production callers leave it at the default.
  static Future<MoveOutcome> applyAction(
    OrganizeAction action, {
    required String baseDir,
    FileSystem fs = _defaultFs,
  }) async {
    final sourcePath = p.normalize(p.join(baseDir, action.source));
    final targetPath = p.normalize(p.join(baseDir, action.target));
    try {
      if (!PathSafety.isWithin(baseDir, sourcePath) ||
          !PathSafety.isWithin(baseDir, targetPath)) {
        throw FileSystemException('Path escapes base directory', targetPath);
      }
      if (sourcePath == targetPath) {
        action.status = ActionStatus.applied;
        return const MoveOutcome(ok: true);
      }
      final sourceFile = fs.file(sourcePath);
      if (!await sourceFile.exists()) {
        throw FileSystemException('Source no longer exists', sourcePath);
      }
      final bytes = await sourceFile.length();
      await fs.directory(p.dirname(targetPath)).create(recursive: true);
      await _moveFile(sourceFile, targetPath, fs);
      action.status = ActionStatus.applied;
      action.error = null;
      return MoveOutcome(ok: true, bytes: bytes, fromPath: sourcePath, toPath: targetPath);
    } catch (e) {
      action.status = ActionStatus.failed;
      action.error = e.toString();
      return MoveOutcome(ok: false, error: e.toString());
    }
  }

  /// Renames in place when possible; falls back to copy+delete across volumes
  /// (where `rename` throws). Refuses to clobber an existing target. If the
  /// post-copy delete of the source fails, the partial target is cleaned up
  /// so we don't leave a silent duplicate.
  static Future<void> _moveFile(File source, String targetPath, FileSystem fs) async {
    if (await fs.file(targetPath).exists() ||
        await fs.directory(targetPath).exists()) {
      throw FileSystemException('Target already exists', targetPath);
    }
    try {
      await source.rename(targetPath);
    } on FileSystemException {
      await source.copy(targetPath);
      try {
        await source.delete();
      } catch (_) {
        try { await fs.file(targetPath).delete(); } catch (_) {}
        rethrow;
      }
    }
  }
}
