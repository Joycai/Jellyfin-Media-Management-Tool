import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/apply_controller.dart';
import '../../services/organize_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../glass/glass_panel.dart';

/// Live progress view shown while an organize plan is applied: an overall
/// progress card plus a terminal-style activity log, with pause/stop controls.
class OrganizeProgressScreen extends StatefulWidget {
  const OrganizeProgressScreen({super.key});

  /// Presents the screen, drives [controller] to completion, and returns the
  /// final result once the user closes it.
  static Future<ApplyResult> show(BuildContext context, ApplyController controller) async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: controller,
        child: const OrganizeProgressScreen(),
      ),
    ));
    return controller.result;
  }

  @override
  State<OrganizeProgressScreen> createState() => _OrganizeProgressScreenState();
}

class _OrganizeProgressScreenState extends State<OrganizeProgressScreen> {
  final _scroll = ScrollController();
  final Set<LogLevel> _levels = {LogLevel.info, LogLevel.warn, LogLevel.debug};

  /// Guards against stacking auto-scroll animations: the controller can tick
  /// many times per frame, and a fresh `animateTo` per tick chains animations
  /// that fight each other.
  bool _autoScrollPending = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ApplyController>();
    controller.addListener(_autoScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.start());
  }

  @override
  void dispose() {
    context.read<ApplyController>().removeListener(_autoScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// "Follow-tail" auto-scroll: only chases the log bottom when the user is
  /// already near it. If they've scrolled up to inspect a past line we leave
  /// them alone.
  void _autoScroll() {
    if (_autoScrollPending) return;
    _autoScrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollPending = false;
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels > 120) return;
      _scroll.animateTo(pos.maxScrollExtent,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final c = context.watch<ApplyController>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: glass.backdrop),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(c),
                const SizedBox(height: 18),
                _progressCard(c),
                const SizedBox(height: 18),
                Expanded(child: _logPanel(c)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(ApplyController c) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final running = c.status == ApplyStatus.running;
    final paused = c.status == ApplyStatus.paused;
    final finished = c.status == ApplyStatus.done || c.status == ApplyStatus.stopped;

    final (Color dot, String title) = switch (c.status) {
      ApplyStatus.running => (const Color(0xFF34C759), l10n.organizing(c.total)),
      ApplyStatus.paused => (const Color(0xFFE0A030), l10n.statusPaused),
      ApplyStatus.done => (const Color(0xFF34C759), l10n.statusDone),
      ApplyStatus.stopped => (scheme.onSurfaceVariant, l10n.statusStopped),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(width: 14),
          if (running && c.eta != null)
            Text(l10n.etaRemaining(c.eta!.inMinutes, c.eta!.inSeconds % 60),
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
          const Spacer(),
          if (finished)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check, size: 18),
              label: Text(l10n.doneClose),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: () => paused ? c.resume() : c.pause(),
              icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
              label: Text(paused ? l10n.resume : l10n.pause),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15)),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: c.stop,
              icon: const Icon(Icons.stop, size: 18),
              label: Text(l10n.stop),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error.withValues(alpha: 0.16),
                foregroundColor: scheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Progress card ──────────────────────────────────────────────────────────
  Widget _progressCard(ApplyController c) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return GlassPanel(
      radius: 22,
      elevated: true,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${c.done}', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1)),
                TextSpan(text: '/${c.total}',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              ])),
              const Spacer(),
              Text(
                '${formatBytes(c.bytesDone)} / ${formatBytes(c.bytesTotal)} · ${_speed(c.speedBytesPerSec)}',
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _bar(c.fraction),
          const SizedBox(height: 16),
          Row(
            children: [
              _legend(const Color(0xFF34C759), l10n.legendDone, c.done),
              const Spacer(),
              _legend(scheme.primary, l10n.legendInProgress, c.inProgress),
              const Spacer(),
              _legend(scheme.onSurfaceVariant, l10n.legendQueued, c.queued),
              const Spacer(),
              _legend(const Color(0xFFE0A030), l10n.legendSkipped, c.skipped),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(double fraction) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        children: [
          Container(height: 10, color: scheme.onSurface.withValues(alpha: 0.10)),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary, scheme.secondary]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('$label  ', style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
        Text('$count', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ── Activity log (terminal) ────────────────────────────────────────────────
  Widget _logPanel(ApplyController c) {
    final entries = c.log.where((e) => _levels.contains(e.level)).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _logHeader(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              itemCount: entries.length,
              itemBuilder: (_, i) => _logLine(entries[i], i == entries.length - 1 && c.status == ApplyStatus.running),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161A22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          for (final col in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)]) ...[
            Container(width: 11, height: 11, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 8),
          const Text('activity.log',
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF9AA4B2), fontWeight: FontWeight.w600)),
          const Spacer(),
          _levelPill('INFO', LogLevel.info, const Color(0xFF34C759)),
          const SizedBox(width: 6),
          _levelPill('WARN', LogLevel.warn, const Color(0xFFE0A030)),
          const SizedBox(width: 6),
          _levelPill('DEBUG', LogLevel.debug, const Color(0xFF8A93A2)),
        ],
      ),
    );
  }

  Widget _levelPill(String label, LogLevel level, Color color) {
    final on = _levels.contains(level);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () => setState(() => on ? _levels.remove(level) : _levels.add(level)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: on ? color : const Color(0xFF6B7280),
            )),
      ),
    );
  }

  Widget _logLine(LogEntry e, bool isLast) {
    final levelColor = switch (e.level) {
      LogLevel.info => const Color(0xFF34C759),
      LogLevel.warn => const Color(0xFFE0A030),
      LogLevel.debug => const Color(0xFF8A93A2),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.3),
          children: [
            TextSpan(text: '${_clock(e.time)} ', style: const TextStyle(color: Color(0xFF6B7280))),
            TextSpan(text: '${e.level.name.toUpperCase()} ', style: TextStyle(color: levelColor, fontWeight: FontWeight.w700)),
            TextSpan(text: _message(e), style: const TextStyle(color: Color(0xFFD3D8E0))),
            if (isLast) const TextSpan(text: ' ▌', style: TextStyle(color: Color(0xFF6B83F5))),
          ],
        ),
      ),
    );
  }

  String _message(LogEntry e) {
    final l10n = AppLocalizations.of(context)!;
    return switch (e.kind) {
      LogKind.started => l10n.logStarted(e.count),
      LogKind.moved => l10n.logMoved(e.dir, e.name), // alpha order: dir, name
      LogKind.skipped => l10n.logSkipped(e.name),
      LogKind.failed => l10n.logFailed(e.error, e.name), // alpha order: error, name
      LogKind.finished => l10n.logFinished(e.done, e.skipped),
      LogKind.stopped => l10n.logStopped(e.done, e.skipped),
    };
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  static String _speed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '—';
    return '${formatBytes(bytesPerSec.round())}/s';
  }
}
