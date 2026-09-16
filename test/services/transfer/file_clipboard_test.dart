import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/transfer/file_clipboard.dart';

void main() {
  test('starts empty and reports nothing as cut', () {
    final c = FileClipboard();
    expect(c.isEmpty, isTrue);
    expect(c.count, 0);
    expect(c.isCut('/a'), isFalse);
  });

  test('a cut marks exactly its paths; a copy marks none', () {
    final c = FileClipboard();
    var notified = 0;
    c.addListener(() => notified++);

    c.set(['/a', '/b'], ClipboardMode.cut);
    expect(c.isCut('/a'), isTrue);
    expect(c.isCut('/c'), isFalse);
    expect(c.mode, ClipboardMode.cut);
    expect(notified, 1);

    c.set(['/a'], ClipboardMode.copy);
    expect(c.isCut('/a'), isFalse);
    expect(c.paths, ['/a']);
    expect(notified, 2);
  });

  test('setting an empty list keeps the previous clipboard', () {
    final c = FileClipboard()..set(['/a'], ClipboardMode.copy);
    var notified = 0;
    c.addListener(() => notified++);

    c.set(const [], ClipboardMode.cut);

    expect(c.paths, ['/a']);
    expect(c.mode, ClipboardMode.copy);
    expect(notified, 0);
  });

  test('clear empties it once and is silent when already empty', () {
    final c = FileClipboard()..set(['/a'], ClipboardMode.cut);
    var notified = 0;
    c.addListener(() => notified++);

    c.clear();
    c.clear();

    expect(c.isEmpty, isTrue);
    expect(c.isCut('/a'), isFalse);
    expect(notified, 1);
  });

  test('the exposed list is unmodifiable', () {
    final c = FileClipboard()..set(['/a'], ClipboardMode.copy);
    expect(() => c.paths.add('/b'), throwsUnsupportedError);
  });
}
