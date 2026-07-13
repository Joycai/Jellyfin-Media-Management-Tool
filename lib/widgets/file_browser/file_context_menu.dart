import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../services/file_browser_service.dart';
import '../../services/file_label_service.dart';
import '../../utils/format.dart';
import '../dialogs/input_dialog.dart';
import '../dialogs/preview_dialog.dart';

enum _MenuAction { preview, rename, delete, properties, reveal }

/// Right-click / long-press context menu for a file-table row.
///
/// Actions operate on [entry], except delete: when [entry] is part of a
/// multi-selection the whole selection is deleted (Explorer/Finder behavior).
Future<void> showFileContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required FileEntry entry,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final scheme = Theme.of(context).colorScheme;
  final browser = context.read<FileBrowserService>();

  // Right-clicking an unselected row focuses it (and collapses any
  // multi-selection), mirroring system file managers.
  if (!browser.isSelected(entry.path)) {
    browser.selectSingle(entry);
  }
  final multiDelete =
      browser.isSelected(entry.path) && browser.selectionCount > 1;
  final deleteCount = multiDelete ? browser.selectionCount : 1;

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final action = await showMenu<_MenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    color: scheme.surface,
    elevation: 10,
    constraints: const BoxConstraints(minWidth: 220),
    items: [
      if (PreviewDialog.canPreview(entry))
        _item(_MenuAction.preview, Icons.visibility_outlined, l10n.menuPreview),
      _item(_MenuAction.rename, Icons.drive_file_rename_outline, l10n.rename),
      _item(
        _MenuAction.reveal,
        Icons.folder_open_outlined,
        l10n.menuRevealInFileManager,
      ),
      _item(
        _MenuAction.properties,
        Icons.info_outline_rounded,
        l10n.menuProperties,
      ),
      const PopupMenuDivider(),
      _item(
        _MenuAction.delete,
        Icons.delete_outline_rounded,
        multiDelete ? l10n.deleteSelectedCount(deleteCount) : l10n.delete,
        color: scheme.error,
      ),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _MenuAction.preview:
      await PreviewDialog.show(context, entry);
    case _MenuAction.rename:
      await _rename(context, entry);
    case _MenuAction.delete:
      await _delete(context, multiDelete ? browser.selectedEntries : [entry]);
    case _MenuAction.properties:
      await _showProperties(context, entry);
    case _MenuAction.reveal:
      await _revealInFileManager(context, entry);
  }
}

PopupMenuItem<_MenuAction> _item(
  _MenuAction value,
  IconData icon,
  String label, {
  Color? color,
}) {
  return PopupMenuItem<_MenuAction>(
    value: value,
    height: 42,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 13.5, color: color)),
      ],
    ),
  );
}

Future<void> _rename(BuildContext context, FileEntry entry) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final browser = context.read<FileBrowserService>();

  final newName = await showDialog<String>(
    context: context,
    builder: (_) => InputDialog(
      title: l10n.renameFile,
      labelText: l10n.newNameLabel,
      initialValue: entry.name,
      actionLabel: l10n.rename,
    ),
  );
  if (newName == null || newName.trim().isEmpty || newName == entry.name) {
    return;
  }

  try {
    final newPath = p.join(p.dirname(entry.path), newName.trim());
    if (entry.isDirectory) {
      await Directory(entry.path).rename(newPath);
    } else {
      await File(entry.path).rename(newPath);
    }
    browser.refresh();
    messenger.showSnackBar(
      SnackBar(content: Text('${entry.name} → ${newName.trim()}')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.errorRenaming(e.toString()))),
    );
  }
}

Future<void> _delete(BuildContext context, List<FileEntry> entries) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final browser = context.read<FileBrowserService>();
  final scheme = Theme.of(context).colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.delete),
      content: Text(
        entries.length == 1
            ? l10n.deleteConfirmOne(entries.first.name)
            : l10n.deleteConfirmMany(entries.length),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  var deleted = 0;
  String? firstError;
  for (final e in entries) {
    try {
      if (e.isDirectory) {
        await Directory(e.path).delete(recursive: true);
      } else {
        await File(e.path).delete();
      }
      deleted++;
    } catch (err) {
      firstError ??= err.toString();
    }
  }
  browser.clearSelection();
  browser.refresh();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        firstError == null
            ? l10n.deletedCount(deleted)
            : l10n.deleteFailed(firstError),
      ),
    ),
  );
}

Future<void> _showProperties(BuildContext context, FileEntry entry) async {
  final l10n = AppLocalizations.of(context)!;
  final label = FileLabelService.getLabel(entry.extension);
  final locale = Localizations.localeOf(context).toString();
  final modified = DateFormat.yMMMd(locale).add_Hm().format(entry.modified);

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      Widget row(String k, Widget v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(
                k,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(child: v),
          ],
        ),
      );
      Text value(String s) => Text(s, style: const TextStyle(fontSize: 13.5));

      return AlertDialog(
        title: Row(
          children: [
            Icon(
              FileLabelService.getIcon(label, entry.isDirectory),
              size: 20,
              color: FileLabelService.getIconColor(
                entry.isDirectory ? 'Folder' : label,
                entry.isDirectory,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(
                l10n.colType,
                value(
                  entry.isDirectory
                      ? l10n.typeFolder
                      : '${_localizedType(l10n, label)} (${entry.extension})',
                ),
              ),
              row(
                l10n.colSize,
                value(entry.isDirectory ? '—' : formatBytes(entry.size)),
              ),
              row(l10n.propModified, value(modified)),
              row(
                l10n.propPath,
                SelectableText(
                  entry.path,
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
        ],
      );
    },
  );
}

String _localizedType(AppLocalizations l10n, String label) => switch (label) {
  'Video' => l10n.typeVideo,
  'Subtitle' => l10n.typeSubtitle,
  'Image' => l10n.typeImage,
  'Metadata' => l10n.typeMetadata,
  'Audio' => l10n.typeAudio,
  'Text' => l10n.typeText,
  _ => l10n.typeOther,
};

/// Reveals [entry] in the OS file manager (selected in its parent folder).
Future<void> _revealInFileManager(BuildContext context, FileEntry entry) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (Platform.isWindows) {
      // `explorer /select,` exits with a non-zero code even on success, so
      // don't check the exit code — just fire it.
      await Process.start('explorer', ['/select,${entry.path}']);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', entry.path]);
    } else {
      // Linux: no portable "reveal", open the containing folder instead.
      await Process.start('xdg-open', [p.dirname(entry.path)]);
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.revealFailed)));
  }
}
