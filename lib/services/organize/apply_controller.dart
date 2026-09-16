import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/history_entry.dart';
import '../../models/organize_plan.dart';
import '../history_service.dart';
import './organize_service.dart';

enum ApplyStatus { running, paused, stopped, done }

enum LogLevel { info, warn, debug }

/// Semantic activity-log entry; the screen formats it with localized strings so
/// the log stays translatable.
enum LogKind { started, moved, skipped, failed, finished, stopped, undoLost }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final LogKind kind;
  final String name;
  final String dir;
  final String error;
  final int count;
  final int done;
  final int skipped;

  LogEntry(
    this.kind, {
    required this.level,
    this.name = '',
    this.dir = '',
    this.error = '',
    this.count = 0,
    this.done = 0,
    this.skipped = 0,
  }) : time = DateTime.now();
}

/// Drives applying an [OrganizePlan] with live progress, pause/stop control and
/// an activity log. Registered as a local `ChangeNotifier` for the progress UI.
class ApplyController extends ChangeNotifier {
  final OrganizePlan plan;
  final String baseDir;
  final bool backup;
  final int totalBytes;
  final HistoryService? history;

  /// Default for [maxLogEntries]: enough scrollback to investigate a large
  /// library, small enough that the log stops being the job's memory footprint.
  static const int defaultMaxLogEntries = 5000;

  /// How many of the newest activity-log entries to retain. Older ones are
  /// dropped from the front; the aggregate counts ([done], [failed], [skipped])
  /// are kept separately and stay exact either way.
  final int maxLogEntries;

  ApplyController({
    required this.plan,
    required this.baseDir,
    required this.backup,
    required this.totalBytes,
    this.history,
    this.maxLogEntries = defaultMaxLogEntries,
  });

  ApplyStatus _status = ApplyStatus.running;
  int _done = 0;
  int _failed = 0;
  int _skipped = 0;
  int _inProgress = 0;
  int _bytesDone = 0;

  /// Retained activity-log entries, oldest first. Bounded by [maxLogEntries]:
  /// a 100k-action job would otherwise hold 100k [LogEntry] objects -- each
  /// carrying three strings -- for a panel that only ever shows the tail.
  final List<LogEntry> _log = [];

  /// Every entry ever appended, including the ones trimming has dropped.
  /// Consumers walk the log by this absolute index (see [logAt]), so a trim at
  /// the front cannot shift entries they have already seen.
  int _logAppended = 0;

  final List<Map<String, String>> _moves = [];
  final Stopwatch _sw = Stopwatch();
  Completer<void>? _pauseGate;
  bool _stopRequested = false;
  bool _started = false;

  bool _disposed = false;

  /// Set when the batch moved files but the undo manifest could not be
  /// written, which leaves the result unrecoverable from the History
  /// screen. Surfaced in the task summary as well as the log: a log the
  /// user has already scrolled past is not a warning.
  String? _undoError;

  String? get undoError => _undoError;

  /// Pending throttled notify; non-null means a rebuild is already queued.
  /// Lifecycle, pause/resume and terminal transitions flush via
  /// [_notifyNow] so the UI never lags behind a user-initiated state change.
  Timer? _notifyTimer;
  static const _notifyThrottle = Duration(milliseconds: 50);

  /// Coalesces high-frequency in-loop progress ticks into at most one rebuild
  /// per [_notifyThrottle]. A 10k-action job rebuilds the progress screen at
  /// ~20 fps instead of ~20k times.
  void _scheduleNotify() {
    if (_disposed) return;
    _notifyTimer ??= Timer(_notifyThrottle, () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  /// Flushes any pending throttled notify and emits one immediately. Used at
  /// terminal transitions and user-initiated state changes (start, pause,
  /// resume, stop, done) so they never appear delayed.
  void _notifyNow() {
    if (_disposed) return;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    super.dispose();
  }

  ApplyStatus get status => _status;
  int get total => plan.actions.length;
  int get done => _done;
  int get failed => _failed;
  int get skipped => _skipped;
  int get inProgress => _inProgress;
  int get queued =>
      (total - _done - _failed - _skipped - _inProgress).clamp(0, total);
  int get bytesDone => _bytesDone;
  int get bytesTotal => totalBytes;

  /// A snapshot of the retained log, oldest first.
  ///
  /// Kept for diagnostics and tests. A UI that redraws as the job runs should
  /// walk [logStart] / [logLength] / [logAt] instead, so a rebuild costs what
  /// arrived since the last one rather than a copy of the whole list.
  List<LogEntry> get log => List.unmodifiable(_log);

  /// Absolute index of the oldest entry [logAt] can still return; equals the
  /// number of entries trimming has dropped from the front.
  int get logStart => _logAppended - _log.length;

  /// Absolute number of entries appended, including trimmed ones.
  int get logLength => _logAppended;

  /// The entry at absolute index [index], which must be at least [logStart].
  ///
  /// Index-based rather than handing out the list: the progress screen appends
  /// to its own filtered view as entries arrive, so a rebuild costs what showed
  /// up since the last one instead of copying the whole log.
  LogEntry logAt(int index) => _log[index - logStart];

  void _addLog(LogEntry entry) {
    _log.add(entry);
    _logAppended++;
    if (_log.length > maxLogEntries) {
      _log.removeRange(0, _log.length - maxLogEntries);
    }
  }

  double get fraction =>
      total == 0 ? 0 : ((_done + _failed + _skipped) / total).clamp(0.0, 1.0);

  double get speedBytesPerSec {
    final s = _sw.elapsedMilliseconds / 1000.0;
    return s > 0 ? _bytesDone / s : 0;
  }

  Duration? get eta {
    final sp = speedBytesPerSec;
    if (sp <= 0 || _status != ApplyStatus.running) return null;
    final rem = bytesTotal - _bytesDone;
    if (rem <= 0) return Duration.zero;
    return Duration(seconds: (rem / sp).round());
  }

  ApplyResult get result => ApplyResult(
    succeeded: _done,
    failed: _failed,
    failures: plan.actions
        .where((a) => a.status == ActionStatus.failed)
        .toList(),
  );

  /// Runs the apply loop. Idempotent: subsequent calls are no-ops (the detail
  /// screen and the task service both want to ensure it starts, but only one
  /// should actually drive the loop).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sw.start();
    _addLog(LogEntry(LogKind.started, level: LogLevel.info, count: total));
    _notifyNow();

    // Pace very fast (same-volume rename) jobs so progress is perceptible,
    // without meaningfully slowing large batches.
    final pace = total <= 60 ? 40 : (total <= 200 ? 12 : 0);

    try {
      for (final a in plan.actions) {
        if (_stopRequested) break;
        while (_pauseGate != null) {
          await _pauseGate!.future;
        }
        if (_stopRequested) break;

        if (a.status == ActionStatus.needsReview) {
          _skipped++;
          _addLog(
            LogEntry(
              LogKind.skipped,
              level: LogLevel.warn,
              name: p.basename(a.source),
            ),
          );
          _scheduleNotify();
          continue;
        }
        if (a.status != ActionStatus.pending) continue;

        _inProgress++;
        _scheduleNotify();
        if (pace > 0) await Future.delayed(Duration(milliseconds: pace));

        final outcome = await applyOrganizeAction(a, baseDir: baseDir);
        _inProgress--;
        if (outcome.ok) {
          _done++;
          _bytesDone += outcome.bytes;
          if (outcome.fromPath != null && outcome.toPath != null) {
            _moves.add({'from': outcome.fromPath!, 'to': outcome.toPath!});
          }
          _addLog(
            LogEntry(
              LogKind.moved,
              level: LogLevel.info,
              name: p.basename(a.source),
              dir: p.dirname(a.target),
            ),
          );
        } else {
          _failed++;
          _addLog(
            LogEntry(
              LogKind.failed,
              level: LogLevel.warn,
              name: p.basename(a.source),
              error: outcome.error ?? '',
            ),
          );
        }
        _scheduleNotify();
      }
    } finally {
      // All of this has to run even when the loop threw. Files have already
      // been moved by then, so the manifest is the only record that they can
      // be moved back, and the status is what tells the UI the batch is over
      // rather than still running.
      await _recordUndo();
      _sw.stop();
      _status = _stopRequested ? ApplyStatus.stopped : ApplyStatus.done;
      _addLog(
        LogEntry(
          _stopRequested ? LogKind.stopped : LogKind.finished,
          level: LogLevel.info,
          done: _done,
          skipped: _skipped,
        ),
      );
      _notifyNow();
    }
  }

  /// Writes the undo manifest for everything that actually moved.
  ///
  /// Failures are captured rather than thrown: the moves already happened, so
  /// an exception from here would replace whatever the loop threw with a
  /// complaint about the paperwork and the caller would learn neither. The
  /// user gets a warn line in the log and [undoError] in the task summary.
  Future<void> _recordUndo() async {
    if (!backup || _moves.isEmpty || history == null) return;
    final renames = _moves
        .where((m) => p.basename(m['from']!) != p.basename(m['to']!))
        .length;
    try {
      await history!.record(
        kind: HistoryKind.aiOrganize,
        baseDir: baseDir,
        itemCount: _moves.length,
        moveCount: _moves.length - renames,
        renameCount: renames,
        totalBytes: _bytesDone,
        moves: _moves,
      );
    } catch (e) {
      _undoError = e.toString();
      _addLog(
        LogEntry(
          LogKind.undoLost,
          level: LogLevel.warn,
          name: baseDir,
          error: _undoError!,
        ),
      );
    }
  }

  void pause() {
    if (_status != ApplyStatus.running) return;
    _pauseGate = Completer<void>();
    _status = ApplyStatus.paused;
    _sw.stop();
    _notifyNow();
  }

  void resume() {
    if (_status != ApplyStatus.paused) return;
    _status = ApplyStatus.running;
    _sw.start();
    final g = _pauseGate;
    _pauseGate = null;
    g?.complete();
    _notifyNow();
  }

  void stop() {
    if (_status == ApplyStatus.done || _status == ApplyStatus.stopped) return;
    _stopRequested = true;
    if (_pauseGate != null) {
      final g = _pauseGate;
      _pauseGate = null;
      g?.complete();
    }
    _status = ApplyStatus.running; // let the loop fall through to its end
    _notifyNow();
  }
}
