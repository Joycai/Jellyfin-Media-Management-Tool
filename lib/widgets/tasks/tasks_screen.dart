import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/organize/apply_controller.dart';
import '../../services/task_service.dart';
import '../../services/transfer/file_transfer.dart';
import '../../services/transfer/transfer_controller.dart';
import '../../theme/design_tokens.dart';
import '../../utils/format.dart';
import '../ai/organize_progress_screen.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';

/// 任务分区。列出所有分析 / 应用任务，倒序；应用任务带暂停 / 停止与「查看详情」。
///
/// 版式沿用 5.2「执行与日志」的语言：标题条 h48、总进度卡、语义色编码的状态角标。
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final tasks = context.watch<TaskService>();

    return Padding(
      padding: const EdgeInsets.all(AppSizes.contentPaddingH),
      child: GlassSurface(
        fill: t.cardFill,
        blur: t.blurPanel,
        saturate: true,
        borderRadius: BorderRadius.circular(AppRadii.panel + 2),
        border: Border.all(color: t.stroke),
        shadow: t.elevation.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: AppSizes.topBar,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.contentPaddingH,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.stroke)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 15, color: t.accent),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    l10n.tasksTitle,
                    style: AppTypeScale.title.copyWith(
                      fontSize: AppTypeScale.sizeBody,
                      color: t.textTitle,
                    ),
                  ),
                  if (tasks.runningCount > 0) ...[
                    const SizedBox(width: AppSpacing.md12),
                    _RunningPill(count: tasks.runningCount),
                  ],
                  const Spacer(),
                  if (tasks.tasks.any((t) => t.isFinished))
                    AppButton(
                      label: l10n.tasksClearFinished,
                      icon: Icons.delete_sweep_outlined,
                      kind: AppButtonKind.ghost,
                      height: AppSizes.controlSm,
                      onPressed: tasks.clearFinished,
                    ),
                ],
              ),
            ),
            Expanded(
              child: tasks.tasks.isEmpty
                  ? const _Empty()
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: tasks.tasks.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (_, i) => _TaskCard(task: tasks.tasks[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color: t.textMuted.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.tasksEmpty,
            style: AppTypeScale.title.copyWith(color: t.textTitle),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.tasksEmptyHint,
            style: AppTypeScale.caption.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RunningPill extends StatelessWidget {
  final int count;
  const _RunningPill({required this.count});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: AppSizes.controlXs,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.tiny),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: context.tokens.monoTiny.copyWith(
              fontWeight: FontWeight.w700,
              color: t.accentText,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final OrganizerTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    // Live-rebuild on the controller's tick when this is an apply task; for
    // analyze tasks the parent's TaskService.notifyListeners is enough.
    final live = task.controller ?? task.transfer;
    if (live == null) return _buildCard(context);
    return AnimatedBuilder(
      animation: live,
      builder: (_, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final controller = task.controller;

    final transfer = task.transfer;

    final progress =
        controller?.fraction ??
        transfer?.fraction ??
        task.progress ??
        (task.status == TaskStatus.done ? 1.0 : null);

    // 一屏最多两种语义色（1.1）：这里按任务**种类**而不是按状态取色，状态由
    // 右侧角标单独表达，否则一列混合任务会同时点亮四种色相。
    final (icon, accent) = switch (task.kind) {
      TaskKind.analyze => (Icons.auto_awesome, t.ai),
      TaskKind.apply => (Icons.drive_file_move_outlined, t.accent),
      TaskKind.scrape => (Icons.travel_explore_outlined, t.success),
      TaskKind.scrapeCommit => (Icons.sim_card_download_outlined, t.success),
      TaskKind.transfer => (
        transfer?.mode == TransferMode.copy
            ? Icons.file_copy_outlined
            : Icons.drive_file_move_outlined,
        t.accent,
      ),
    };

    final title = switch (task.kind) {
      TaskKind.analyze => l10n.tasksAnalyzeLabel(task.label),
      TaskKind.apply => l10n.tasksApplyLabel(task.label),
      TaskKind.scrape => l10n.tasksScrapeLabel(task.label),
      TaskKind.scrapeCommit => l10n.tasksScrapeCommitLabel(task.label),
      TaskKind.transfer =>
        transfer?.mode == TransferMode.copy
            ? l10n.tasksCopyLabel(task.label)
            : l10n.tasksMoveLabel(task.label),
    };

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: AppSpacing.md12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypeScale.bodyStrong.copyWith(
                        color: t.textTitle,
                      ),
                    ),
                    Text(
                      _statusLine(l10n, controller),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tokens.monoSmall.copyWith(
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(status: task.status, l10n: l10n),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: _ProgressBar(
              // A failed task shows an empty bar; anything else with no
              // fraction yet (analyze, a commit before its first download)
              // is indeterminate.
              value: task.status == TaskStatus.failed ? 0 : progress,
              color: task.status == TaskStatus.failed ? t.danger : accent,
              background: t.strokeStrong,
            ),
          ),
          if (task.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              task.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.caption.copyWith(color: t.dangerText),
            ),
          ],
          if (controller != null || task.isFinished || task.isCancellable) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                // Analyze tasks have no controller — their stop goes through
                // the task's cancel token instead.
                if (controller == null && task.isCancellable)
                  _SmallButton(
                    icon: Icons.stop_rounded,
                    label: l10n.stop,
                    onTap: () => context.read<TaskService>().cancel(task.id),
                  ),
                if (controller != null &&
                    controller.status == ApplyStatus.running)
                  _SmallButton(
                    icon: Icons.pause_rounded,
                    label: l10n.pause,
                    onTap: controller.pause,
                  ),
                if (controller != null &&
                    controller.status == ApplyStatus.paused)
                  _SmallButton(
                    icon: Icons.play_arrow_rounded,
                    label: l10n.resume,
                    onTap: controller.resume,
                  ),
                if (controller != null &&
                    task.status == TaskStatus.running) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _SmallButton(
                    icon: Icons.stop_rounded,
                    label: l10n.stop,
                    danger: true,
                    onTap: controller.stop,
                  ),
                ],
                if (controller != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _SmallButton(
                    icon: Icons.visibility_outlined,
                    label: l10n.tasksViewDetail,
                    onTap: () => _openDetail(context, controller),
                  ),
                ],
                const Spacer(),
                if (task.isFinished)
                  _SmallButton(
                    icon: Icons.close_rounded,
                    label: l10n.tasksDismiss,
                    onTap: () => context.read<TaskService>().dismiss(task.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _statusLine(AppLocalizations l10n, ApplyController? c) {
    if (task.kind == TaskKind.analyze) {
      switch (task.status) {
        case TaskStatus.running:
          return l10n.tasksAnalyzeRunning;
        case TaskStatus.done:
          return task.summary == null
              ? l10n.tasksAnalyzeDone
              : '${l10n.tasksAnalyzeDone} · ${task.summary}';
        case TaskStatus.failed:
          return l10n.tasksFailed;
        case TaskStatus.stopped:
          return l10n.statusStopped;
      }
    }
    if (c != null && task.status == TaskStatus.running) {
      return '${c.done}/${c.total}';
    }
    final tr = task.transfer;
    if (tr != null && task.status == TaskStatus.running) {
      return _transferLine(l10n, tr);
    }
    if (task.status == TaskStatus.failed) return l10n.tasksFailed;
    if (task.status == TaskStatus.stopped) return l10n.statusStopped;
    if (task.summary != null) return task.summary!;
    return '';
  }

  /// `1.2 GB / 4.8 GB · 3 min left` — bytes rather than items, because one
  /// item can be a 40 GB folder and a count would sit at 0/1 for an hour.
  String _transferLine(AppLocalizations l10n, TransferController tr) {
    final bytes =
        '${formatBytes(tr.bytesDone)} / ${formatBytes(tr.bytesTotal)}';
    final eta = tr.eta;
    if (eta == null || eta == Duration.zero) return bytes;
    return '$bytes · ${l10n.etaRemaining(eta.inMinutes, eta.inSeconds % 60)}';
  }

  Future<void> _openDetail(BuildContext context, ApplyController controller) {
    // The progress screen calls controller.start() in initState — that's a
    // no-op once started, so it's safe to re-open over a running task.
    return OrganizeProgressScreen.show(context, controller);
  }
}

/// A task's progress bar: animated between known fractions, indeterminate
/// when there is none.
///
/// The null case must not reach the tween. `TweenAnimationBuilder` evaluates
/// `Tween(end: null)` as `null as double`, which throws on the first frame —
/// and in a release build a throwing list item is painted as a grey error box
/// sized to fill the viewport, so one running analyze task blanked the whole
/// Tasks tab.
class _ProgressBar extends StatelessWidget {
  final double? value;
  final Color color;
  final Color background;

  const _ProgressBar({
    required this.value,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(double? v) => LinearProgressIndicator(
      value: v,
      minHeight: 4,
      backgroundColor: background,
      valueColor: AlwaysStoppedAnimation(color),
    );

    final target = value;
    if (target == null) return bar(null);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      // 进度条更新 240ms linear（1.4f）。
      duration: AppMotion.respecting(context, AppMotion.progress),
      curve: Curves.linear,
      builder: (context, v, _) => bar(v),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TaskStatus status;
  final AppLocalizations l10n;
  const _StatusBadge({required this.status, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (text, color) = switch (status) {
      TaskStatus.running => (l10n.tasksRunning, t.accent),
      TaskStatus.done => (l10n.tasksDone, t.success),
      TaskStatus.failed => (l10n.tasksFailed, t.danger),
      TaskStatus.stopped => (l10n.statusStopped, t.warning),
    };
    return AppTag(label: text, color: color);
  }
}

/// 行内小按钮：h24（1.3c）。
class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    icon: icon,
    height: AppSizes.controlXs,
    kind: danger ? AppButtonKind.danger : AppButtonKind.ghost,
    onPressed: onTap,
  );
}
