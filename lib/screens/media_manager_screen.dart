import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../services/file_browser_service.dart';
import '../widgets/file_preview.dart';
import '../widgets/dialogs/input_dialog.dart';
import '../widgets/dialogs/search_dialog.dart';
import '../widgets/file_browser/browser_toolbar.dart';
import '../widgets/file_browser/file_list_view.dart';

class MediaManagerScreen extends StatefulWidget {
  const MediaManagerScreen({super.key});

  @override
  State<MediaManagerScreen> createState() => _MediaManagerScreenState();
}

class _MediaManagerScreenState extends State<MediaManagerScreen> {
  Future<void> _pickDirectory() async {
    final browser = context.read<FileBrowserService>();
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      browser.setCurrentDirectory(selectedDirectory);
    }
  }

  Future<void> _createNewFolder() async {
    final browser = context.read<FileBrowserService>();
    if (browser.currentDirectory == null) return;
    final l10n = AppLocalizations.of(context)!;

    final String? folderName = await showDialog<String>(
      context: context,
      builder: (context) => InputDialog(
        title: l10n.createNewFolder,
        labelText: l10n.folderName,
        actionLabel: l10n.create,
      ),
    );

    if (folderName != null && folderName.isNotEmpty) {
      final newPath = p.join(browser.currentDirectory!, folderName);
      try {
        await Directory(newPath).create();
        browser.refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorCreatingFolder(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _renameEntity(FileSystemEntity entity) async {
    final l10n = AppLocalizations.of(context)!;
    final browser = context.read<FileBrowserService>();
    
    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => InputDialog(
        title: l10n.rename,
        labelText: l10n.newName,
        initialValue: p.basename(entity.path),
        actionLabel: l10n.rename,
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != p.basename(entity.path)) {
      final newPath = p.join(entity.parent.path, newName);
      try {
        if (entity is File) {
          final newFile = await entity.rename(newPath);
          browser.setSelectedFile(newFile);
          browser.refresh();
        } else if (entity is Directory) {
          await entity.rename(newPath);
          browser.refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorRenaming(e.toString()))),
          );
        }
      }
    }
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
    final browser = context.read<FileBrowserService>();
    
    if (settings.searchSites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noSearchSitesConfigured)),
      );
      return;
    }

    final String initialKeyword = browser.selectedFile != null ? p.basenameWithoutExtension(browser.selectedFile!.path) : '';
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => WebSearchDialog(initialKeyword: initialKeyword),
    );

    if (result != null) {
      final String keyword = result['keyword'];
      final SearchSite site = result['site'];
      if (!mounted) return;
      final String defaultLang = Localizations.localeOf(context).languageCode;

      if (keyword.isNotEmpty) {
        String url = site.url;
        final lang = settings.locale?.languageCode ?? defaultLang;
        
        url = url.replaceAll('{keyword}', Uri.encodeComponent(keyword));
        url = url.replaceAll('{lang}', lang);

        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final browser = context.watch<FileBrowserService>();

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
                BrowserToolbar(
                  currentDirectory: browser.currentDirectory,
                  currentSort: browser.currentSort,
                  isAscending: browser.isAscending,
                  onPickDirectory: _pickDirectory,
                  onGoToParent: browser.goToParent,
                  onCreateFolder: _createNewFolder,
                  onRefresh: browser.refresh,
                  onSearchWeb: _showSearchDialog,
                  onSortChanged: (value) {
                    if (value is SortOption) {
                      browser.setSortOption(value);
                    } else if (value is bool) {
                      browser.setAscending(value);
                    }
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: FileListView(
                    files: browser.files,
                    selectedFile: browser.selectedFile,
                    onFileTap: (entity) => browser.setSelectedFile(entity),
                    onFileDoubleTap: (entity) => browser.setCurrentDirectory(entity.path),
                    onContextMenu: _showContextMenu,
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
            file: browser.selectedFile,
            onRenamed: (newFile) {
              browser.setSelectedFile(newFile);
              browser.refresh();
            },
          ),
        ),
      ],
    );
  }
}
