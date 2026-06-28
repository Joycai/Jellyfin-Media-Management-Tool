import 'package:path/path.dart' as p;

/// Path-containment checks used before any move/rename — defends against an
/// AI-generated plan (or tampered undo manifest) whose target resolves outside
/// the user-chosen folder via `..` segments or absolute paths.
class PathSafety {
  /// True iff [candidate] resolves to [base] itself or a descendant of it,
  /// after `..` and symlink-free normalization. Both inputs are made absolute
  /// before comparison so a relative `candidate` is treated as joined with the
  /// current working directory — callers should pass already-joined paths.
  static bool isWithin(String base, String candidate) {
    final b = p.normalize(p.absolute(base));
    final c = p.normalize(p.absolute(candidate));
    return p.equals(b, c) || p.isWithin(b, c);
  }
}
