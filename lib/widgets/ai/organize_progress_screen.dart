import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/apply_controller.dart';
import '../../services/organize_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/format.dart';
import '../shell/app_shell.dart';
import '../shell/secondary_title_bar.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';

/// Live progress view shown while an organize plan is applied: an overall
/// progress card plus a terminal-style activity log, with pause/stop controls.
class OrganizeProgressScreen extends StatefulWidget {
  const OrganizeProgressScreen({super.key});

  /// Presents the screen, drives [controller] to completion, and returns the
  /// final result once the user closes it.
  static Future<ApplyResult> show(
    BuildContext context,
    ApplyController controller,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChangeNotifierProvider.value(
          value: controller,
          child: const OrganizeProgressScreen(),
        ),
      ),
    );
    return controller.result;
  }

  @override
  State<OrganizeProgressScreen> createState() => _OrganizeProgressScreenState();
}

class _OrganizeProgressScreenState extends State<OrganizeProgressScreen> {
  final _scroll = ScrollController();
  final Set<LogLevel> _levels = {LogLevel.info, LogLevel.warn, LogLevel.debug};

  /// The level-filtered log, appended to as entries arrive.
  ///
  /// This used to be rebuilt inside `build` from the controller's whole log,
  /// which copied it twice per frame -- once for the unmodifiable snapshot, once
  /// for `.where().toList()` -- at up to 20 rebuilds a second, on a list that
  /// grows by one entry per action. A 10k-action job spent ~400k element copies
  /// a second drawing a terminal.
  final List<LogEntry> _visible = [];

  /// Absolute log index [_visible] is synced up to.
  int _syncedTo = 0;

  /// Guards against stacking auto-scroll animations: the controller can tick
  /// many times per frame, and a fresh `animateTo` per tick chains animations
  /// that fight each other.
  bool _autoScrollPending = false;

  /// Held from [initState] because [dispose] runs after this element has been
  /// deactivated, and an ancestor lookup from there throws ("Looking up a
  /// deactivated widget's ancestor is unsafe"). Reading the provider once up
  /// front is also what keeps the listener removal pointed at the same
  /// controller the listener was added to.
  late final ApplyController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<ApplyController>();
    _controller.addListener(_autoScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.start());
  }

  @override
  void dispose() {
    _controller.removeListener(_autoScroll);
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
      _scroll.animateTo(
        pos.maxScrollExtent,
        duration: AppMotion.panel,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.watch<ApplyController>();

    return Scaffold(
      // 整页路由盖住主顶栏，窗口按钮与拖拽区必须由这一条带回来。
      body: AppShell(
        titleBar: SecondaryTitleBar(
          backLabel: l10n.back,
          onBack: () => Navigator.of(context).pop(),
          title: _title(c, l10n),
          subtitle: c.status == ApplyStatus.running && c.eta != null
              ? l10n.etaRemaining(c.eta!.inMinutes, c.eta!.inSeconds % 60)
              : null,
          actions: _controls(c, l10n),
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSizes.contentPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _progressCard(c),
              const SizedBox(height: AppSpacing.lg),
              Expanded(child: _logPanel(c)),
            ],
          ),
        ),
      ),
    );
  }

  String _title(ApplyController c, AppLocalizations l10n) => switch (c.status) {
    ApplyStatus.running => l10n.organizing(c.total),
    ApplyStatus.paused => l10n.statusPaused,
    ApplyStatus.done => l10n.statusDone,
    ApplyStatus.stopped => l10n.statusStopped,
  };

  /// 5.3 把暂停 / 停止放在标题条右侧，正文里只剩进度与日志。
  List<Widget> _controls(ApplyController c, AppLocalizations l10n) {
    final paused = c.status == ApplyStatus.paused;
    final finished =
        c.status == ApplyStatus.done || c.status == ApplyStatus.stopped;
    if (finished) {
      return [
        AppButton.primary(
          label: l10n.doneClose,
          icon: Icons.check_rounded,
          height: AppSizes.controlSm,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.md12),
      ];
    }
    return [
      AppButton(
        label: paused ? l10n.resume : l10n.pause,
        icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        height: AppSizes.controlSm,
        onPressed: () => paused ? c.resume() : c.pause(),
      ),
      const SizedBox(width: AppSpacing.xs),
      AppButton(
        label: l10n.stop,
        icon: Icons.stop_rounded,
        kind: AppButtonKind.danger,
        height: AppSizes.controlSm,
        onPressed: c.stop,
      ),
      const SizedBox(width: AppSpacing.md12),
    ];
  }

  // ── Progress card ──────────────────────────────────────────────────────────
  Widget _progressCard(ApplyController c) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final t = context.tokens;
    return GlassSurface(
      fill: t.cardFill,
      blur: t.blurPanel,
      borderRadius: BorderRadius.circular(AppRadii.panel),
      border: Border.all(color: t.stroke),
      shadow: t.elevation.card,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${c.done}',
                      style: const TextStyle(
                        fontSize: AppTypeScale.sizeDisplay,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: '/${c.total}',
                      style: TextStyle(
                        fontSize: AppTypeScale.sizeHeading,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${formatBytes(c.bytesDone)} / ${formatBytes(c.bytesTotal)} · ${_speed(c.speedBytesPerSec)}',
                style: TextStyle(
                  fontSize: AppTypeScale.sizeTitle,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _bar(c.fraction),
          const SizedBox(height: 16),
          Row(
            children: [
              _legend(AppPalette.success, l10n.legendDone, c.done),
              const Spacer(),
              _legend(scheme.primary, l10n.legendInProgress, c.inProgress),
              const Spacer(),
              _legend(scheme.onSurfaceVariant, l10n.legendQueued, c.queued),
              const Spacer(),
              _legend(AppPalette.warning, l10n.legendSkipped, c.skipped),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(double fraction) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: Stack(
        children: [
          Container(
            height: 10,
            color: scheme.onSurface.withValues(alpha: 0.10),
          ),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary, scheme.secondary],
                ),
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
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '$label  ',
          style: TextStyle(
            fontSize: AppTypeScale.sizeBody,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: AppTypeScale.sizeBody,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Activity log (terminal) ────────────────────────────────────────────────
  /// Appends whatever the controller logged since the last call.
  ///
  /// Cheap enough to call from `build`: after the first sync it walks only the
  /// entries that arrived. A trim at the front of the controller's log is
  /// detected through [ApplyController.logStart], so dropped indices are never
  /// re-read as if they were still there.
  void _syncLog(ApplyController c) {
    if (_syncedTo < c.logStart) {
      _visible.clear();
      _syncedTo = c.logStart;
    }
    for (var i = _syncedTo; i < c.logLength; i++) {
      final entry = c.logAt(i);
      if (_levels.contains(entry.level)) _visible.add(entry);
    }
    _syncedTo = c.logLength;
  }

  Widget _logPanel(ApplyController c) {
    _syncLog(c);
    final entries = _visible;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.terminalBase,
        borderRadius: BorderRadius.circular(AppRadii.panel),
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
              itemBuilder: (_, i) => _logLine(
                entries[i],
                i == entries.length - 1 && c.status == ApplyStatus.running,
              ),
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
        color: AppPalette.terminalChrome,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          for (final col in const [
            AppPalette.macClose,
            AppPalette.macMinimize,
            AppPalette.macZoom,
          ]) ...[
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: col, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 8),
          const Text(
            'activity.log',
            style: TextStyle(
              fontFamily: AppTypeScale.mono,
              fontFamilyFallback: AppTypeScale.monoFallback,
              fontSize: AppTypeScale.sizeBody,
              color: AppPalette.onTerminalMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _levelPill('INFO', LogLevel.info, AppPalette.success),
          const SizedBox(width: 6),
          _levelPill('WARN', LogLevel.warn, AppPalette.warning),
          const SizedBox(width: 6),
          _levelPill('DEBUG', LogLevel.debug, _debugLevel),
        ],
      ),
    );
  }

  /// 日志面板在**两套主题里都是深色**（5.3），所以它内部的文字色不能跟着
  /// 主题走 —— 浅色主题下的 ink 墨色压在这块深底上就看不见了。这两个常量是
  /// 这块终端自己的中性档。
  static const _debugLevel = AppPalette.onTerminalMuted;
  static const _mutedOnTerminal = AppPalette.onTerminalFaint;

  Widget _levelPill(String label, LogLevel level, Color color) {
    final on = _levels.contains(level);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.button),
      onTap: () => setState(() {
        if (on) {
          _levels.remove(level);
        } else {
          _levels.add(level);
        }
        // The filter itself changed, so the synced view is stale in both
        // directions -- entries it dropped may now qualify and vice versa.
        // Rewind the cursor and let the next _syncLog rebuild from what the
        // controller still retains.
        _visible.clear();
        _syncedTo = 0;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypeScale.mono,
            fontFamilyFallback: AppTypeScale.monoFallback,
            fontSize: AppTypeScale.sizeCaption,
            fontWeight: FontWeight.w700,
            color: on ? color : _mutedOnTerminal,
          ),
        ),
      ),
    );
  }

  Widget _logLine(LogEntry e, bool isLast) {
    final levelColor = switch (e.level) {
      LogLevel.info => AppPalette.success,
      LogLevel.warn => AppPalette.warning,
      LogLevel.debug => _debugLevel,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: AppTypeScale.mono,
            fontFamilyFallback: AppTypeScale.monoFallback,
            fontSize: AppTypeScale.sizeBody,
            height: 1.3,
          ),
          children: [
            TextSpan(
              text: '${_clock(e.time)} ',
              style: const TextStyle(color: _mutedOnTerminal),
            ),
            TextSpan(
              text: '${e.level.name.toUpperCase()} ',
              style: TextStyle(color: levelColor, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: _message(e),
              style: const TextStyle(color: AppPalette.onTerminal),
            ),
            if (isLast)
              const TextSpan(
                text: ' ▌',
                style: TextStyle(color: AppPalette.accent),
              ),
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
      LogKind.failed => l10n.logFailed(
        e.error,
        e.name,
      ), // alpha order: error, name
      LogKind.finished => l10n.logFinished(e.done, e.skipped),
      LogKind.stopped => l10n.logStopped(e.done, e.skipped),
      LogKind.undoLost => l10n.logUndoLost(e.error),
    };
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  static String _speed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '—';
    return '${formatBytes(bytesPerSec.round())}/s';
  }
}
