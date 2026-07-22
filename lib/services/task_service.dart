import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/organize_plan.dart';
import '../utils/ids.dart';
import 'ai/ai_cancel_token.dart';
import 'ai_service.dart';
import 'apply_controller.dart';

/// What kind of work a [OrganizerTask] is doing.
enum TaskKind {
  /// AI is analyzing a folder to produce an `OrganizePlan`.
  analyze,

  /// The user-confirmed plan is being moved/renamed on disk.
  apply,
}

enum TaskStatus { running, done, failed, stopped }

/// One unit of background work shown in the Tasks tab. Analyze tasks just hold
/// metadata; apply tasks carry the live [ApplyController] so the UI can render
/// real-time progress without polling the service.
class OrganizerTask {
  final String id;
  final TaskKind kind;

  /// Display label — folder basename or similar. Stays stable across the
  /// task's lifetime.
  final String label;

  /// Started time for relative-time rendering.
  final DateTime startedAt;

  /// Apply-only: the controller actually running the move loop. Watch it for
  /// live progress; pause/stop go through it directly.
  final ApplyController? controller;

  /// Analyze-only: aborts the folder walk and the in-flight model request.
  final AiCancelToken? cancelToken;

  TaskStatus status;
  DateTime? finishedAt;

  /// Short summary line shown after completion ("整理 22 项 · 1.2 GB").
  String? summary;

  /// Error message when [status] == failed.
  String? error;

  OrganizerTask({
    required this.id,
    required this.kind,
    required this.label,
    required this.startedAt,
    this.controller,
    this.cancelToken,
    this.status = TaskStatus.running,
    this.finishedAt,
    this.summary,
    this.error,
  });

  bool get isFinished => status != TaskStatus.running;

  /// Whether the user can stop this task where it currently stands.
  bool get isCancellable =>
      status == TaskStatus.running &&
      (cancelToken != null || controller != null);
}

/// Tracks AI analyze + apply tasks the user has kicked off so the Tasks tab
/// can render them. The service does not own analyze logic — callers pass
/// the work and the service wraps it with progress + status bookkeeping.
class TaskService extends ChangeNotifier {
  final List<OrganizerTask> _tasks = [];

  List<OrganizerTask> get tasks => List.unmodifiable(_tasks);

  /// Count of tasks still running — drives the tab badge.
  int get runningCount =>
      _tasks.where((t) => t.status == TaskStatus.running).length;

  /// Runs [ai.analyzeFolder] under a new task entry. Returns the [OrganizerTask]
  /// so the caller can also stash references if needed; the task is already
  /// in [tasks] when this returns.
  OrganizerTask startAnalyze({
    required AiService ai,
    required String baseDir,
    String? titleHint,
    String? mediaTypeHint,
    Set<String>? onlyPaths,
  }) {
    final task = OrganizerTask(
      id: newId(),
      kind: TaskKind.analyze,
      label: p.basename(baseDir),
      startedAt: DateTime.now(),
      cancelToken: AiCancelToken(),
    );
    _tasks.insert(0, task);
    notifyListeners();

    // Fire-and-forget: completion updates the task.
    unawaited(() async {
      try {
        final plan = await ai.analyzeFolder(
          baseDir,
          titleHint: titleHint,
          mediaTypeHint: mediaTypeHint,
          onlyPaths: onlyPaths,
          cancelToken: task.cancelToken,
        );
        task
          ..status = TaskStatus.done
          ..finishedAt = DateTime.now()
          ..summary = _analyzeSummary(plan);
      } on AiCancelled {
        // User-initiated: not a failure, so no error line.
        task
          ..status = TaskStatus.stopped
          ..finishedAt = DateTime.now();
      } catch (e) {
        if (task.cancelToken?.isCancelled ??
            false || task.status == TaskStatus.stopped) {
          task
            ..status = TaskStatus.stopped
            ..finishedAt = DateTime.now();
        } else {
          task
            ..status = TaskStatus.failed
            ..finishedAt = DateTime.now()
            ..error = e.toString();
        }
      }
      notifyListeners();
    }());

    return task;
  }

  /// Registers an apply task wrapping [controller] and kicks off
  /// `controller.start()`. The controller's own listeners drive the live
  /// progress UI; this method just bookkeeps status transitions.
  OrganizerTask startApply({
    required ApplyController controller,
    required String label,
    VoidCallback? onDone,
  }) {
    final task = OrganizerTask(
      id: newId(),
      kind: TaskKind.apply,
      label: label,
      startedAt: DateTime.now(),
      controller: controller,
    );
    _tasks.insert(0, task);
    notifyListeners();

    void listener() {
      if (!controller.status.isTerminal) return;
      task
        ..status = _statusFromApply(controller.status)
        ..finishedAt ??= DateTime.now()
        ..summary = _applySummary(controller);
      controller.removeListener(listener);
      notifyListeners();
      if (onDone != null) onDone();
    }

    controller.addListener(listener);
    unawaited(controller.start());

    return task;
  }

  /// Stops a running task: analyze tasks abort their request through the
  /// cancel token, apply tasks fall out of their move loop via the controller.
  /// Either way the task ends up [TaskStatus.stopped] and keeps whatever work
  /// it already completed. No-op on finished tasks.
  void cancel(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _tasks[i];
    if (t.isFinished) return;
    // Apply: the controller's own listener flips the task to stopped once the
    // loop unwinds, so the count of moved files stays accurate.
    t.controller?.stop();
    // Analyze: closing the socket makes analyzeFolder throw AiCancelled, and
    // the catch above records the stop. Mark it now so the UI reacts on click
    // instead of waiting for the request to unwind.
    if (t.cancelToken != null) {
      t.cancelToken!.cancel();
      t
        ..status = TaskStatus.stopped
        ..finishedAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Removes a finished task. No-op on running tasks — use [cancel] first.
  void dismiss(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _tasks[i];
    if (!t.isFinished) return;
    _tasks.removeAt(i);
    notifyListeners();
  }

  /// Clears every finished task at once.
  void clearFinished() {
    _tasks.removeWhere((t) => t.isFinished);
    notifyListeners();
  }

  String _analyzeSummary(OrganizePlan plan) {
    final n = plan.actions.length;
    final tokens = plan.promptTokens + plan.completionTokens;
    return '$n · $tokens tok';
  }

  String _applySummary(ApplyController c) {
    if (c.status == ApplyStatus.stopped) {
      return '${c.done}/${c.total} · stopped';
    }
    if (c.failed > 0) {
      return '${c.done} ok · ${c.failed} failed';
    }
    return '${c.done}/${c.total}';
  }

  TaskStatus _statusFromApply(ApplyStatus s) => switch (s) {
    ApplyStatus.done => TaskStatus.done,
    ApplyStatus.stopped => TaskStatus.stopped,
    _ => TaskStatus.running,
  };
}

extension on ApplyStatus {
  bool get isTerminal =>
      this == ApplyStatus.done || this == ApplyStatus.stopped;
}
