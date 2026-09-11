import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:path/path.dart' as p;

/// A folder with one subdirectory and three files whose names, types, sizes
/// and timestamps all disagree, so every sort option has a distinct answer.
///
/// `B.mkv` is capitalised on purpose: the name sort is case-insensitive and
/// the comparator used to lower both sides on every comparison, which is what
/// the precomputed keys have to keep doing.
Future<Directory> _tree() async {
  final dir = await Directory.systemTemp.createTemp('browser_sort_');
  await Directory(p.join(dir.path, 'zzz')).create();

  Future<void> write(String name, int size, DateTime modified) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsString('x' * size);
    await f.setLastModified(modified);
  }

  final t = DateTime(2026, 1, 1);
  await write('a.txt', 30, t.add(const Duration(hours: 3)));
  await write('B.mkv', 10, t.add(const Duration(hours: 1)));
  await write('c.mkv', 20, t.add(const Duration(hours: 2)));
  return dir;
}

List<String> _names(FileBrowserService b) =>
    b.files.map((e) => e.name).toList();

void main() {
  late Directory dir;
  late FileBrowserService browser;

  setUp(() async {
    dir = await _tree();
    browser = FileBrowserService();
    browser.setCurrentDirectory(dir.path);
    await browser.loadFiles();
  });

  tearDown(() async {
    browser.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('name sort puts folders first and ignores case', () {
    expect(_names(browser), ['zzz', 'a.txt', 'B.mkv', 'c.mkv']);
  });

  test('type sort groups by label, then by name inside a label', () {
    browser.setSortOption(SortOption.type);

    // Folder, then Text, then the two Videos in name order.
    expect(_names(browser), ['zzz', 'a.txt', 'B.mkv', 'c.mkv']);
  });

  test('size sort orders by bytes', () {
    browser.setSortOption(SortOption.size);

    // The directory reports size 0, so it leads on the way up.
    expect(_names(browser), ['zzz', 'B.mkv', 'c.mkv', 'a.txt']);
  });

  test('date sort orders by modified time', () {
    browser.setSortOption(SortOption.date);

    expect(_names(browser), ['zzz', 'B.mkv', 'c.mkv', 'a.txt']);
  });

  test('descending reverses the files but leaves folders pinned first', () {
    browser.setAscending(false);

    // The folders-first check returns before the direction is applied, so a
    // descending sort reverses the files among themselves and the directory
    // still leads. Longstanding behaviour, asserted here so the precomputed
    // keys cannot quietly change it.
    expect(_names(browser), ['zzz', 'c.mkv', 'B.mkv', 'a.txt']);
  });
}
