import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';

void main() {
  group('FileEntry', () {
    test('name comes from the basename of path', () {
      final e = FileEntry(
        path: '/work/Movies/Dune (2021).mkv',
        isDirectory: false,
        size: 100,
        modified: DateTime(2024, 1, 1),
      );
      expect(e.name, 'Dune (2021).mkv');
      expect(e.extension, '.mkv');
    });

    test('extension is empty for directories', () {
      final e = FileEntry(
        path: '/work/Movies',
        isDirectory: true,
        size: 0,
        modified: DateTime(2024, 1, 1),
      );
      expect(e.extension, '');
    });
  });
}
