import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/organize_plan.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/path_tree.dart';

/// What the user chose in the preview dialog.
typedef PreviewResult = ({bool apply, bool backup});

enum _View { tree, list, poster }

enum _Filter { changes, all, conflicts }

/// A before→after confirmation of an [OrganizePlan]: a two-pane tree diff of the
/// source folder versus the proposed Jellyfin structure, with move/rename/
/// conflict counts and an apply action.
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
  }) =>
      showDialog<PreviewResult>(
        context: context,
        builder: (_) => OrganizePreviewDialog(plan: plan, baseDir: baseDir, totalBytes: totalBytes),
      );

  @override
  State<OrganizePreviewDialog> createState() => _OrganizePreviewDialogState();
}

class _OrganizePreviewDialogState extends State<OrganizePreviewDialog> {
  _View _view = _View.tree;
  _Filter _filter = _Filter.changes;
  bool _backup = true;

  List<OrganizeAction> get _actions => widget.plan.actions;
  List<OrganizeAction> get _pending =>
      _actions.where((a) => a.status != ActionStatus.needsReview).toList();
  List<OrganizeAction> get _conflicts =>
      _actions.where((a) => a.status == ActionStatus.needsReview).toList();

  int get _renames =>
      _actions.where((a) => p.basename(a.source) != p.basename(a.target)).length;
  int get _moves => _actions.length - _renames;

  int get _folderCount =>
      _pending.map((a) => p.dirname(a.target)).where((d) => d.isNotEmpty && d != '.').toSet().length;

  int get _avgConfidencePct {
    if (_actions.isEmpty) return 0;
    final mean = _actions.map((a) => a.confidence).reduce((x, y) => x + y) / _actions.length;
    return (mean * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
        child: Column(
          children: [
            _header(context, l10n),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _toolbar(context, l10n),
            Expanded(child: _body(context, l10n)),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _footer(context, l10n),
          ],
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
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.previewTitle(_actions.length),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  // gen-l10n orders placeholders alphabetically: (folders, pct, size).
                  l10n.previewSubtitle(_folderCount, _avgConfidencePct, formatBytes(widget.totalBytes, zero: '—')),
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
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
          _Segmented<_View>(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            items: [
              (_View.tree, l10n.viewTree),
              (_View.list, l10n.viewList),
              (_View.poster, l10n.viewPoster),
            ],
          ),
          const SizedBox(width: 20),
          Text('${l10n.showOnly}:', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          _FilterChip(label: l10n.filterChanges, selected: _filter == _Filter.changes, onTap: () => setState(() => _filter = _Filter.changes)),
          const SizedBox(width: 6),
          _FilterChip(label: l10n.filterAll, selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
          const SizedBox(width: 6),
          _FilterChip(label: l10n.filterConflicts(_conflicts.length), selected: _filter == _Filter.conflicts, onTap: () => setState(() => _filter = _Filter.conflicts)),
          const Spacer(),
          _count(context, Icons.add, scheme.primary, l10n.countMoves(_moves)),
          const SizedBox(width: 14),
          _count(context, Icons.drive_file_rename_outline, scheme.tertiary, l10n.countRenames(_renames)),
          const SizedBox(width: 14),
          _count(context, Icons.warning_amber_rounded, const Color(0xFFE0A030), l10n.countConflicts(_conflicts.length)),
        ],
      ),
    );
  }

  Widget _count(BuildContext context, IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _body(BuildContext context, AppLocalizations l10n) {
    switch (_view) {
      case _View.poster:
        return _ComingSoon(label: l10n.viewPoster);
      case _View.list:
        return _ListDiff(actions: _filteredActions);
      case _View.tree:
        return _TreeCompare(
          baseDir: widget.baseDir,
          pending: _filter == _Filter.conflicts ? const [] : _pending,
          conflicts: _filter == _Filter.changes || _filter == _Filter.all || _filter == _Filter.conflicts ? _conflicts : const [],
        );
    }
  }

  List<OrganizeAction> get _filteredActions => switch (_filter) {
        _Filter.conflicts => _conflicts,
        _ => _actions,
      };

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _footer(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Checkbox(value: _backup, onChanged: (v) => setState(() => _backup = v ?? true)),
          const SizedBox(width: 2),
          Flexible(
            child: Text(l10n.recordUndoHistory,
                style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, (apply: true, backup: _backup)),
            icon: const Icon(Icons.auto_awesome, size: 17),
            label: Text(l10n.applyOrganizeCount(_pending.length)),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
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

  const _TreeCompare({required this.baseDir, required this.pending, required this.conflicts});

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
        SizedBox(
          width: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 14),
              RotatedBox(
                quarterTurns: 1,
                child: Text(l10n.aiOrganizeVertical,
                    style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: scheme.onSurfaceVariant)),
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
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: accent)),
              const SizedBox(width: 10),
              Flexible(
                child: Tooltip(
                  message: path,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: scheme.onSurfaceVariant)),
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
    final bg = isLeaf ? accent.withValues(alpha: 0.12) : Colors.transparent;
    return Container(
      margin: EdgeInsets.only(left: line.depth * 18.0, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Row(
        children: [
          Text(line.isDir ? '├' : '│', style: TextStyle(fontFamily: 'monospace', color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
          const SizedBox(width: 8),
          if (line.isDir)
            Icon(Icons.folder_rounded, size: 15, color: accent),
          if (line.isDir) const SizedBox(width: 6),
          Flexible(
            child: Tooltip(
              message: line.isDir ? '${line.name}/' : line.name,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(line.isDir ? '${line.name}/' : line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: line.depth <= 1 && line.isDir ? FontWeight.w700 : FontWeight.w400,
                    color: line.isDir && line.depth <= 1 && isAfter ? accent : null,
                  )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictRow(BuildContext context, OrganizeAction c, AppLocalizations l10n) {
    const orange = Color(0xFFE0852C);
    final name = p.basename(isAfter ? c.target : c.source);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Text(isAfter ? '└ ?' : '└', style: const TextStyle(fontFamily: 'monospace', color: orange)),
          const SizedBox(width: 8),
          Flexible(
            child: Tooltip(
              message: isAfter ? c.target : c.source,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(
                isAfter ? '$name · ${l10n.needsReviewSuffix}' : '$name ⚠',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: orange),
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
  const _ListDiff({required this.actions});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: actions.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
      itemBuilder: (_, i) {
        final a = actions[i];
        final review = a.status == ActionStatus.needsReview;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: a.source,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(a.source,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(review ? Icons.help_outline : Icons.arrow_forward,
                    size: 16, color: review ? const Color(0xFFE0852C) : scheme.primary),
              ),
              Expanded(
                child: Tooltip(
                  message: a.target,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(a.target,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace', fontSize: 13,
                        color: review ? const Color(0xFFE0852C) : scheme.onSurface,
                      )),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Shared bits ───────────────────────────────────────────────────────────────

class _Segmented<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final List<(T, String)> items;
  const _Segmented({required this.value, required this.onChanged, required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in items)
            Material(
              color: v == value ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                        color: v == value ? scheme.onSurface : scheme.onSurfaceVariant,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              )),
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
          Icon(Icons.image_outlined, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('$label · ${l10n.comingSoon}', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
