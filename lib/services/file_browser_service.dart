import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import 'file_label_service.dart';

enum SortOption { name, type, date, size }

class FileBrowserService extends ChangeNotifier {
  String? _currentDirectory;
  List<FileEntry> _files = [];
  FileEntry? _selectedFile;

  /// Multi-selection: absolute paths of every checked/ctrl-clicked entry.
  /// [_selectedFile] stays the focused row (single click / range anchor).
  final Set<String> _selectedPaths = {};

  /// Range-select anchor (shift-click extends from here).
  String? _anchorPath;
  StreamSubscription<FileSystemEvent>? _directorySubscription;
  Timer? _reloadDebounce;
  SortOption _currentSort = SortOption.name;
  bool _isAscending = true;

  /// Bumped on every load attempt so a slow async load can detect that a
  /// newer one (or a setCurrentDirectory) has started and bail out instead
  /// of stomping on fresher state.
  int _loadGeneration = 0;

  /// How many entries are stat'd at once when listing a directory.
  ///
  /// One future per entry meant a folder with 20k files put 20k concurrent
  /// stat calls and 20k pending futures in flight before the first result
  /// came back. Batching also gives the generation guard somewhere to check:
  /// it used to run only after the whole listing had resolved, so switching
  /// folders quickly still paid for every stale stat.
  static const int _statBatch = 64;

  /// Burst-event debounce window before a watcher-triggered reload runs.
  /// Long enough to coalesce extracts/batch renames, short enough to feel
  /// instant for one-off file drops.
  static const _reloadDelay = Duration(milliseconds: 200);

  String? get currentDirectory => _currentDirectory;
  List<FileEntry> get files => _files;
  FileEntry? get selectedFile => _selectedFile;
  SortOption get currentSort => _currentSort;
  bool get isAscending => _isAscending;

  /// Absolute paths of every multi-selected entry.
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);
  int get selectionCount => _selectedPaths.length;
  bool isSelected(String path) => _selectedPaths.contains(path);

  /// Entries (from the current listing) that are multi-selected.
  List<FileEntry> get selectedEntries =>
      _files.where((e) => _selectedPaths.contains(e.path)).toList();

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _reloadDebounce?.cancel();
    _directorySubscription?.cancel();
    super.dispose();
  }

  void setCurrentDirectory(String? path) {
    if (_currentDirectory == path) return;
    _reloadDebounce?.cancel();
    _currentDirectory = path;
    _selectedFile = null;
    _selectedPaths.clear();
    _anchorPath = null;
    unawaited(loadFiles());
    _watchDirectory();
    notifyListeners();
  }

  void setSelectedFile(FileEntry? entry) {
    _selectedFile = entry;
    notifyListeners();
  }

  /// Plain click: focus [entry] and clear any multi-selection. Only the
  /// checkbox / ctrl-click / shift-click gestures populate [selectedPaths],
  /// so "organize selected" never fires from a mere focus click.
  void selectSingle(FileEntry entry) {
    _selectedFile = entry;
    _anchorPath = entry.path;
    _selectedPaths.clear();
    notifyListeners();
  }

  /// Checkbox / ctrl-click: add or remove [entry] from the selection.
  void toggleSelection(FileEntry entry) {
    if (_selectedPaths.contains(entry.path)) {
      _selectedPaths.remove(entry.path);
      if (_selectedFile?.path == entry.path) _selectedFile = null;
    } else {
      _selectedPaths.add(entry.path);
      _selectedFile = entry;
    }
    _anchorPath = entry.path;
    notifyListeners();
  }

  /// Shift-click: replace the selection with the range between the current
  /// anchor and [target], in [visible] order (the UI's filtered/sorted list).
  void selectRange(List<FileEntry> visible, FileEntry target) {
    final anchorIdx = _anchorPath == null
        ? -1
        : visible.indexWhere((e) => e.path == _anchorPath);
    final targetIdx = visible.indexWhere((e) => e.path == target.path);
    if (targetIdx < 0) return;
    if (anchorIdx < 0) {
      selectSingle(target);
      return;
    }
    final lo = anchorIdx < targetIdx ? anchorIdx : targetIdx;
    final hi = anchorIdx < targetIdx ? targetIdx : anchorIdx;
    _selectedPaths
      ..clear()
      ..addAll(visible.sublist(lo, hi + 1).map((e) => e.path));
    _selectedFile = target;
    notifyListeners();
  }

  /// Select-all: replaces the selection with every entry in [visible] (the
  /// UI's filtered/sorted list, not [files], so it honors an active search).
  void selectAll(Iterable<FileEntry> visible) {
    final paths = visible.map((e) => e.path).toList();
    if (paths.isEmpty) return;
    _selectedPaths
      ..clear()
      ..addAll(paths);
    _selectedFile ??= visible.first;
    _anchorPath = paths.first;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedPaths.isEmpty && _selectedFile == null) return;
    _selectedPaths.clear();
    _selectedFile = null;
    _anchorPath = null;
    notifyListeners();
  }

  void setSortOption(SortOption option) {
    if (_currentSort == option) return;
    _currentSort = option;
    _sortEntries(_files);
    notifyListeners();
  }

  void setAscending(bool value) {
    if (_isAscending == value) return;
    _isAscending = value;
    _sortEntries(_files);
    notifyListeners();
  }

  void _watchDirectory() {
    _directorySubscription?.cancel();
    if (_currentDirectory == null) return;
    final directory = Directory(_currentDirectory!);
    try {
      _directorySubscription = directory.watch().listen(
        (_) => _onWatchEvent(),
        // A network share's watch can fail after it starts — the NAS sleeps,
        // the connection drops. That should cost live updates, not surface as
        // an unhandled error; a manual refresh still works.
        onError: (Object e) =>
            debugPrint('Error watching directory $_currentDirectory: $e'),
      );
    } catch (e) {
      debugPrint('Error watching directory $_currentDirectory: $e');
    }
  }

  /// Coalesces a burst of watcher events into a single reload. Also handles
  /// the watched directory disappearing — on macOS the FSEvent fires on a
  /// child path, not the directory itself, so we re-check existence instead
  /// of comparing `event.path == _currentDirectory` (which never matched).
  void _onWatchEvent() {
    final dir = _currentDirectory;
    if (dir == null) return;
    if (!_existsSync(Directory(dir))) {
      _reloadDebounce?.cancel();
      goToParent();
      return;
    }
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(_reloadDelay, () => unawaited(loadFiles()));
  }

  Future<void> loadFiles() async {
    if (_currentDirectory == null) {
      _files = [];
      _selectedFile = null;
      if (!_disposed) notifyListeners();
      return;
    }

    final gen = ++_loadGeneration;
    final directory = Directory(_currentDirectory!);

    if (!await _exists(directory)) {
      if (gen != _loadGeneration || _disposed) return;
      goToParent();
      return;
    }

    try {
      final raw = await directory.list(followLinks: false).toList();
      if (gen != _loadGeneration || _disposed) return;

      // Entries we couldn't stat (e.g. permission-denied symlinks) come back
      // null from _toEntry and are dropped here rather than aborting the
      // listing over one unreadable file.
      final usable = <FileEntry>[];
      for (var i = 0; i < raw.length; i += _statBatch) {
        // A newer load -- or a dispose -- while this one was mid-flight means
        // the rest of these stats are work for a directory nobody is looking
        // at any more.
        if (gen != _loadGeneration || _disposed) return;
        final batch = raw.skip(i).take(_statBatch);
        usable.addAll(
          (await Future.wait(batch.map(_toEntry))).whereType<FileEntry>(),
        );
      }
      if (gen != _loadGeneration || _disposed) return;

      _sortEntries(usable);
      _files = usable;
      // Clear stale selection if the file is gone.
      if (_selectedFile != null &&
          !usable.any((e) => e.path == _selectedFile!.path)) {
        _selectedFile = null;
      }
      final live = usable.map((e) => e.path).toSet();
      _selectedPaths.removeWhere((path) => !live.contains(path));
      if (_anchorPath != null && !live.contains(_anchorPath)) {
        _anchorPath = null;
      }
      if (!_disposed) notifyListeners();
    } catch (e) {
      if (gen != _loadGeneration || _disposed) return;
      debugPrint('Error listing files: $e');
    }
  }

  Future<FileEntry?> _toEntry(FileSystemEntity entity) async {
    try {
      final stat = await entity.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      return FileEntry(
        path: entity.path,
        isDirectory: isDir,
        size: isDir ? 0 : stat.size,
        modified: stat.modified,
      );
    } catch (_) {
      return null;
    }
  }

  void _sortEntries(List<FileEntry> entries) {
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int comparison;
      switch (_currentSort) {
        case SortOption.name:
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortOption.type:
          final labelA = a.isDirectory
              ? 'Folder'
              : FileLabelService.getLabel(a.extension);
          final labelB = b.isDirectory
              ? 'Folder'
              : FileLabelService.getLabel(b.extension);
          comparison = labelA.compareTo(labelB);
          if (comparison == 0) {
            comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
        case SortOption.date:
          comparison = a.modified.compareTo(b.modified);
          break;
        case SortOption.size:
          comparison = a.size.compareTo(b.size);
          break;
      }

      return _isAscending ? comparison : -comparison;
    });
  }

  void goToParent() {
    final current = _currentDirectory;
    if (current == null) return;
    // `p.dirname` treats a UNC share (`\\nas\media`) as a root, the way it
    // treats `C:\`. `Directory.parent` did not: it walked on to `\\nas\`,
    // which is no directory at all, and `exists` throws on it.
    final parent = p.dirname(current);
    setCurrentDirectory(p.equals(parent, current) ? null : parent);
  }

  /// `exists`, counting a path that cannot be checked as still present.
  ///
  /// Windows throws rather than returning false for a UNC path it cannot
  /// resolve — a NAS gone to sleep, a dropped connection. Reading that as
  /// "deleted" walked the browser up the tree one failing parent at a time
  /// until it fell off the root onto the empty start page, when the folder
  /// was only out of reach for a moment.
  static Future<bool> _exists(Directory directory) async {
    try {
      return await directory.exists();
    } catch (_) {
      return true;
    }
  }

  static bool _existsSync(Directory directory) {
    try {
      return directory.existsSync();
    } catch (_) {
      return true;
    }
  }

  void refresh() {
    unawaited(loadFiles());
  }
}
