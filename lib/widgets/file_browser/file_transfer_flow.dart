/// Copy / cut / paste / move for the file browser — the glue between the
/// context menu, the shortcuts and the footer bar on one side and
/// `planTransfer` → conflict dialog → `TransferController` on the other.
///
/// Every entry point here ends in one of two places: the clipboard (copy,
/// cut: nothing touches disk) or a transfer task (paste, move to…), which is
/// the only path that writes. A paste runs in the Tasks tab so a 40 GB season
/// has a progress bar and a Stop button instead of a frozen window.
library;

import 'dart:io' show FileSystemException;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../services/file_browser_service.dart';
import '../../services/file_label_service.dart';
import '../../services/history_service.dart';
import '../../services/task_service.dart';
import '../../services/transfer/file_clipboard.dart';
import '../../services/transfer/file_transfer.dart';
import '../../services/transfer/transfer_controller.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';

/// Puts [entries] on the clipboard as a copy. No-op for an empty list.
void copyEntries(BuildContext context, List<FileEntry> entries) {
  if (entries.isEmpty) return;
  final l10n = AppLocalizations.of(context)!;
  context.read<FileClipboard>().set(
    entries.map((e) => e.path),
    ClipboardMode.copy,
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.clipboardCopiedCount(entries.length))),
  );
}

/// Puts [entries] on the clipboard as a cut. The rows dim; nothing moves
/// until a paste.
void cutEntries(BuildContext context, List<FileEntry> entries) {
  if (entries.isEmpty) return;
  context.read<FileClipboard>().set(
    entries.map((e) => e.path),
    ClipboardMode.cut,
  );
}

/// Pastes the clipboard into [destinationDir]. A cut clears the clipboard
/// once the task starts (the entries are moving, so a second paste would
/// find nothing); a copy stays for pasting again elsewhere.
Future<void> pasteClipboard(
  BuildContext context, {
  required String destinationDir,
}) async {
  final clipboard = context.read<FileClipboard>();
  if (clipboard.isEmpty) return;
  final cut = clipboard.mode == ClipboardMode.cut;
  await _startTransfer(
    context,
    sources: clipboard.paths,
    destinationDir: destinationDir,
    mode: cut ? TransferMode.move : TransferMode.copy,
    onStarted: cut ? clipboard.clear : null,
  );
}

/// Asks for a destination folder, then moves [entries] there.
Future<void> moveEntriesTo(
  BuildContext context,
  List<FileEntry> entries,
) async {
  if (entries.isEmpty) return;
  final l10n = AppLocalizations.of(context)!;
  final browser = context.read<FileBrowserService>();
  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: l10n.moveToTitle,
    initialDirectory: browser.currentDirectory,
  );
  if (dir == null || !context.mounted) return;
  await _startTransfer(
    context,
    sources: entries.map((e) => e.path).toList(),
    destinationDir: dir,
    mode: TransferMode.move,
  );
}

Future<void> _startTransfer(
  BuildContext context, {
  required List<String> sources,
  required String destinationDir,
  required TransferMode mode,
  VoidCallback? onStarted,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final browser = context.read<FileBrowserService>();
  final tasks = context.read<TaskService>();
  final history = context.read<HistoryService>();

  final TransferPlan plan;
  try {
    plan = await planTransfer(
      sources: sources,
      destinationDir: destinationDir,
      mode: mode,
    );
  } on FileSystemException {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.transferDestinationMissing)),
    );
    return;
  }
  if (!context.mounted) return;

  // Refusals are reported whether or not something else goes ahead: a
  // paste that silently drops one of five items is how libraries lose files.
  final refusalNote = _describeRefusals(l10n, plan);
  if (plan.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(refusalNote ?? l10n.transferNothingToDo)),
    );
    return;
  }

  var policy = ConflictPolicy.keepBoth;
  if (plan.conflicts.isNotEmpty) {
    final chosen = await _showConflictDialog(context, plan);
    if (chosen == null) return;
    policy = chosen;
  }
  if (refusalNote != null) {
    messenger.showSnackBar(SnackBar(content: Text(refusalNote)));
  }

  final controller = TransferController(
    plan: plan,
    policy: policy,
    history: history,
  );
  onStarted?.call();
  tasks.startTransfer(
    controller: controller,
    label: p.basename(plan.destinationDir),
    onDone: (c) {
      browser.refresh();
      messenger.showSnackBar(SnackBar(content: Text(_summary(l10n, c))));
    },
  );
}

String? _describeRefusals(AppLocalizations l10n, TransferPlan plan) {
  if (plan.refused.isEmpty) return null;
  final counts = <TransferRefusal, int>{};
  for (final r in plan.refused) {
    counts[r.reason] = (counts[r.reason] ?? 0) + 1;
  }
  return [
    for (final e in counts.entries)
      switch (e.key) {
        TransferRefusal.missing => l10n.transferRefusedMissing(e.value),
        TransferRefusal.intoItself => l10n.transferRefusedIntoItself,
        TransferRefusal.sameFolder => l10n.transferRefusedSameFolder(e.value),
        TransferRefusal.link => l10n.transferRefusedLink(e.value),
        TransferRefusal.unreadable => l10n.transferRefusedUnreadable(e.value),
      },
  ].join(' · ');
}

/// Counts, not the first error — the batch convention.
String _summary(AppLocalizations l10n, TransferController c) {
  final r = c.result;
  if (r == null) return l10n.transferFailedCount(c.total);
  return [
    c.mode == TransferMode.copy
        ? l10n.transferCopiedCount(r.succeeded)
        : l10n.transferMovedCount(r.succeeded),
    if (r.failed > 0) l10n.transferFailedCount(r.failed),
    if (r.stopped) l10n.transferStopped(r.succeeded),
    if (c.undoError != null || c.undoUnavailable) l10n.transferNoUndo,
  ].join(' · ');
}

/// "N items already exist in `<folder>`" — the only question a paste asks.
/// Returns null on cancel.
Future<ConflictPolicy?> _showConflictDialog(
  BuildContext context,
  TransferPlan plan,
) {
  final l10n = AppLocalizations.of(context)!;
  final conflicts = plan.conflicts;
  return showGlassDialog<ConflictPolicy>(
    context: context,
    builder: (ctx) {
      final t = ctx.tokens;
      return GlassAlertDialog(
        // 30×30 tile with a 14px glyph: the Tasks card's icon tile, reused
        // here so the dialog reads as the same family (design canvas, conflict
        // dialog artboard).
        icon: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.warning.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          child: Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
        ),
        title: Text(
          l10n.transferConflictTitle(
            conflicts.length,
            p.basename(plan.destinationDir),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.transferConflictBody),
            const SizedBox(height: AppSpacing.md12),
            _ConflictList(conflicts: conflicts),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          AppButton(
            label: l10n.transferSkipExisting,
            onPressed: () => Navigator.pop(ctx, ConflictPolicy.skip),
          ),
          AppButton.primary(
            label: l10n.transferKeepBoth,
            onPressed: () => Navigator.pop(ctx, ConflictPolicy.keepBoth),
          ),
        ],
      );
    },
  );
}

/// The conflicting names, each with the numbered name keep-both would give
/// it, in the dialog's own scroll box past six rows.
class _ConflictList extends StatelessWidget {
  final List<TransferItem> conflicts;
  const _ConflictList({required this.conflicts});

  /// Rows before the list scrolls — enough to see what is at stake without
  /// the dialog growing past the table behind it.
  static const int _visibleRows = 6;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: BoxConstraints(
        maxHeight: AppSizes.menuItemHeight * _visibleRows + AppSpacing.xs * 2,
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: t.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.field),
        border: Border.all(color: t.stroke),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: conflicts.length,
        itemBuilder: (context, i) {
          final item = conflicts[i];
          final name = p.basename(item.target);
          final label = item.isDirectory
              ? 'Folder'
              : FileLabelService.getLabel(p.extension(name).toLowerCase());
          return SizedBox(
            height: AppSizes.menuItemHeight,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.md),
                // 14px glyph in a 30px row, per the conflict dialog artboard.
                Icon(
                  FileLabelService.getIcon(label, item.isDirectory),
                  size: 14,
                  color: FileLabelService.getIconColor(label, item.isDirectory),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.monoSmall.copyWith(color: t.textBody),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '→ ${numberedName(name, 2, isDirectory: item.isDirectory)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.monoTiny.copyWith(color: t.textMuted),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
            ),
          );
        },
      ),
    );
  }
}
