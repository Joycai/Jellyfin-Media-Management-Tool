import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../services/file_browser_service.dart';
import '../../services/file_label_service.dart';
import '../../shortcuts/app_shortcuts.dart';
import '../../utils/format.dart';
import '../dialogs/input_dialog.dart';
import '../dialogs/preview_dialog.dart';
import '../glass/glass_dialog.dart';
import '../glass/glass_menu.dart';
import '../scrape/scrape_flow.dart';

enum _MenuAction {
  preview,
  scrape,
  rescrapeFolder,
  rename,
  delete,
  properties,
  reveal,
}

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

  final action = await showGlassMenu<_MenuAction>(
    context,
    globalPosition: globalPosition,
    items: [
      if (PreviewDialog.canPreview(entry))
        glassMenuItem(
          context,
          value: _MenuAction.preview,
          icon: Icons.visibility_outlined,
          label: l10n.menuPreview,
        ),
      // Single-entry only for now: batch scraping is a later phase, and the
      // per-host rate limit means a folder of 300 titles is a queue, not a
      // click.
      if (canScrape(entry))
        glassMenuItem(
          context,
          value: _MenuAction.scrape,
          icon: Icons.travel_explore_outlined,
          iconColor: scheme.primary,
          label: l10n.menuScrapeMetadata,
          trailing: shortcutLabel(AppShortcutId.scrape),
        ),
      // Folders only: the batch refresh re-reads the URL each NFO recorded,
      // so it needs a tree to walk.
      if (entry.isDirectory)
        glassMenuItem(
          context,
          value: _MenuAction.rescrapeFolder,
          icon: Icons.refresh_rounded,
          label: l10n.menuRescrapeFolder,
        ),
      const PopupMenuDivider(),
      glassMenuItem(
        context,
        value: _MenuAction.rename,
        icon: Icons.drive_file_rename_outline,
        label: l10n.rename,
        trailing: shortcutLabel(AppShortcutId.rename),
      ),
      glassMenuItem(
        context,
        value: _MenuAction.reveal,
        icon: Icons.folder_outlined,
        // The design codes this row by its subject: the amber of a folder
        // icon, the same hue the file table uses for folders.
        iconColor: const Color(0xFFE0A030),
        label: l10n.menuRevealInFileManager,
      ),
      glassMenuItem(
        context,
        value: _MenuAction.properties,
        icon: Icons.info_outline_rounded,
        label: l10n.menuProperties,
      ),
      const PopupMenuDivider(),
      glassMenuItem(
        context,
        value: _MenuAction.delete,
        icon: Icons.delete_outline_rounded,
        label: multiDelete
            ? l10n.deleteSelectedCount(deleteCount)
            : l10n.delete,
        color: scheme.error,
        trailing: shortcutLabel(AppShortcutId.delete),
      ),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _MenuAction.preview:
      await PreviewDialog.show(context, entry);
    case _MenuAction.scrape:
      await startScrapeFlow(
        context,
        target: entry,
        baseDir: browser.currentDirectory ?? p.dirname(entry.path),
      );
    case _MenuAction.rescrapeFolder:
      await startBatchScrapeFlow(context, dir: entry.path);
    case _MenuAction.rename:
      await renameEntry(context, entry);
    case _MenuAction.delete:
      await deleteEntries(
        context,
        multiDelete ? browser.selectedEntries : [entry],
      );
    case _MenuAction.properties:
      await _showProperties(context, entry);
    case _MenuAction.reveal:
      await _revealInFileManager(context, entry);
  }
}

/// Prompts for a new name and renames [entry] in place. Shared by the context
/// menu and the F2 shortcut.
Future<void> renameEntry(BuildContext context, FileEntry entry) async {
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

/// Confirms, then deletes every entry in [entries], reporting a count rather
/// than aborting on the first failure. Shared by the context menu and the
/// Delete shortcut. A no-op for an empty list.
Future<void> deleteEntries(
  BuildContext context,
  List<FileEntry> entries,
) async {
  if (entries.isEmpty) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final browser = context.read<FileBrowserService>();
  final scheme = Theme.of(context).colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => GlassAlertDialog(
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

      return GlassAlertDialog(
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
