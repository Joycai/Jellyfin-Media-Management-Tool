import 'package:flutter/foundation.dart';

/// What a paste will do with the clipboard's entries.
enum ClipboardMode { copy, cut }

/// The file browser's copy/cut clipboard.
///
/// App-internal on purpose: Flutter has no cross-platform file clipboard, and
/// the three OS formats (`CF_HDROP`, `NSFilenamesPboardType`, `text/uri-list`)
/// would each need native code. Holding absolute paths here gives copy, cut
/// and paste inside the app today; OS interop is backlog B25.
///
/// A cut is a *promise*, not an action: nothing moves until the paste, and the
/// table only dims the cut rows ([isCut]) so the user can see what a paste
/// will take away. The clipboard survives folder changes — cut in one folder,
/// navigate, paste in another is the whole point.
class FileClipboard extends ChangeNotifier {
  List<String> _paths = const [];
  ClipboardMode _mode = ClipboardMode.copy;

  /// Absolute paths, in the order they were selected.
  List<String> get paths => _paths;
  ClipboardMode get mode => _mode;
  bool get isEmpty => _paths.isEmpty;
  bool get isNotEmpty => _paths.isNotEmpty;
  int get count => _paths.length;

  Set<String> _cutSet = const {};

  /// True when [path] is on the clipboard as a cut — the row draws dimmed.
  bool isCut(String path) => _cutSet.contains(path);

  /// Replaces the clipboard. An empty [paths] is a no-op rather than a clear,
  /// so a shortcut fired with nothing focused leaves a previous copy intact.
  void set(Iterable<String> paths, ClipboardMode mode) {
    final list = List<String>.unmodifiable(paths);
    if (list.isEmpty) return;
    _paths = list;
    _mode = mode;
    _cutSet = mode == ClipboardMode.cut ? Set.unmodifiable(list) : const {};
    notifyListeners();
  }

  void clear() {
    if (_paths.isEmpty) return;
    _paths = const [];
    _cutSet = const {};
    notifyListeners();
  }
}
