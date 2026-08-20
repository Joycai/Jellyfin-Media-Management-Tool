import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/organize_plan.dart';
import '../../services/file_label_service.dart';
import '../../utils/format.dart';
import '../../utils/path_tree.dart';
import '../glass/glass_dialog.dart';
import '../glass/glass_segmented.dart';
import 'edit_action_dialog.dart';
import 'rename_rule_dialog.dart';

/// What the user chose in the preview dialog.
typedef PreviewResult = ({bool apply, bool backup});

enum _View { tree, list, poster }

enum _Filter { changes, all, conflicts }

/// A before→after confirmation of an [OrganizePlan]: a two-pane tree diff of the
/// source folder versus the proposed Jellyfin structure, with move/rename/
/// conflict counts and an apply action.
///
/// This is also where the plan is edited. Rows in the list view can have their
/// target rewritten or a low-confidence proposal accepted, mutating [plan] in
/// place — the caller applies whatever the user confirms here.
class OrganizePreviewDialog extends StatefulWidget {
  final OrganizePlan plan;
  final String baseDir;
  final int totalBytes;

  const OrganizePreviewDialog({
    super.key,
    required this.plan,
    required this.baseDir,
    required this.totalBytes,
  });

  static Future<PreviewResult?> show(
    BuildContext context, {
    required OrganizePlan plan,
    required String baseDir,
    required int totalBytes,
  }) => showDialog<PreviewResult>(
    context: context,
    builder: (_) => OrganizePreviewDialog(
      plan: plan,
      baseDir: baseDir,
      totalBytes: totalBytes,
    ),
  );

  @override
  State<OrganizePreviewDialog> createState() => _OrganizePreviewDialogState();
}

class _OrganizePreviewDialogState extends State<OrganizePreviewDialog> {
  late _View _view;
  _Filter _filter = _Filter.changes;
  bool _backup = true;

  @override
  void initState() {
    super.initState();
    // Conflicts can only be resolved from the list view, so open there when the
    // plan has any — otherwise the user lands on a tree that shows the problem
    // without offering the fix.
    _view = _conflicts.isEmpty ? _View.tree : _View.list;
  }

  List<OrganizeAction> get _actions => widget.plan.actions;
  List<OrganizeAction> get _pending =>
      _actions.where((a) => a.status != ActionStatus.needsReview).toList();
  List<OrganizeAction> get _conflicts =>
      _actions.where((a) => a.status == ActionStatus.needsReview).toList();

  int get _renames => _actions
      .where((a) => p.basename(a.source) != p.basename(a.target))
      .length;
  int get _moves => _actions.length - _renames;

  int get _folderCount => _pending
      .map((a) => p.dirname(a.target))
      .where((d) => d.isNotEmpty && d != '.')
      .toSet()
      .length;

  int get _avgConfidencePct {
    if (_actions.isEmpty) return 0;
    final mean =
        _actions.map((a) => a.confidence).reduce((x, y) => x + y) /
        _actions.length;
    return (mean * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // The glass surface, not Material's tinted slab — see GlassDialogSurface.
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
        child: GlassDialogSurface(
          child: Column(
            children: [
              _header(context, l10n),
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              _toolbar(context, l10n),
              Expanded(child: _body(context, l10n)),
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              _footer(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.previewTitle(_actions.length),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // gen-l10n orders placeholders alphabetically: (folders, pct, size).
                  l10n.previewSubtitle(
                    _folderCount,
                    _avgConfidencePct,
                    formatBytes(widget.totalBytes, zero: '—'),
                  ),
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The dialog's core promise, stated where the eye lands first:
          // nothing here touches disk until Apply.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.secondary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.secondary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.previewDryRun,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Toolbar (view tabs · filters · counts) ─────────────────────────────────
  Widget _toolbar(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          // Flexible + Wrap rather than a rigid row: with the English strings
          // this cluster is wider than the dialog at its narrow end, and a
          // toolbar that overflows breaks the whole dialog's layout pass.
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GlassSegmented<_View>(
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                  items: [
                    GlassSegmentedItem(value: _View.tree, label: l10n.viewTree),
                    GlassSegmentedItem(value: _View.list, label: l10n.viewList),
                    GlassSegmentedItem(
                      value: _View.poster,
                      label: l10n.viewPoster,
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Text(
                  '${l10n.showOnly}:',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                _FilterChip(
                  label: l10n.filterChanges,
                  selected: _filter == _Filter.changes,
                  onTap: () => setState(() => _filter = _Filter.changes),
                ),
                _FilterChip(
                  label: l10n.filterAll,
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all),
                ),
                _FilterChip(
                  label: l10n.filterConflicts(_conflicts.length),
                  selected: _filter == _Filter.conflicts,
                  onTap: () => setState(() => _filter = _Filter.conflicts),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _count(context, Icons.add, scheme.primary, l10n.countMoves(_moves)),
          const SizedBox(width: 14),
          _count(
            context,
            Icons.drive_file_rename_outline,
            scheme.tertiary,
            l10n.countRenames(_renames),
          ),
          const SizedBox(width: 14),
          _count(
            context,
            Icons.warning_amber_rounded,
            const Color(0xFFE0A030),
            l10n.countConflicts(_conflicts.length),
          ),
        ],
      ),
    );
  }

  Widget _count(
    BuildContext context,
    IconData icon,
    Color color,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _body(BuildContext context, AppLocalizations l10n) {
    switch (_view) {
      case _View.poster:
        return _ComingSoon(label: l10n.viewPoster);
      case _View.list:
        if (_filteredActions.isEmpty) return _emptyFilter(context, l10n);
        return _ListDiff(
          actions: _filteredActions,
          onEdit: _editAction,
          onResolve: _resolveAction,
        );
      case _View.tree:
        final pending = _filter == _Filter.conflicts
            ? const <OrganizeAction>[]
            : _pending;
        // A blank pair of panes reads as a rendering bug, not as "the filter
        // matched nothing" — say so instead.
        if (pending.isEmpty && _conflicts.isEmpty) {
          return _emptyFilter(context, l10n);
        }
        return _TreeCompare(
          baseDir: widget.baseDir,
          pending: pending,
          conflicts: _conflicts,
        );
    }
  }

  Widget _emptyFilter(BuildContext context, AppLocalizations l10n) => Center(
    child: Text(
      l10n.previewFilterEmpty,
      style: TextStyle(
        fontSize: 13.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  List<OrganizeAction> get _filteredActions => switch (_filter) {
    _Filter.conflicts => _conflicts,
    _ => _actions,
  };

  // ── Editing ───────────────────────────────────────────────────────────────

  /// Video targets in the plan, so the subtitle rule can anchor to the episode
  /// it belongs with rather than to whatever happens to sit on disk.
  List<String> get _videoTargets => _actions
      .where((a) => FileLabelService.getLabel(p.extension(a.target)) == 'Video')
      .map((a) => a.target)
      .toList();

  Future<void> _editAction(OrganizeAction action) async {
    final target = await EditActionDialog.show(
      context,
      action: action,
      baseDir: widget.baseDir,
      videoTargets: _videoTargets,
    );
    if (target == null || target == action.target || !mounted) return;
    setState(() {
      action.target = target;
      action.userEdited = true;
      // The user just decided what this file should be called, so the
      // low-confidence flag is stale — leaving it would silently skip the very
      // row they came here to fix.
      if (action.status == ActionStatus.needsReview) {
        action.status = ActionStatus.pending;
      }
    });
  }

  /// Accepts a low-confidence proposal as-is, moving it out of the skip list.
  void _resolveAction(OrganizeAction action) =>
      setState(() => action.status = ActionStatus.pending);

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _footer(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Checkbox(
            value: _backup,
            onChanged: (v) => setState(() => _backup = v ?? true),
          ),
          const SizedBox(width: 2),
          // Expanded, not Flexible + Spacer: two flex children split the free
          // space between them, and the share a loose Flexible doesn't use is
          // forfeited — it piles up after the last child, so the buttons float
          // ~150px off the right edge. One Expanded label owns all the slack
          // and the buttons stay flush.
          Expanded(
            child: Text(
              l10n.recordUndoHistory,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => RenameRuleDialog.show(context),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: Text(l10n.previewAdjustRules),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, (apply: true, backup: _backup)),
            icon: const Icon(Icons.auto_awesome, size: 17),
            label: Text(l10n.applyOrganizeCount(_pending.length)),
          ),
        ],
      ),
    );
  }
}

// ── Tree compare ──────────────────────────────────────────────────────────────

class _TreeCompare extends StatelessWidget {
  final String baseDir;
  final List<OrganizeAction> pending;
  final List<OrganizeAction> conflicts;

  const _TreeCompare({
    required this.baseDir,
    required this.pending,
    required this.conflicts,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _TreePane(
            label: l10n.beforeLabel,
            path: baseDir,
            accent: const Color(0xFFE08A3C),
            lines: buildPathTree(pending.map((a) => a.source).toList()),
            conflicts: conflicts,
            isAfter: false,
          ),
        ),
        Container(
          width: 84,
          // The design separates the three zones with hairlines either side
          // of the arrow strip — without them the two trees read as one
          // continuous surface.
          decoration: BoxDecoration(
            border: Border.symmetric(
              vertical: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 14),
              RotatedBox(
                quarterTurns: 1,
                child: Text(
                  l10n.aiOrganizeVertical,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _TreePane(
            label: l10n.afterLabel,
            path: baseDir,
            accent: const Color(0xFF34A06B),
            lines: buildPathTree(pending.map((a) => a.target).toList()),
            conflicts: conflicts,
            isAfter: true,
          ),
        ),
      ],
    );
  }
}

class _TreePane extends StatelessWidget {
  final String label;
  final String path;
  final Color accent;
  final List<TreeLine> lines;
  final List<OrganizeAction> conflicts;
  final bool isAfter;

  const _TreePane({
    required this.label,
    required this.path,
    required this.accent,
    required this.lines,
    required this.conflicts,
    required this.isAfter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w700, color: accent),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Tooltip(
                  message: path,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in lines) _row(context, line),
          for (final c in conflicts) _conflictRow(context, c, l10n),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, TreeLine line) {
    final scheme = Theme.of(context).colorScheme;
    final isLeaf = !line.isDir;
    // The design highlights the *created* structure, not just its contents:
    // on the after side a top-level folder row gets the tint too, so the new
    // Jellyfin layout reads at a glance.
    final bg = isLeaf
        ? accent.withValues(alpha: 0.12)
        : (isAfter && line.depth <= 1)
        ? accent.withValues(alpha: 0.10)
        : Colors.transparent;
    return Container(
      margin: EdgeInsets.only(left: line.depth * 18.0, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Text(
            line.isDir ? '├' : '│',
            style: TextStyle(
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          if (line.isDir) Icon(Icons.folder_rounded, size: 15, color: accent),
          if (line.isDir) const SizedBox(width: 6),
          Flexible(
            child: Tooltip(
              message: line.isDir ? '${line.name}/' : line.name,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(
                line.isDir ? '${line.name}/' : line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: line.depth <= 1 && line.isDir
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: line.isDir && line.depth <= 1 && isAfter
                      ? accent
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictRow(
    BuildContext context,
    OrganizeAction c,
    AppLocalizations l10n,
  ) {
    const orange = Color(0xFFE0852C);
    final name = p.basename(isAfter ? c.target : c.source);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Text(
            isAfter ? '└ ?' : '└',
            style: const TextStyle(fontFamily: 'monospace', color: orange),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Tooltip(
              message: isAfter ? c.target : c.source,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(
                isAfter ? '$name · ${l10n.needsReviewSuffix}' : '$name ⚠',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: orange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── List diff ─────────────────────────────────────────────────────────────────

class _ListDiff extends StatelessWidget {
  final List<OrganizeAction> actions;
  final ValueChanged<OrganizeAction> onEdit;
  final ValueChanged<OrganizeAction> onResolve;

  const _ListDiff({
    required this.actions,
    required this.onEdit,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: actions.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.3),
      ),
      itemBuilder: (_, i) => _DiffRow(
        action: actions[i],
        onEdit: () => onEdit(actions[i]),
        onResolve: () => onResolve(actions[i]),
      ),
    );
  }
}

/// One `source → target` line. The row's controls fade in on hover so the list
/// stays readable, but stay reachable without hover on the conflicts that need
/// attention.
class _DiffRow extends StatefulWidget {
  final OrganizeAction action;
  final VoidCallback onEdit;
  final VoidCallback onResolve;

  const _DiffRow({
    required this.action,
    required this.onEdit,
    required this.onResolve,
  });

  @override
  State<_DiffRow> createState() => _DiffRowState();
}

class _DiffRowState extends State<_DiffRow> {
  static const _amber = Color(0xFFE0852C);
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final a = widget.action;
    final review = a.status == ActionStatus.needsReview;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(child: _path(a.source, color: scheme.onSurfaceVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  review ? Icons.help_outline : Icons.arrow_forward,
                  size: 16,
                  color: review ? _amber : scheme.primary,
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: _path(
                        a.target,
                        color: review ? _amber : scheme.onSurface,
                      ),
                    ),
                    if (a.userEdited) ...[
                      const SizedBox(width: 8),
                      _Badge(label: l10n.editedBadge, color: scheme.primary),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (review)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  color: _amber,
                  tooltip: l10n.markResolved,
                  onPressed: widget.onResolve,
                ),
              Opacity(
                opacity: _hover ? 1 : 0.28,
                child: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: l10n.edit,
                  onPressed: widget.onEdit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _path(String value, {required Color color}) => Tooltip(
    message: value,
    waitDuration: const Duration(milliseconds: 350),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: color),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  final String label;
  const _ComingSoon({required this.label});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 48,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '$label · ${l10n.comingSoon}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
