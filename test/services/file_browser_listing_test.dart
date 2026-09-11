import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:path/path.dart' as p;

/// A temp folder holding [count] empty video files named `<prefix>NNNN.mkv`,
/// zero-padded so a name sort has one obvious answer.
Future<Directory> _seed(String prefix, int count) async {
  final dir = await Directory.systemTemp.createTemp('browser_list_');
  for (var i = 0; i < count; i++) {
    final name = '$prefix${i.toString().padLeft(4, '0')}.mkv';
    await File(p.join(dir.path, name)).writeAsString('x');
  }
  return dir;
}

void main() {
  // 150 is comfortably past the service's stat batch size, so the listing has
  // to go through several batches to come back whole.
  test(
    'a folder larger than one stat batch loads completely and in order',
    () async {
      final dir = await _seed('f', 150);
      addTearDown(() => dir.delete(recursive: true));
      final browser = FileBrowserService();
      addTearDown(browser.dispose);

      browser.setCurrentDirectory(dir.path);
      await browser.loadFiles();

      expect(browser.files, hasLength(150));
      expect(browser.files.first.name, 'f0000.mkv');
      expect(browser.files.last.name, 'f0149.mkv');
    },
  );

  test('switching folders mid-listing keeps the newer folder', () async {
    final big = await _seed('big', 150);
    final small = await _seed('small', 3);
    addTearDown(() => big.delete(recursive: true));
    addTearDown(() => small.delete(recursive: true));
    final browser = FileBrowserService();
    addTearDown(browser.dispose);

    // Two setCurrentDirectory calls leave the first listing in flight. Its
    // generation is stale, so it has to abandon the rest of its batches
    // instead of writing the big folder over the small one when it finishes.
    browser.setCurrentDirectory(big.path);
    browser.setCurrentDirectory(small.path);
    await browser.loadFiles();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(browser.currentDirectory, small.path);
    expect(browser.files, hasLength(3));
    expect(browser.files.every((e) => e.name.startsWith('small')), isTrue);
  });
}
