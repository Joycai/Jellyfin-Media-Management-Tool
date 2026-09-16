import 'dart:async';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show Context;

import '../history_service.dart';
import './file_transfer.dart';

enum TransferStatus { running, stopped, done, failed }

/// Drives one [TransferPlan] with live progress and a stop button, and writes
/// the undo manifest when it ends. One per paste, owned by its task — the
/// same shape as `ApplyController`, minus pause and the activity log.
class TransferController extends ChangeNotifier {
  final TransferPlan plan;
  final ConflictPolicy policy;
  final HistoryService? history;
  final FileSystem _fs;

  TransferController({
    required this.plan,
    required this.policy,
    this.history,
    FileSystem fs = const LocalFileSystem(),
  }) : _fs = fs;

  TransferStatus _status = TransferStatus.running;
  int _bytesDone = 0;
  bool _stopRequested = false;
  bool _started = false;
  bool _disposed = false;
  TransferResult? _result;
  String? _undoError;
  String? _error;
  final Stopwatch _sw = Stopwatch();

  /// Pending throttled notify; a 5k-file tree would otherwise rebuild the
  /// Tasks tab once per file.
  Timer? _notifyTimer;
  static const _notifyThrottle = Duration(milliseconds: 50);

  TransferStatus get status => _status;
  TransferMode get mode => plan.mode;
  int get total => plan.items.length;
  int get bytesDone => _bytesDone;
  int get bytesTotal => plan.totalBytes;
  TransferResult? get result => _result;

  /// Set when files moved but the undo manifest could not be written.
  String? get undoError => _undoError;

  /// Set when the transfer itself threw before it could finish the batch —
  /// a per-item failure is in [result], not here.
  String? get error => _error;

  /// Why undo was not offered even though nothing failed: the sources and
  /// the destination share no root (two Windows drives), so no `baseDir`
  /// could bound the manifest's paths — or nothing file-shaped moved (an
  /// empty folder), so there was nothing to write.
  bool get undoUnavailable => _undoUnavailable;
  bool _undoUnavailable = false;

  /// Bytes-based while running; a finished batch is full whatever the bytes
  /// say (zero-byte placeholders, skipped conflicts add nothing).
  double get fraction => _status == TransferStatus.done
      ? 1
      : bytesTotal == 0
      ? 0
      : (_bytesDone / bytesTotal).clamp(0.0, 1.0);

  Duration? get eta {
    final s = _sw.elapsedMilliseconds / 1000.0;
    if (s <= 0 || _bytesDone <= 0 || _status != TransferStatus.running) {
      return null;
    }
    final rem = bytesTotal - _bytesDone;
    if (rem <= 0) return Duration.zero;
    return Duration(seconds: (rem / (_bytesDone / s)).round());
  }

  void _scheduleNotify() {
    if (_disposed) return;
    _notifyTimer ??= Timer(_notifyThrottle, () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

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

  /// Runs the transfer. Idempotent, like `ApplyController.start`.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sw.start();
    _notifyNow();
    try {
      _result = await executeTransfer(
        plan,
        policy: policy,
        fs: _fs,
        onProgress: (bytes) {
          _bytesDone = bytes;
          _scheduleNotify();
        },
        shouldStop: () => _stopRequested,
      );
    } catch (e) {
      // The executor catches per item, so this is a fault in the batch
      // itself. It is started unawaited by the task service, and an
      // exception escaping here would be an unhandled async error with no
      // card to show it on.
      _error = e.toString();
    } finally {
      // Runs even when the executor threw: whatever moved before the throw is
      // only recoverable through the manifest.
      await _recordUndo();
      _sw.stop();
      _status = _error != null
          ? TransferStatus.failed
          : (_result?.stopped ?? _stopRequested)
          ? TransferStatus.stopped
          : TransferStatus.done;
      _notifyNow();
    }
  }

  Future<void> _recordUndo() async {
    final r = _result;
    if (history == null || r == null) return;
    if (r.moves.isEmpty && r.created.isEmpty) {
      // An empty folder moves by one rename and records no file — there is
      // nothing a manifest could reverse, and the summary must say so rather
      // than let the user look for an entry that was never written.
      if (r.succeeded > 0) _undoUnavailable = true;
      return;
    }
    final baseDir = commonRoot([
      ...r.moves.map((m) => m['from']!),
      ...r.moves.map((m) => m['to']!),
      ...r.created,
    ], context: _fs.path);
    if (baseDir == null) {
      _undoUnavailable = true;
      return;
    }
    try {
      await history!.recordTransfer(
        baseDir: baseDir,
        itemCount: r.succeeded,
        totalBytes: r.bytesDone,
        moves: r.moves,
        created: r.created,
      );
    } catch (e) {
      _undoError = e.toString();
    }
  }

  /// Finishes the file in flight, then ends the batch.
  void stop() {
    if (_status != TransferStatus.running) return;
    _stopRequested = true;
    _notifyNow();
  }

  /// The deepest directory containing every path in [paths], or null when
  /// they share no root at all. Undo checks each manifest path against this,
  /// so it is the tightest bound the manifest can carry.
  @visibleForTesting
  static String? commonRoot(
    Iterable<String> paths, {
    required Context context,
  }) {
    List<String>? common;
    for (final raw in paths) {
      final parts = context.split(context.normalize(context.absolute(raw)));
      // A file's own name is never part of its containing directory.
      final dirParts = parts.sublist(0, parts.length - 1);
      if (common == null) {
        common = dirParts;
        continue;
      }
      var i = 0;
      while (i < common.length &&
          i < dirParts.length &&
          context.equals(common[i], dirParts[i])) {
        i++;
      }
      common = common.sublist(0, i);
    }
    // `split` keeps the root (`/` or `C:\`) as the first element, so an
    // empty prefix means the paths do not even share a drive.
    if (common == null || common.isEmpty) return null;
    return context.joinAll(common);
  }
}
