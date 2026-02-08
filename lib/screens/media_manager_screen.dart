import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/file_label_service.dart';
import '../services/settings_service.dart';
import '../widgets/file_preview.dart';

enum SortOption { name, type, date, size }

class MediaManagerScreen extends StatefulWidget {
  const MediaManagerScreen({super.key});

  @override
  State<MediaManagerScreen> createState() => _MediaManagerScreenState();
}

class _MediaManagerScreenState extends State<MediaManagerScreen> {
  String? _currentDirectory;
  List<FileSystemEntity> _files = [];
  FileSystemEntity? _selectedFile;
  StreamSubscription<FileSystemEvent>? _directorySubscription;
  SortOption _currentSort = SortOption.name;
  bool _isAscending = true;

  @override
  void dispose() {
    _directorySubscription?.cancel();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        _currentDirectory = selectedDirectory;
        _selectedFile = null;
        _loadFiles();
        _watchDirectory();
      });
    }
  }

  void _watchDirectory() {
    _directorySubscription?.cancel();
    if (_currentDirectory != null) {
      final directory = Directory(_currentDirectory!);
      _directorySubscription = directory.watch().listen((event) {
        if (event.type == FileSystemEvent.delete && event.path == _currentDirectory) {
          _goToParent();
        } else {
          _loadFiles();
        }
      });
    }
  }

  void _loadFiles() {
    if (_currentDirectory != null) {
      final directory = Directory(_currentDirectory!);
      if (!directory.existsSync()) {
        _goToParent();
        return;
      }

      try {
        final entities = directory.listSync().toList();
        _sortEntities(entities);
        setState(() {
          _files = entities;
        });
      } catch (e) {
        debugPrint('Error listing files: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing directory: $e')),
        );
      }
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

  void _goToParent() {
    if (_currentDirectory != null) {
      final parent = Directory(_currentDirectory!).parent;
      if (parent.path != _currentDirectory) {
        setState(() {
          _currentDirectory = parent.path;
          _selectedFile = null;
          _loadFiles();
          _watchDirectory();
        });
      } else {
        setState(() {
          _currentDirectory = null;
          _files = [];
          _selectedFile = null;
        });
      }
    }
  }

  Future<void> _createNewFolder() async {
    if (_currentDirectory == null) return;
    final l10n = AppLocalizations.of(context)!;

    final TextEditingController folderNameController = TextEditingController();
    final String? folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createNewFolder),
        content: TextField(
          controller: folderNameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.folderName,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, folderNameController.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );

    if (folderName != null && folderName.isNotEmpty) {
      final newPath = p.join(_currentDirectory!, folderName);
      try {
        await Directory(newPath).create();
        _loadFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating folder: $e')),
          );
        }
      }
    }
  }

  Future<void> _renameEntity(FileSystemEntity entity) async {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController nameController = TextEditingController(text: p.basename(entity.path));
    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.rename),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.newName,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: Text(l10n.rename),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != p.basename(entity.path)) {
      final newPath = p.join(entity.parent.path, newName);
      try {
        if (entity is File) {
          final newFile = await entity.rename(newPath);
          _onFileRenamed(newFile);
        } else if (entity is Directory) {
          await entity.rename(newPath);
          _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error renaming: $e')),
          );
        }
      }
    }
  }

  void _onFileRenamed(FileSystemEntity newEntity) {
    setState(() {
      _selectedFile = newEntity;
      _loadFiles();
    });
  }

  void _showContextMenu(BuildContext context, Offset globalPosition, FileSystemEntity entity) {
    final l10n = AppLocalizations.of(context)!;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          onTap: () {
            Future.delayed(Duration.zero, () => _renameEntity(entity));
          },
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l10n.rename),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _showSearchDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    
    if (settings.searchSites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No search sites configured in Settings')),
      );
      return;
    }

    final keywordController = TextEditingController(
      text: _selectedFile != null ? p.basenameWithoutExtension(_selectedFile!.path) : '',
    );
    
    // Use the last selected site index from settings
    int selectedIndex = settings.lastSearchSiteIndex;
    if (selectedIndex >= settings.searchSites.length) {
      selectedIndex = 0;
    }
    SearchSite selectedSite = settings.searchSites[selectedIndex];

    final String defaultLang = Localizations.localeOf(context).languageCode;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.searchFromWeb),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keywordController,
                decoration: InputDecoration(labelText: l10n.searchKeyword),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SearchSite>(
                initialValue: selectedSite,
                decoration: InputDecoration(labelText: l10n.searchSite),
                items: settings.searchSites.asMap().entries.map((entry) {
                  return DropdownMenuItem(value: entry.value, child: Text(entry.value.name));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedSite = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.search)),
          ],
        ),
      ),
    );

    if (result == true && keywordController.text.isNotEmpty) {
      // Save the selected site index to settings
      final newIndex = settings.searchSites.indexOf(selectedSite);
      if (newIndex != -1) {
        settings.setLastSearchSiteIndex(newIndex);
      }

      String url = selectedSite.url;
      final lang = settings.locale?.languageCode ?? defaultLang;
      
      url = url.replaceAll('{keyword}', Uri.encodeComponent(keywordController.text));
      url = url.replaceAll('{lang}', lang);

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        // Left Side: File Browser
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
            ),
            child: Column(
              children: [
                // Browser Toolbar
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _currentDirectory != null ? _goToParent : null,
                          tooltip: l10n.parentFolder,
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: _pickDirectory,
                          tooltip: l10n.openDirectory,
                        ),
                        IconButton(
                          icon: const Icon(Icons.create_new_folder),
                          onPressed: _currentDirectory != null ? _createNewFolder : null,
                          tooltip: l10n.createNewFolder,
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _currentDirectory != null ? _loadFiles : null,
                          tooltip: l10n.refresh,
                        ),
                        IconButton(
                          icon: const Icon(Icons.public),
                          onPressed: _showSearchDialog,
                          tooltip: l10n.searchFromWeb,
                        ),
                        PopupMenuButton<dynamic>(
                          icon: const Icon(Icons.sort),
                          tooltip: l10n.sortBy,
                          onSelected: (value) {
                            setState(() {
                              if (value is SortOption) {
                                _currentSort = value;
                              } else if (value is bool) {
                                _isAscending = value;
                              }
                              _loadFiles();
                            });
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: SortOption.name,
                              child: Row(
                                children: [
                                  Icon(_currentSort == SortOption.name ? Icons.check : null, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.sortByName),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SortOption.type,
                              child: Row(
                                children: [
                                  Icon(_currentSort == SortOption.type ? Icons.check : null, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.sortByType),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SortOption.date,
                              child: Row(
                                children: [
                                  Icon(_currentSort == SortOption.date ? Icons.check : null, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.sortByDate),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SortOption.size,
                              child: Row(
                                children: [
                                  Icon(_currentSort == SortOption.size ? Icons.check : null, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.sortBySize),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: true,
                              child: Row(
                                children: [
                                  Icon(_isAscending ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.ascending),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: false,
                              child: Row(
                                children: [
                                  Icon(!_isAscending ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
                                  const SizedBox(width: 8),
                                  Text(l10n.descending),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _currentDirectory ?? 'No directory selected',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                // File List
                Expanded(
                  child: _currentDirectory == null
                      ? const Center(child: Text('Please select a directory'))
                      : ListView.builder(
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final entity = _files[index];
                            final name = p.basename(entity.path);
                            final isDirectory = entity is Directory;
                            final extension = p.extension(entity.path);
                            final label = isDirectory ? 'Folder' : FileLabelService.getLabel(extension);
                            final isSelected = _selectedFile?.path == entity.path;

                            return GestureDetector(
                              onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, entity),
                              onLongPressStart: (details) => _showContextMenu(context, details.globalPosition, entity),
                              child: InkWell(
                                onDoubleTap: isDirectory
                                    ? () {
                                        setState(() {
                                          _currentDirectory = entity.path;
                                          _selectedFile = null;
                                          _loadFiles();
                                          _watchDirectory();
                                        });
                                      }
                                    : null,
                                child: ListTile(
                                  leading: Icon(
                                    FileLabelService.getIcon(label, isDirectory),
                                    color: FileLabelService.getIconColor(label, isDirectory),
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: isDirectory ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text(label),
                                  selected: isSelected,
                                  onTap: () {
                                    setState(() {
                                      _selectedFile = entity;
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // Right Side: Operations / Preview
        Expanded(
          flex: 2,
          child: FilePreview(
            file: _selectedFile,
            onRenamed: _onFileRenamed,
          ),
        ),
      ],
    );
  }
}
