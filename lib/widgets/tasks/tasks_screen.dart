import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/apply_controller.dart';
import '../../services/task_service.dart';
import '../ai/organize_progress_screen.dart';
import '../glass/glass_panel.dart';

/// The body shown when the user picks the Tasks tab. Lists every analyze /
/// apply task in reverse-chronological order; apply tasks expose pause/stop
/// and a "view details" entry that re-opens the live progress screen.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tasks = context.watch<TaskService>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GlassPanel(
        radius: 24,
        elevated: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 18, 14),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 22, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    l10n.tasksTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (tasks.runningCount > 0)
                    _RunningPill(count: tasks.runningCount),
                  const Spacer(),
                  if (tasks.tasks.any((t) => t.isFinished))
                    TextButton.icon(
                      onPressed: () => tasks.clearFinished(),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(l10n.tasksClearFinished),
                    ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Expanded(
              child: tasks.tasks.isEmpty
                  ? _Empty(l10n: l10n, scheme: scheme)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      itemCount: tasks.tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
  final AppLocalizations l10n;
  final ColorScheme scheme;
  const _Empty({required this.l10n, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.tasksEmpty,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.tasksEmptyHint,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
    final scheme = Theme.of(context).colorScheme;
    // Live-rebuild on the controller's tick when this is an apply task; for
    // analyze tasks the parent's TaskService.notifyListeners is enough.
    final controller = task.controller;
    if (controller == null) {
      return _buildCard(context, scheme);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => _buildCard(context, scheme),
    );
  }

  Widget _buildCard(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
    final isAnalyze = task.kind == TaskKind.analyze;
    final controller = task.controller;

    final progress = controller != null
        ? controller.fraction
        : (task.status == TaskStatus.done ? 1.0 : null);

    final (icon, accent) = switch ((task.kind, task.status)) {
      (TaskKind.analyze, TaskStatus.running) => (
        Icons.auto_awesome,
        scheme.primary,
      ),
      (TaskKind.analyze, _) => (Icons.auto_awesome, const Color(0xFF8B5CF6)),
      (TaskKind.apply, _) => (
        Icons.drive_file_move_outlined,
        const Color(0xFF22C9A9),
      ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAnalyze
                          ? l10n.tasksAnalyzeLabel(task.label)
                          : l10n.tasksApplyLabel(task.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(l10n, controller),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: task.status, accent: accent, l10n: l10n),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: task.status == TaskStatus.failed ? 0 : progress,
              minHeight: 6,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(
                task.status == TaskStatus.failed ? scheme.error : accent,
              ),
            ),
          ),
          if (task.error != null) ...[
            const SizedBox(height: 10),
            Text(
              task.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          if (controller != null || task.isFinished || task.isCancellable) ...[
            const SizedBox(height: 10),
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
                  const SizedBox(width: 8),
                  _SmallButton(
                    icon: Icons.stop_rounded,
                    label: l10n.stop,
                    onTap: controller.stop,
                  ),
                ],
                if (controller != null) ...[
                  const SizedBox(width: 8),
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
    if (task.summary != null) return task.summary!;
    return '';
  }

  Future<void> _openDetail(BuildContext context, ApplyController controller) {
    // The progress screen calls controller.start() in initState — that's a
    // no-op once started, so it's safe to re-open over a running task.
    return OrganizeProgressScreen.show(context, controller);
  }
}

class _StatusBadge extends StatelessWidget {
  final TaskStatus status;
  final Color accent;
  final AppLocalizations l10n;
  const _StatusBadge({
    required this.status,
    required this.accent,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (status) {
      TaskStatus.running => (l10n.tasksRunning, accent),
      TaskStatus.done => (l10n.tasksDone, const Color(0xFF34C759)),
      TaskStatus.failed => (l10n.tasksFailed, scheme.error),
      TaskStatus.stopped => (l10n.statusStopped, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: scheme.onSurface),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
