/// The AI request log: every request body the app actually sent, with what
/// came back, one JSON object per line in a file per day.
///
/// It exists for the failures that do not announce themselves. A field a
/// server drops without a word, a reasoning switch it ignores, a relay that
/// rewrites the reply — each shows up only as worse results, and the ladders
/// in the providers make choices on the user's behalf that nothing else
/// records. The log is where those choices, and the exact bytes behind them,
/// can be read afterwards.
///
/// What it never holds: a credential (headers are not logged at all, and a
/// URL loses its query string), and large payloads — every string longer
/// than [maxString] characters, and every inline image, is replaced by a note
/// of its length. Off by default; Settings → Privacy turns it on.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai_http.dart';

class ApiLog {
  ApiLog({this.directory, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The app-wide log, pointed at `<appSupport>/logs` by `main()`.
  static final ApiLog instance = ApiLog();

  /// Longest string kept verbatim.
  static const maxString = 2048;

  /// Days of log files kept; older ones are removed by [prune].
  static const retentionDays = 7;

  /// Where the daily files go. Null writes nothing.
  Directory? directory;
  final DateTime Function() _clock;

  /// Whether requests are written. Nothing is buffered while this is off.
  bool enabled = false;

  /// Numbers every entry of this process, so the entries of one retry ladder
  /// read in order even when concurrent tasks interleave between them.
  int _sequence = 0;

  /// Writes are chained so that entries from concurrent requests never
  /// interleave inside a line.
  Future<void> _tail = Future.value();

  /// The file entries written now go to.
  File? get currentFile {
    final dir = directory;
    if (dir == null) return null;
    final now = _clock();
    final day =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return File(p.join(dir.path, 'api-$day.jsonl'));
  }

  /// Records one request. [request] is the decoded body as sent; [response]
  /// is whatever summary the provider has (text, tool calls, usage), or null
  /// with [error] when the request failed. Never throws, and returns at once:
  /// the write happens behind every earlier one.
  void record({
    required String protocol,
    required String model,
    required Uri url,
    required Object? request,
    int? status,
    Object? response,
    String? error,
    Duration? elapsed,
  }) {
    if (!enabled) return;
    final file = currentFile;
    if (file == null) return;
    final entry = {
      'seq': ++_sequence,
      'at': _clock().toIso8601String(),
      'protocol': protocol,
      'model': model,
      // The query string and user info can carry a credential; nothing else
      // in them is worth reading back.
      'url': AiHttp.safeUrl(url),
      'status': ?status,
      'elapsed_ms': ?elapsed?.inMilliseconds,
      'request': redact(request),
      'response': ?redact(response),
      'error': ?redact(error),
    };
    final String line;
    try {
      line = '${jsonEncode(entry)}\n';
    } catch (_) {
      return;
    }
    _tail = _tail.then((_) async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // A log that cannot be written must not fail the request it logs.
      }
    });
  }

  /// Completes once every entry recorded so far is on disk.
  Future<void> flush() => _tail;

  /// Removes log files older than [retentionDays]. Best effort.
  Future<void> prune() async {
    final dir = directory;
    if (dir == null || !await dir.exists()) return;
    final cutoff = _clock().subtract(const Duration(days: retentionDays));
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Pruning is housekeeping; the next launch tries again.
    }
  }

  /// Deletes every log file.
  Future<void> clear() async {
    await flush();
    final dir = directory;
    if (dir == null || !await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Nothing to report: the files are only a diagnostic aid.
    }
  }

  /// A copy of [value] safe to write: long strings and inline images are
  /// replaced by a note of their size, and nothing else is changed.
  static Object? redact(Object? value) => switch (value) {
    String s when s.startsWith('data:') && s.contains(';base64,') =>
      '<inline data, ${s.length} chars omitted>',
    String s when s.length > maxString =>
      '${s.substring(0, 200)}… <${s.length - 200} chars omitted>',
    Map<dynamic, dynamic> map => {
      for (final entry in map.entries)
        '${entry.key}': _isInlineData(entry.key, entry.value)
            ? '<inline data, ${(entry.value as String).length} chars omitted>'
            : redact(entry.value),
    },
    List<dynamic> list => [for (final item in list) redact(item)],
    _ => value,
  };

  /// Gemini's `inlineData.data` and Anthropic's `source.data` are bare
  /// base64, with no `data:` prefix to recognise them by.
  static bool _isInlineData(Object? key, Object? value) =>
      key == 'data' && value is String && value.length > 256;
}
