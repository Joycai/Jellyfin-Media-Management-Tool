import 'package:path/path.dart' as p;

/// One row in a flattened directory tree: a folder or file name plus its
/// indent depth, ready to render as an indented list.
class TreeLine {
  final String name;
  final int depth;
  final bool isDir;
  const TreeLine({
    required this.name,
    required this.depth,
    required this.isDir,
  });
}

/// Collapses a list of relative paths into a sorted, de-duplicated tree of
/// [TreeLine] entries. Each segment past the leaf is treated as a directory.
List<TreeLine> buildPathTree(List<String> paths) {
  final seen = <String>{};
  final lines = <TreeLine>[];
  final sorted = [...paths]..sort();
  for (final path in sorted) {
    final parts = p.split(path).where((s) => s.isNotEmpty).toList();
    for (var i = 0; i < parts.length; i++) {
      final key = parts.sublist(0, i + 1).join('/');
      if (seen.add(key)) {
        lines.add(
          TreeLine(name: parts[i], depth: i, isDir: i < parts.length - 1),
        );
      }
    }
  }
  return lines;
}
