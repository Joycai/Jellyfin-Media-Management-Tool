import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Windows path rules stop at a UNC share root, as at a drive', () {
    // goToParent relies on this. `Directory.parent` walked past the share to
    // `\\nas\`, which is not a directory, and `exists` throws on it.
    expect(p.windows.dirname(r'\\nas\media\Movies'), r'\\nas\media');
    expect(p.windows.dirname(r'\\nas\media'), r'\\nas\media');
    expect(p.windows.dirname(r'C:\'), r'C:\');
  });

  test('goToParent moves to the containing folder', () async {
    final root = await Directory.systemTemp.createTemp('browser_parent_');
    addTearDown(() => root.delete(recursive: true));
    final child = await Directory(p.join(root.path, 'child')).create();
    final browser = FileBrowserService();
    addTearDown(browser.dispose);

    browser.setCurrentDirectory(child.path);
    browser.goToParent();

    expect(browser.currentDirectory, root.path);
  });
}
