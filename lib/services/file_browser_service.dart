import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'file_label_service.dart';

enum SortOption { name, type, date, size }

class FileBrowserService extends ChangeNotifier {
  String? _currentDirectory;
  List<FileSystemEntity> _files = [];
  FileSystemEntity? _selectedFile;
  StreamSubscription<FileSystemEvent>? _directorySubscription;
  Timer? _reloadDebounce;
  SortOption _currentSort = SortOption.name;
  bool _isAscending = true;

  /// Burst-event debounce window before a watcher-triggered reload runs.
  /// Long enough to coalesce extracts/batch renames, short enough to feel
  /// instant for one-off file drops.
  static const _reloadDelay = Duration(milliseconds: 200);

  String? get currentDirectory => _currentDirectory;
  List<FileSystemEntity> get files => _files;
  FileSystemEntity? get selectedFile => _selectedFile;
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
    loadFiles();
    _watchDirectory();
    notifyListeners();
  }

  void setSelectedFile(FileSystemEntity? entity) {
    _selectedFile = entity;
    notifyListeners();
  }

  void setSortOption(SortOption option) {
    _currentSort = option;
    loadFiles();
    notifyListeners();
  }

  void setAscending(bool value) {
    _isAscending = value;
    loadFiles();
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
    _reloadDebounce = Timer(_reloadDelay, loadFiles);
  }

  void loadFiles() {
    if (_currentDirectory != null) {
      final directory = Directory(_currentDirectory!);
      if (!directory.existsSync()) {
        goToParent();
        return;
      }

      try {
        // Using sync for now as per current implementation, 
        // but this service makes it easier to change to async later.
        final entities = directory.listSync().toList();
        _sortEntities(entities);
        _files = entities;
        notifyListeners();
      } catch (e) {
        debugPrint('Error listing files: $e');
      }
    } else {
      _files = [];
      notifyListeners();
    }
  }

  void _sortEntities(List<FileSystemEntity> entities) {
    entities.sort((a, b) {
      if (a is Directory && b is! Directory) return -1;
      if (a is! Directory && b is Directory) return 1;

      int comparison;
      switch (_currentSort) {
        case SortOption.name:
          comparison = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          break;
        case SortOption.type:
          final labelA = a is Directory ? 'Folder' : FileLabelService.getLabel(p.extension(a.path));
          final labelB = b is Directory ? 'Folder' : FileLabelService.getLabel(p.extension(b.path));
          comparison = labelA.compareTo(labelB);
          if (comparison == 0) {
            comparison = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case SortOption.date:
          // Using statSync here for consistency with current implementation.
          final statA = a.statSync();
          final statB = b.statSync();
          comparison = statA.modified.compareTo(statB.modified);
          break;
        case SortOption.size:
          final sizeA = a is File ? a.lengthSync() : 0;
          final sizeB = b is File ? b.lengthSync() : 0;
          comparison = sizeA.compareTo(sizeB);
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
    loadFiles();
  }
}
