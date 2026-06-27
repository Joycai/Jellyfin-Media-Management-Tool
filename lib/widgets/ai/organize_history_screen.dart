import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/history_entry.dart';
import '../../services/history_service.dart';
import '../../theme/app_theme.dart';

/// Operation history: a vertical list of recorded operations with undo +
/// "view list" affordances, plus a 7-day retention notice.
class OrganizeHistoryScreen extends StatefulWidget {
  const OrganizeHistoryScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const OrganizeHistoryScreen()),
      );

  @override
  State<OrganizeHistoryScreen> createState() => _OrganizeHistoryScreenState();
}

class _OrganizeHistoryScreenState extends State<OrganizeHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryService>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final history = context.watch<HistoryService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: glass.backdrop),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, l10n),
              Expanded(
                child: history.entries.isEmpty
                    ? _empty(context, l10n)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        itemCount: history.entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _HistoryCard(entry: history.entries[i]),
                      ),
              ),
              if (history.entries.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0A030).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0A030).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE0A030)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(l10n.historyUndoFootnote,
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 24, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Text(l10n.historyTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(l10n.historyRetention(HistoryService.retentionDays),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 56, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(l10n.historyEmpty, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            glass.panelFill,
            Color.lerp(glass.panelFill, scheme.primary, 0.05) ?? glass.panelFill,
          ],
        ),
        border: Border.all(color: glass.panelStroke),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KindBadge(kind: entry.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title(l10n),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_subtitle(l10n),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_relativeTime(l10n, entry.createdAt),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
          if (entry.canUndo) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _UndoButton(entry: entry),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showMoves(context, entry, l10n),
                  icon: const Icon(Icons.list_alt_outlined, size: 16),
                  label: Text(l10n.viewList),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    side: BorderSide(color: glass.panelStroke),
                    foregroundColor: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _title(AppLocalizations l10n) => switch (entry.kind) {
        HistoryKind.aiOrganize => l10n.historyTitleAi(entry.itemCount),
        HistoryKind.manualRename => l10n.historyTitleManual(entry.itemCount),
        HistoryKind.metadataRefresh => l10n.historyTitleMetadata,
        HistoryKind.batchImport => l10n.historyTitleImport(entry.itemCount),
      };

  String _subtitle(AppLocalizations l10n) {
    final parts = <String>[];
    if (entry.moveCount > 0) parts.add(l10n.subMoves(entry.moveCount));
    if (entry.renameCount > 0) parts.add(l10n.subRenames(entry.renameCount));
    if (entry.totalBytes > 0) parts.add(_bytes(entry.totalBytes));
    return parts.isEmpty ? entry.baseDir : parts.join(' · ');
  }

  static String _bytes(int b) {
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    double s = b.toDouble();
    int i = 0;
    while (s >= 1024 && i < u.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(s >= 100 || i <= 1 ? 0 : 1)} ${u[i]}';
  }

  static String _relativeTime(AppLocalizations l10n, DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return l10n.timeJustNow;
    if (diff.inHours < 1) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) {
      return l10n.timeToday('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
    if (diff.inDays < 2) return l10n.timeYesterday;
    return l10n.timeDaysAgo(diff.inDays);
  }

  Future<void> _showMoves(BuildContext context, HistoryEntry entry, AppLocalizations l10n) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MovesDialog(entry: entry),
    );
  }
}

class _UndoButton extends StatefulWidget {
  final HistoryEntry entry;
  const _UndoButton({required this.entry});

  @override
  State<_UndoButton> createState() => _UndoButtonState();
}

class _UndoButtonState extends State<_UndoButton> {
  bool _busy = false;

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final history = context.read<HistoryService>();
    setState(() => _busy = true);
    final result = await history.undo(widget.entry);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(result.hasFailures
          ? l10n.undoPartial(result.failures.length, result.succeeded)
          : l10n.undoDone(result.succeeded)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const orange = Color(0xFFE0852C);
    return OutlinedButton.icon(
      onPressed: _busy ? null : _undo,
      icon: _busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: orange))
          : const Icon(Icons.undo_rounded, size: 16),
      label: Text(l10n.undoAction),
      style: OutlinedButton.styleFrom(
        foregroundColor: orange,
        side: const BorderSide(color: orange),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final HistoryKind kind;
  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final (Color a, Color b, IconData icon) = switch (kind) {
      HistoryKind.aiOrganize => (const Color(0xFF6F69FF), const Color(0xFFA56BFF), Icons.auto_awesome),
      HistoryKind.manualRename => (const Color(0xFF5A6173), const Color(0xFF7E8497), Icons.drive_file_rename_outline),
      HistoryKind.metadataRefresh => (const Color(0xFF3B82F6), const Color(0xFF60A5FA), Icons.sync_rounded),
      HistoryKind.batchImport => (const Color(0xFF6F69FF), const Color(0xFFA56BFF), Icons.cloud_download_outlined),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _MovesDialog extends StatelessWidget {
  final HistoryEntry entry;
  const _MovesDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(l10n.movesListTitle(entry.moves.length),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: entry.moves.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  itemBuilder: (_, i) {
                    final m = entry.moves[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.basename(m['from']!),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(Icons.subdirectory_arrow_right, size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(p.relative(m['to']!, from: entry.baseDir),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: scheme.onSurface)),
                            ),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
