import 'package:path/path.dart' as p;

/// A directory listing entry with its `stat()` baked in.
///
/// Lets the file browser sort and render rows without re-issuing one
/// `statSync` / `lengthSync` per row per repaint — the cost that used to
/// freeze the UI on large folders.
class FileEntry {
  final String path;
  final bool isDirectory;

  /// File size in bytes; 0 for directories.
  final int size;

  /// Last-modified timestamp from `stat()`.
  final DateTime modified;

  const FileEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  /// Basename of [path].
  String get name => p.basename(path);

  /// Extension of [path] including the dot, or `''` for directories.
  String get extension => isDirectory ? '' : p.extension(path);
}
