import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../services/file_label_service.dart';

class FileListView extends StatelessWidget {
  final List<FileSystemEntity> files;
  final FileSystemEntity? selectedFile;
  final Function(FileSystemEntity) onFileTap;
  final Function(FileSystemEntity) onFileDoubleTap;
  final Function(BuildContext, Offset, FileSystemEntity) onContextMenu;

  const FileListView({
    super.key,
    required this.files,
    this.selectedFile,
    required this.onFileTap,
    required this.onFileDoubleTap,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (files.isEmpty) {
      return Center(child: Text(l10n.pleaseSelectDirectory));
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final entity = files[index];
        final name = p.basename(entity.path);
        final isDirectory = entity is Directory;
        final extension = p.extension(entity.path);
        final label = isDirectory ? 'Folder' : FileLabelService.getLabel(extension);
        final isSelected = selectedFile?.path == entity.path;

        return GestureDetector(
          onSecondaryTapDown: (details) => onContextMenu(context, details.globalPosition, entity),
          onLongPressStart: (details) => onContextMenu(context, details.globalPosition, entity),
          child: InkWell(
            onDoubleTap: isDirectory ? () => onFileDoubleTap(entity) : null,
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
              onTap: () => onFileTap(entity),
            ),
          ),
        );
      },
    );
  }
}
