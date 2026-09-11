import 'package:path/path.dart' as p;

import 'filename_parser.dart';

/// One title's worth of files: the unit the model is asked about.
class MediaGroup {
  const MediaGroup({
    required this.id,
    required this.folder,
    required this.seriesKey,
    required this.videos,
    required this.companions,
    this.companionVideos = const {},
  });

  /// `g1`, `g2`, … in folder-then-key order, so the same listing always yields
  /// the same ids — a model answering about `g3` must mean the same group on a
  /// retry.
  final String id;

  /// The folder holding the title, `''` at the root. Season and extras
  /// subfolders are folded into their parent, so this is `Show`, never
  /// `Show/Season 1`.
  final String folder;

  /// Shared [ParsedFile.seriesKey] of the videos; `''` for a group made only of
  /// companions.
  final String seriesKey;

  /// Sorted by season, episode, then path; missing numbers sort last.
  final List<ParsedFile> videos;

  /// Subtitles, artwork, NFOs and anything else that travels with the title.
  final List<ParsedFile> companions;

  /// Companion [ParsedFile.relativePath] → the video it belongs to, for the
  /// companions that belong to one specific video.
  final Map<String, ParsedFile> companionVideos;

  List<ParsedFile> get files => [...videos, ...companions];

  /// The most common non-empty video title guess (earliest wins a tie), else
  /// the folder's name.
  String get titleGuess {
    final counts = <String, int>{};
    for (final v in videos) {
      if (v.titleGuess.isNotEmpty) {
        counts[v.titleGuess] = (counts[v.titleGuess] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return folder.isEmpty ? '' : p.basename(folder);
    var best = counts.keys.first;
    for (final entry in counts.entries) {
      if (entry.value > counts[best]!) best = entry.key;
    }
    return best;
  }

  /// The video [companion] belongs to specifically (its subtitle, its thumb),
  /// or null for folder-level files like `poster.jpg`.
  ParsedFile? videoFor(ParsedFile companion) =>
      companionVideos[companion.relativePath];

  @override
  String toString() =>
      'MediaGroup($id, folder: "$folder", key: "$seriesKey", '
      '${videos.length} videos, ${companions.length} companions)';
}

/// Splits a parsed file list into titles.
abstract final class Grouping {
  static List<MediaGroup> build(List<ParsedFile> files) {
    final builders = <(String, String), _GroupBuilder>{};

    _GroupBuilder builderFor(String folder, String key) => builders.putIfAbsent(
      _id(folder, key),
      () => _GroupBuilder(folder, key),
    );

    List<_GroupBuilder> videoGroupsIn(String folder) => [
      for (final b in builders.values)
        if (b.folder == folder && b.videos.isNotEmpty) b,
    ];

    final videos = files.where((f) => f.isVideo).toList();
    final extras = <ParsedFile>[];

    // Season and extras subfolders group under their parent, so a show split
    // into `Season 1` / `Season 2` is one title rather than one per season.
    for (final v in videos) {
      if (v.extraType != null) {
        extras.add(v);
        continue;
      }
      builderFor(
        FilenameParser.containerParent(v.folder),
        v.seriesKey,
      ).videos.add(v);
    }

    // An extra is often named after itself (`Making of.mkv` in `Extras/`, a
    // bare `trailer.mkv`) rather than its title, so when its key matches
    // nothing it goes to the folder's only title, if there is exactly one.
    for (final v in extras) {
      final owner = FilenameParser.containerParent(v.folder);
      final exact = builders[_id(owner, v.seriesKey)];
      if (exact != null) {
        exact.videos.add(v);
        continue;
      }
      final inFolder = videoGroupsIn(owner);
      if (inFolder.length == 1) {
        inFolder.single.videos.add(v);
      } else {
        builderFor(owner, v.seriesKey).videos.add(v);
      }
    }

    final byFolder = <String, List<ParsedFile>>{};
    for (final v in videos) {
      byFolder.putIfAbsent(v.folder, () => []).add(v);
    }
    final groupOf = <String, _GroupBuilder>{
      for (final b in builders.values)
        for (final v in b.videos) v.relativePath: b,
    };

    for (final c in files.where((f) => !f.isVideo)) {
      final siblings = byFolder[c.folder] ?? const <ParsedFile>[];
      final video =
          _longestPrefixVideo(c, siblings) ?? _sameEpisodeVideo(c, siblings);
      if (video != null) {
        final group = groupOf[video.relativePath]!;
        group.companions.add(c);
        group.companionVideos[c.relativePath] = video;
        continue;
      }
      final owner = FilenameParser.containerParent(c.folder);
      final sameKey = builders[_id(owner, c.seriesKey)];
      if (sameKey != null && sameKey.videos.isNotEmpty) {
        sameKey.companions.add(c);
        continue;
      }
      final inFolder = videoGroupsIn(owner);
      if (inFolder.length == 1) {
        inFolder.single.companions.add(c);
        continue;
      }
      // Two titles share the folder and nothing says which this belongs to;
      // guessing would put one show's poster on the other.
      builderFor(owner, '').companions.add(c);
    }

    final ordered = builders.values.toList()
      ..sort((a, b) {
        final byFolder = _sortable(a.folder).compareTo(_sortable(b.folder));
        return byFolder != 0 ? byFolder : a.key.compareTo(b.key);
      });

    return [
      for (final (i, b) in ordered.indexed)
        MediaGroup(
          id: 'g${i + 1}',
          folder: b.folder,
          seriesKey: b.key,
          videos: b.videos..sort(_byEpisode),
          companions: b.companions
            ..sort((x, y) => x.relativePath.compareTo(y.relativePath)),
          companionVideos: Map.unmodifiable(b.companionVideos),
        ),
    ];
  }

  /// The same-folder video whose name is the longest prefix of [companion]'s,
  /// ending at a word boundary — `Show - 1` must not claim `Show - 10.ass`.
  static ParsedFile? _longestPrefixVideo(
    ParsedFile companion,
    List<ParsedFile> videos,
  ) {
    final name = companion.baseName.toLowerCase();
    ParsedFile? best;
    for (final v in videos) {
      final prefix = v.baseName.toLowerCase();
      if (prefix.isEmpty || !name.startsWith(prefix)) continue;
      if (name.length > prefix.length &&
          _wordCharacter.hasMatch(name[prefix.length])) {
        continue;
      }
      if (best == null || prefix.length > best.baseName.length) best = v;
    }
    return best;
  }

  static final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// A subtitle from another release (`Alpha - 02.chs.ass` beside
  /// `[A] Alpha - 02 [1080p].mkv`) shares no prefix with its video but names
  /// the same title and episode. Matched only when exactly one video does.
  static ParsedFile? _sameEpisodeVideo(
    ParsedFile companion,
    List<ParsedFile> videos,
  ) {
    if (companion.episode == null) return null;
    final matches = [
      for (final v in videos)
        if (v.extraType == null &&
            v.seriesKey == companion.seriesKey &&
            v.episode == companion.episode &&
            v.season == companion.season &&
            v.special == companion.special)
          v,
    ];
    return matches.length == 1 ? matches.single : null;
  }

  static int _byEpisode(ParsedFile a, ParsedFile b) {
    int nullsLast(int? x, int? y) {
      if (x == y) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    }

    final season = nullsLast(a.season, b.season);
    if (season != 0) return season;
    final episode = nullsLast(a.episode, b.episode);
    if (episode != 0) return episode;
    return a.relativePath.compareTo(b.relativePath);
  }

  static (String, String) _id(String folder, String key) => (folder, key);

  // Separator-independent, so ids do not depend on the platform.
  static String _sortable(String folder) =>
      folder.isEmpty ? '' : p.split(folder).join('/');
}

class _GroupBuilder {
  _GroupBuilder(this.folder, this.key);

  final String folder;
  final String key;
  final videos = <ParsedFile>[];
  final companions = <ParsedFile>[];
  final companionVideos = <String, ParsedFile>{};
}
