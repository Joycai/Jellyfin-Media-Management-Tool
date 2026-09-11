/// What organizing remembers between runs, under `<app-support>/agent/`.
///
/// Two things are kept, both keyed by *fingerprints* — a file's absolute path,
/// size and modification time — so anything that changed on disk is simply a
/// miss, never a stale answer:
///
/// * a folder's group decisions (`organize/<folder hash>.json`), so running
///   organize again on the same folder — after a cancel, a failed batch, or
///   just to look again — asks the model only about groups whose files
///   changed;
/// * the targets the user corrected in the preview (`overrides.json`), so the
///   next run does not undo a correction. It is recorded under the file's
///   fingerprint where it was *and* where it is going, because applying the
///   move changes its path.
///
/// Every read treats a missing or corrupt file as "nothing remembered": a
/// cache must never be the reason organizing fails. Writes are serialised and
/// replace the file with one rename.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'jellyfin_naming.dart';

/// One scanned file: enough to fingerprint it.
class FileStamp {
  final String relativePath;
  final int size;
  final DateTime modified;

  const FileStamp({
    required this.relativePath,
    required this.size,
    required this.modified,
  });
}

/// A group decision as remembered between runs.
class CachedDecision {
  final GroupDecision decision;
  final double confidence;
  final String note;

  const CachedDecision({
    required this.decision,
    required this.confidence,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'type': decision.type.name,
    'title': decision.title,
    'year': ?decision.year,
    'season': ?decision.season,
    if (decision.episodeOffset != 0) 'episodeOffset': decision.episodeOffset,
    'confidence': confidence,
    if (note.isNotEmpty) 'note': note,
  };

  static CachedDecision? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = GroupMediaType.values.asNameMap()[json['type']];
    final title = json['title'];
    if (type == null ||
        type == GroupMediaType.unknown ||
        title is! String ||
        title.trim().isEmpty) {
      return null;
    }
    int? integer(Object? value) => value is num ? value.toInt() : null;
    final confidence = json['confidence'];
    final note = json['note'];
    return CachedDecision(
      decision: GroupDecision(
        type: type,
        title: title,
        year: integer(json['year']),
        season: integer(json['season']),
        episodeOffset: integer(json['episodeOffset']) ?? 0,
      ),
      confidence: confidence is num
          ? confidence.toDouble().clamp(0.0, 1.0)
          : 0.8,
      note: note is String ? note : '',
    );
  }

  /// The decision the user's corrections imply, or null when they imply none.
  ///
  /// When every corrected video of a group went into one title folder other
  /// than the decided one (`Shows/Right Title (2011)`), the title, the year
  /// and — from the library root — the type follow it, so the group's other
  /// files land beside them next time. Corrections that disagree with each
  /// other say nothing about the group as a whole.
  CachedDecision? revisedBy(Iterable<String> videoTargets) {
    final folders = <(String, String)>{
      for (final target in videoTargets)
        if (p.posix.split(target) case [final root, final name, _, ...])
          (root, name),
    };
    if (folders.length != 1) return null;
    final (root, name) = folders.single;
    if ('$root/$name' == JellyfinNaming.titleFolder(decision)) return null;

    final match = RegExp(r'^(.*?)\s*\((\d{4})\)$').firstMatch(name);
    final title = (match?.group(1) ?? name).trim();
    if (title.isEmpty) return null;
    return CachedDecision(
      decision: GroupDecision(
        type: switch (root.toLowerCase()) {
          'movies' => GroupMediaType.movie,
          'shows' => GroupMediaType.series,
          _ => decision.type,
        },
        title: title,
        year: match == null ? null : int.parse(match.group(2)!),
        season: decision.season,
        episodeOffset: decision.episodeOffset,
      ),
      confidence: 1,
      note: 'Corrected in the preview',
    );
  }
}

/// A target the user corrected in the preview, as the scan saw the file.
class CorrectedFile {
  final FileStamp stamp;

  /// Forward-slash path relative to the organized folder.
  final String target;
  final bool isVideo;

  /// The group key the file was decided under, when known.
  final String? groupKey;

  const CorrectedFile({
    required this.stamp,
    required this.target,
    required this.isVideo,
    this.groupKey,
  });
}

typedef _Override = ({String target, DateTime lastUsed});

class OrganizeWorkspace {
  /// Decisions for a folder not organized in this long are dropped, as are
  /// all but the most recent [maxFolders] folders.
  static const retentionDays = 7;
  static const maxFolders = 20;

  /// A correction unused for this long is dropped.
  static const overrideRetentionDays = 180;

  final FileSystem _fs;
  final String? _explicitRoot;
  Future<void> _queue = Future.value();

  /// [fs] and [root] are injected in tests; production callers leave them at
  /// the defaults (real local FS + `<app-support>/agent/`).
  OrganizeWorkspace({FileSystem fs = const LocalFileSystem(), String? root})
    : _fs = fs,
      _explicitRoot = root;

  /// Fingerprint of one file: where it is, how big, when it last changed.
  String fileKey(String baseDir, FileStamp stamp) => _hash(
    '${_fs.path.normalize(_fs.path.join(baseDir, stamp.relativePath))}'
    '|${stamp.size}|${stamp.modified.millisecondsSinceEpoch}',
  );

  /// Fingerprint of a group: its files', in any order.
  String groupKey(String baseDir, Iterable<FileStamp> stamps) {
    final keys = [for (final stamp in stamps) fileKey(baseDir, stamp)]..sort();
    return _hash(keys.join('\n'));
  }

  Future<Map<String, CachedDecision>> loadDecisions(String baseDir) =>
      _serial(() async {
        final groups = (await _read(await _decisionsPath(baseDir)))?['groups'];
        if (groups is! Map) return <String, CachedDecision>{};
        return {
          for (final MapEntry(:key, :value) in groups.entries)
            if (key is String) key: ?CachedDecision.fromJson(value),
        };
      });

  Future<void> saveDecision(
    String baseDir,
    String groupKey,
    CachedDecision decision,
  ) => _serial(() async {
    final path = await _decisionsPath(baseDir);
    final stored = (await _read(path))?['groups'];
    await _write(path, {
      'baseDir': baseDir,
      'updatedAt': DateTime.now().toIso8601String(),
      'groups': {if (stored is Map) ...stored, groupKey: decision.toJson()},
    });
  });

  /// The targets the user chose earlier for any of [stamps], by relative
  /// path. A hit counts as a use, which keeps the correction from ageing out.
  Future<Map<String, String>> overridesFor(
    String baseDir,
    Iterable<FileStamp> stamps,
  ) => _serial(() async {
    final path = await _overridesPath();
    final entries = _decodeOverrides(await _read(path));
    final now = DateTime.now();
    final hits = <String, String>{};
    for (final stamp in stamps) {
      final key = fileKey(baseDir, stamp);
      final entry = entries[key];
      if (entry == null) continue;
      hits[stamp.relativePath] = entry.target;
      entries[key] = (target: entry.target, lastUsed: now);
    }
    if (hits.isNotEmpty) await _write(path, _encodeOverrides(entries, now));
    return hits;
  });

  /// Remembers the corrections from a preview the user applied, and revises a
  /// group's remembered decision when its corrected videos agree on a new
  /// title folder (see [CachedDecision.revisedBy]).
  Future<void> recordEdits(String baseDir, List<CorrectedFile> edits) async {
    if (edits.isEmpty) return;
    await _serial(() async {
      final path = await _overridesPath();
      final now = DateTime.now();
      final entries = _decodeOverrides(await _read(path));
      for (final edit in edits) {
        final moved = FileStamp(
          relativePath: edit.target,
          size: edit.stamp.size,
          modified: edit.stamp.modified,
        );
        for (final stamp in [edit.stamp, moved]) {
          entries[fileKey(baseDir, stamp)] = (
            target: edit.target,
            lastUsed: now,
          );
        }
      }
      await _write(path, _encodeOverrides(entries, now));
    });

    final targetsByGroup = <String, List<String>>{};
    for (final edit in edits) {
      if (edit.isVideo && edit.groupKey != null) {
        targetsByGroup.putIfAbsent(edit.groupKey!, () => []).add(edit.target);
      }
    }
    if (targetsByGroup.isEmpty) return;
    final decisions = await loadDecisions(baseDir);
    for (final MapEntry(key: group, value: targets) in targetsByGroup.entries) {
      if (decisions[group]?.revisedBy(targets) case final revised?) {
        await saveDecision(baseDir, group, revised);
      }
    }
  }

  /// Drops folders not organized within [retentionDays], and all but the
  /// newest [maxFolders]. Best effort, like everything here.
  Future<void> prune() => _serial(() async {
    final dir = _fs.directory(_fs.path.join(await _root(), 'organize'));
    if (!await dir.exists()) return;
    final folders = <(File, DateTime)>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final stamp = (await _read(entity.path))?['updatedAt'];
      final updated =
          (stamp is String ? DateTime.tryParse(stamp) : null) ??
          (await entity.stat()).modified;
      folders.add((entity, updated));
    }
    folders.sort((a, b) => b.$2.compareTo(a.$2));
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    for (final (index, (file, updated)) in folders.indexed) {
      if (index < maxFolders && !updated.isBefore(cutoff)) continue;
      try {
        await file.delete();
      } catch (_) {}
    }
  });

  Map<String, _Override> _decodeOverrides(Map<String, dynamic>? json) {
    final entries = json?['entries'];
    if (entries is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in entries.entries)
        if (key is String &&
            value is Map &&
            value['target'] is String &&
            value['lastUsed'] is String)
          if (DateTime.tryParse(value['lastUsed'] as String) case final used?)
            key: (target: value['target'] as String, lastUsed: used),
    };
  }

  Map<String, dynamic> _encodeOverrides(
    Map<String, _Override> entries,
    DateTime now,
  ) {
    final cutoff = now.subtract(const Duration(days: overrideRetentionDays));
    return {
      'entries': {
        for (final MapEntry(:key, :value) in entries.entries)
          if (!value.lastUsed.isBefore(cutoff))
            key: {
              'target': value.target,
              'lastUsed': value.lastUsed.toIso8601String(),
            },
      },
    };
  }

  Future<String> _root() async =>
      _explicitRoot ??
      _fs.path.join((await getApplicationSupportDirectory()).path, 'agent');

  Future<String> _decisionsPath(String baseDir) async => _fs.path.join(
    await _root(),
    'organize',
    '${_hash(_fs.path.normalize(baseDir))}.json',
  );

  Future<String> _overridesPath() async =>
      _fs.path.join(await _root(), 'overrides.json');

  Future<Map<String, dynamic>?> _read(String path) async {
    try {
      final file = _fs.file(path);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// Writes to a sibling and renames it over [path], so a crash mid-write
  /// leaves the previous file rather than half of a new one.
  Future<void> _write(String path, Map<String, dynamic> json) async {
    final file = _fs.file(path);
    await file.parent.create(recursive: true);
    final temp = _fs.file('$path.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(path);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static String _hash(String text) =>
      sha1.convert(utf8.encode(text)).toString();
}
