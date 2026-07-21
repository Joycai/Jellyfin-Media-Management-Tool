import 'package:path/path.dart' as p;

/// Path-containment checks used before any move/rename — defends against an
/// AI-generated plan (or tampered undo manifest) whose target resolves outside
/// the user-chosen folder via `..` segments or absolute paths.
class PathSafety {
  /// True iff [candidate] resolves to [base] itself or a descendant of it,
  /// after `..` and symlink-free normalization. Both inputs are made absolute
  /// before comparison so a relative `candidate` is treated as joined with the
  /// current working directory — callers should pass already-joined paths.
  ///
  /// [context] selects the path style. It must match the filesystem the paths
  /// came from: the host default would read a POSIX path like `/work/a.mkv` as
  /// a Windows root-relative one and mis-resolve it against the current drive.
  static bool isWithin(String base, String candidate, {p.Context? context}) {
    final ctx = context ?? p.context;
    final b = ctx.normalize(ctx.absolute(base));
    final c = ctx.normalize(ctx.absolute(candidate));
    return ctx.equals(b, c) || ctx.isWithin(b, c);
  }
}
