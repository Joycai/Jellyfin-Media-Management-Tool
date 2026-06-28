import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import 'file_label_service.dart';

enum SortOption { name, type, date, size }

class FileBrowserService extends ChangeNotifier {
  String? _currentDirectory;
  List<FileEntry> _files = [];
  FileEntry? _selectedFile;
  StreamSubscription<FileSystemEvent>? _directorySubscription;
  Timer? _reloadDebounce;
  SortOption _currentSort = SortOption.name;
  bool _isAscending = true;

  /// Bumped on every load attempt so a slow async load can detect that a
  /// newer one (or a setCurrentDirectory) has started and bail out instead
  /// of stomping on fresher state.
  int _loadGeneration = 0;

  /// Burst-event debounce window before a watcher-triggered reload runs.
  /// Long enough to coalesce extracts/batch renames, short enough to feel
  /// instant for one-off file drops.
  static const _reloadDelay = Duration(milliseconds: 200);

  String? get currentDirectory => _currentDirectory;
  List<FileEntry> get files => _files;
  FileEntry? get selectedFile => _selectedFile;
  SortOption get currentSort => _currentSort;
  bool get isAscending => _isAscending;

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _directorySubscription?.cancel();
    super.dispose();
  }

  void setCurrentDirectory(String? path) {
    if (_currentDirectory == path) return;
    _reloadDebounce?.cancel();
    _currentDirectory = path;
    _selectedFile = null;
    unawaited(loadFiles());
    _watchDirectory();
    notifyListeners();
  }

  void setSelectedFile(FileEntry? entry) {
    _selectedFile = entry;
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
    _directorySubscription = directory.watch().listen((_) => _onWatchEvent());
  }

  /// Coalesces a burst of watcher events into a single reload. Also handles
  /// the watched directory disappearing — on macOS the FSEvent fires on a
  /// child path, not the directory itself, so we re-check existence instead
  /// of comparing `event.path == _currentDirectory` (which never matched).
  void _onWatchEvent() {
    final dir = _currentDirectory;
    if (dir == null) return;
    if (!Directory(dir).existsSync()) {
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
      notifyListeners();
      return;
    }

    final gen = ++_loadGeneration;
    final directory = Directory(_currentDirectory!);

    if (!await directory.exists()) {
      if (gen != _loadGeneration) return;
      goToParent();
      return;
    }

    try {
      final raw = await directory.list(followLinks: false).toList();
      if (gen != _loadGeneration) return;

      final entries = await Future.wait(raw.map(_toEntry));
      if (gen != _loadGeneration) return;

      // Drop entries we couldn't stat (e.g. permission-denied symlinks).
      final usable = entries.whereType<FileEntry>().toList();
      _sortEntries(usable);
      _files = usable;
      // Clear stale selection if the file is gone.
      if (_selectedFile != null &&
          !usable.any((e) => e.path == _selectedFile!.path)) {
        _selectedFile = null;
      }
      notifyListeners();
    } catch (e) {
      if (gen != _loadGeneration) return;
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
          final labelA = a.isDirectory ? 'Folder' : FileLabelService.getLabel(a.extension);
          final labelB = b.isDirectory ? 'Folder' : FileLabelService.getLabel(b.extension);
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
    if (_currentDirectory != null) {
      final parent = Directory(_currentDirectory!).parent;
      if (parent.path != _currentDirectory) {
        setCurrentDirectory(parent.path);
      } else {
        setCurrentDirectory(null);
      }
    }
  }

  void refresh() {
    unawaited(loadFiles());
  }
}
