import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
// FcVideoThumbnailTime lives here and isn't re-exported by the package's main
// library — importing the platform interface directly is the only way to name it.
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/file_entry.dart';

/// Poster frames for video rows in the file table.
///
/// Decoding happens in `fc_native_video_thumbnail`'s native backends
/// (AVFoundation on macOS, Media Foundation on Windows, FFmpeg on Linux), so
/// nothing here blocks the UI isolate. Results are cached twice: an in-memory
/// LRU for the current session and a JPEG per entry under
/// `<appSupport>/thumbnails/` so re-opening a folder is instant.
///
/// This is the one place in the app that caches anything — everywhere else the
/// filesystem is the source of truth. The cache key includes mtime and size, so
/// a re-encoded file under the same name produces a new key rather than a stale
/// frame; the old entry is left for [_prune] to reclaim.
///
/// Every failure path degrades to "no thumbnail" and the caller falls back to
/// the type icon. That covers Linux boxes without the FFmpeg shared libraries,
/// DRM/codec-locked files, and truncated downloads.
class ThumbnailService {
  ThumbnailService._();

  static final ThumbnailService instance = ThumbnailService._();

  /// Max thumbnail edge, in pixels. Rows render at 34pt, so this stays crisp
  /// up to a 4x device pixel ratio and leaves room for a larger surface later.
  /// Windows ignores the height argument and produces a `width`x`width` box.
  static const int _maxEdge = 320;
  static const int _quality = 80;

  /// Native decode is cheap but not free; a hard cap keeps a fast scroll
  /// through a 500-file folder from queueing 500 simultaneous decodes.
  static const int _maxConcurrent = 3;

  static const int _memCacheEntries = 240;
  static const int _diskCacheBytes = 64 * 1024 * 1024;

  /// Where to grab the frame. The first frame of a movie or episode is
  /// routinely a black fade-in or a distributor logo, so seek past it.
  /// Ignored on Windows (Media Foundation exposes no seek here) and rejected
  /// for clips shorter than this — [_generate] retries without it.
  static final _seekTo = FcVideoThumbnailTime(
    10,
    FcVideoThumbnailTimeUnit.seconds,
  );

  final _plugin = FcNativeVideoThumbnail();

  /// Insertion-ordered (Dart map literals are LinkedHashMaps), so the oldest
  /// key is always `keys.first`.
  final _memory = <String, Uint8List>{};

  /// Keys that produced no frame. Never retried for the life of the session —
  /// a file that can't be decoded now won't decode on the next scroll either.
  final _failed = <String>{};

  final _inflight = <String, Future<Uint8List?>>{};
  final _waiting = Queue<Completer<void>>();
  int _running = 0;

  /// Set when the platform has no implementation registered at all, which
  /// turns the whole service into a no-op instead of throwing per row.
  bool _unsupported = false;

  Directory? _cacheDir;
  Future<void>? _pruned;

  /// Whether [entry] is a row this service can produce a thumbnail for.
  /// Directories and non-video files are not.
  static bool canThumbnail(FileEntry entry, String label) =>
      !entry.isDirectory && label == 'Video';

  /// The in-flight prune, if one is running. Tests await it so a background
  /// directory listing can't outlive the temp directory it's walking.
  @visibleForTesting
  Future<void>? get pendingPrune => _pruned;

  /// Drops all session state so each test starts from a cold service.
  /// The singleton outlives individual tests; without this a cached frame or a
  /// latched [_unsupported] would leak into the next one.
  @visibleForTesting
  void resetForTest() {
    _memory.clear();
    _failed.clear();
    _inflight.clear();
    _waiting.clear();
    _running = 0;
    _unsupported = false;
    _cacheDir = null;
    _pruned = null;
  }

  /// Cached bytes if they're already in memory, otherwise null.
  ///
  /// Lets a row paint its thumbnail on the very first frame — without this,
  /// scrolling back over already-decoded rows flashes the placeholder icon for
  /// a frame while the [Future] from [thumbnailFor] resolves.
  Uint8List? peek(FileEntry entry) {
    if (_unsupported) return null;
    return _memory[_keyFor(entry)];
  }

  /// Poster frame for [entry], or null if one can't be produced.
  Future<Uint8List?> thumbnailFor(FileEntry entry) {
    if (_unsupported) return Future.value(null);
    final key = _keyFor(entry);

    final cached = _memory.remove(key);
    if (cached != null) {
      _memory[key] = cached; // Re-insert to move it to the LRU tail.
      return Future.value(cached);
    }
    if (_failed.contains(key)) return Future.value(null);

    // Dedupe concurrent requests for the same key — a folder can legitimately
    // hold two rows pointing at one path mid-refresh.
    //
    // The braces matter: `whenComplete` awaits whatever its callback returns,
    // and an arrow body would return the removed Future — this same one —
    // leaving it waiting on itself forever.
    return _inflight[key] ??= _load(entry, key).whenComplete(() {
      _inflight.remove(key);
    });
  }

  /// Drops both cache tiers and deletes the on-disk directory.
  Future<void> clearCache() async {
    _memory.clear();
    _failed.clear();
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Error clearing thumbnail cache: $e');
    } finally {
      // Force the next _dir() to recreate it.
      _cacheDir = null;
      _pruned = null;
    }
  }

  /// Total bytes currently held on disk, for the Settings screen.
  Future<int> cacheSizeOnDisk() async {
    try {
      final dir = await _dir();
      var total = 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  /// Content-addressed cache key. mtime and size are folded in so an edited or
  /// replaced file never reuses the previous frame.
  String _keyFor(FileEntry entry) {
    final id =
        '${entry.path}|${entry.modified.microsecondsSinceEpoch}|${entry.size}';
    return sha1.convert(utf8.encode(id)).toString();
  }

  Future<Uint8List?> _load(FileEntry entry, String key) async {
    File? file;
    try {
      file = File(p.join((await _dir()).path, '$key.jpg'));
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _remember(key, bytes);
          return bytes;
        }
      }
    } catch (e) {
      // Unreadable cache dir (permissions, removable drive) — fall through and
      // decode in memory. Not being able to persist isn't fatal.
      debugPrint('Thumbnail cache read failed: $e');
    }

    final Uint8List? bytes;
    try {
      bytes = await _generate(entry.path);
    } on MissingPluginException {
      _unsupported = true;
      return null;
    } catch (e) {
      _failed.add(key);
      return null;
    }
    if (bytes == null || bytes.isEmpty) {
      _failed.add(key);
      return null;
    }

    _remember(key, bytes);
    if (file != null) {
      // Awaited rather than fired and forgotten: it's a ~16 KB local write, and
      // leaving it in flight would race [clearCache] into recreating a file it
      // just deleted.
      try {
        await file.writeAsBytes(bytes);
      } catch (e) {
        debugPrint('Thumbnail cache write failed: $e');
      }
      unawaited(_prune());
    }
    return bytes;
  }

  Future<Uint8List?> _generate(String path) async {
    await _acquire();
    try {
      // A clip shorter than _seekTo has no frame there. Backends differ in how
      // they say so — Linux/macOS throw, and a null return is also allowed by
      // the API contract — so treat both as "retry for the first frame".
      try {
        final seeked = await _plugin.saveThumbnailToBytes(
          srcFile: path,
          width: _maxEdge,
          height: _maxEdge,
          quality: _quality,
          at: _seekTo,
        );
        if (seeked != null && seeked.isNotEmpty) return seeked;
      } on MissingPluginException {
        rethrow;
      } catch (e) {
        // Fall through to the un-seeked attempt.
      }
      return await _plugin.saveThumbnailToBytes(
        srcFile: path,
        width: _maxEdge,
        height: _maxEdge,
        quality: _quality,
      );
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_running < _maxConcurrent) {
      _running++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // Hand the slot straight to the next waiter rather than decrementing and
      // letting it re-check, which would let a newly arriving call jump ahead.
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > _memCacheEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<Directory> _dir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'thumbnails'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDir = dir;
  }

  /// Trims the on-disk cache back under [_diskCacheBytes], oldest first. Runs
  /// at most once per session — the budget is generous enough that a single
  /// sweep after the first new thumbnail keeps growth bounded.
  Future<void> _prune() => _pruned ??= _pruneNow();

  Future<void> _pruneNow() async {
    try {
      final dir = await _dir();
      final entries = <({File file, int size, DateTime modified})>[];
      var total = 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final stat = await e.stat();
        entries.add((file: e, size: stat.size, modified: stat.modified));
        total += stat.size;
      }
      if (total <= _diskCacheBytes) return;

      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final e in entries) {
        if (total <= _diskCacheBytes) break;
        await e.file.delete();
        total -= e.size;
      }
    } catch (e) {
      debugPrint('Thumbnail cache prune failed: $e');
    }
  }
}
