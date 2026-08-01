import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';

FileEntry _entry(String path, {bool isDirectory = false}) => FileEntry(
  path: path,
  isDirectory: isDirectory,
  size: 0,
  modified: DateTime(2026),
);

void main() {
  group('FileBrowserService.selectAll', () {
    test('selects exactly the entries it is given', () {
      final service = FileBrowserService();
      final visible = [_entry('/work/a.mkv'), _entry('/work/b.mkv')];

      service.selectAll(visible);

      expect(service.selectionCount, 2);
      expect(service.isSelected('/work/a.mkv'), isTrue);
      expect(service.isSelected('/work/b.mkv'), isTrue);
    });

    test('honors a filtered list rather than everything on disk', () {
      // Select-all must mean "everything visible", not "everything in the
      // directory" — otherwise an active search silently selects hidden rows.
      final service = FileBrowserService();
      service.selectAll([_entry('/work/match.mkv')]);

      expect(service.selectionCount, 1);
      expect(service.isSelected('/work/other.mkv'), isFalse);
    });

    test('replaces a previous selection instead of adding to it', () {
      final service = FileBrowserService();
      service.selectAll([_entry('/work/a.mkv')]);
      service.selectAll([_entry('/work/b.mkv')]);

      expect(service.selectionCount, 1);
      expect(service.isSelected('/work/a.mkv'), isFalse);
      expect(service.isSelected('/work/b.mkv'), isTrue);
    });

    test('an empty list is a no-op, not a clear', () {
      final service = FileBrowserService();
      service.selectAll([_entry('/work/a.mkv')]);

      var notified = false;
      service.addListener(() => notified = true);
      service.selectAll([]);

      expect(service.selectionCount, 1);
      expect(notified, isFalse);
    });

    test('keeps an existing focused row rather than moving it', () {
      final service = FileBrowserService();
      final focused = _entry('/work/b.mkv');
      service.selectSingle(focused);

      service.selectAll([_entry('/work/a.mkv'), focused]);

      expect(service.selectedFile?.path, '/work/b.mkv');
      expect(service.selectionCount, 2);
    });

    test('adopts a focus when there was none', () {
      final service = FileBrowserService();
      service.selectAll([_entry('/work/a.mkv'), _entry('/work/b.mkv')]);

      expect(service.selectedFile?.path, '/work/a.mkv');
    });

    test('notifies listeners so the footer count updates', () {
      final service = FileBrowserService();
      var notified = 0;
      service.addListener(() => notified++);

      service.selectAll([_entry('/work/a.mkv')]);

      expect(notified, 1);
    });
  });
}
