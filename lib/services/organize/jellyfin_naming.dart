import 'package:path/path.dart' as p;

import 'filename_parser.dart';
import 'grouping.dart';

enum GroupMediaType { movie, series, unknown }

/// The model's answer about one [MediaGroup] — the only part of organizing
/// that is not mechanical.
class GroupDecision {
  const GroupDecision({
    required this.type,
    required this.title,
    this.year,
    this.season,
    this.episodeOffset = 0,
  });

  final GroupMediaType type;
  final String title;
  final int? year;

  /// Season for files whose names carry none.
  final int? season;

  /// Added to parsed episode numbers, turning absolute numbering (`- 13`) into
  /// seasonal (`S02E01`) when a group is one later season of a show.
  final int episodeOffset;

  @override
  String toString() =>
      'GroupDecision(${type.name}, "$title", year: $year, season: $season, '
      'offset: $episodeOffset)';
}

class PlannedTarget {
  const PlannedTarget({required this.file, this.target, this.problem});

  final ParsedFile file;

  /// Relative target joined with forward slashes, or null when the file
  /// cannot be placed and needs review.
  final String? target;

  /// Short English reason when [target] is null.
  final String? problem;

  @override
  String toString() =>
      'PlannedTarget(${file.relativePath} -> ${target ?? 'null ($problem)'})';
}

/// Builds Jellyfin library paths from a group and the decision about it.
///
/// Refusing is always an option here: a null target leaves the file where it
/// is for the user to review, which is recoverable, while a wrong guess moves
/// it somewhere Jellyfin files it under the wrong title.
abstract final class JellyfinNaming {
  // < > : " / \ | ? *
  static const _forbidden = {
    0x3C,
    0x3E,
    0x3A,
    0x22,
    0x2F,
    0x5C,
    0x7C,
    0x3F,
    0x2A,
  };

  static final _reservedWindowsName = RegExp(
    r'^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  /// Characters Windows forbids and control characters removed, whitespace
  /// collapsed, trailing dots and spaces trimmed (Windows drops them silently,
  /// so `Title.` and `Title` would be the same folder). A reserved device name
  /// such as `CON` gets a trailing underscore, since Windows cannot create it.
  static String sanitize(String name) {
    final buffer = StringBuffer();
    for (final rune in name.replaceAll(RegExp(r'\s+'), ' ').runes) {
      if (rune < 0x20 || rune == 0x7F || _forbidden.contains(rune)) continue;
      buffer.writeCharCode(rune);
    }
    final cleaned = buffer
        .toString()
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return _reservedWindowsName.hasMatch(cleaned) ? '${cleaned}_' : cleaned;
  }

  /// `Movies/Title (2020)` or `Shows/Title (2020)`, without ` (year)` when the
  /// year is unknown. Throws [ArgumentError] for an [GroupMediaType.unknown]
  /// type or a title that sanitizes to nothing; [plan] reports both instead.
  static String titleFolder(GroupDecision decision) {
    final root = switch (decision.type) {
      GroupMediaType.movie => 'Movies',
      GroupMediaType.series => 'Shows',
      GroupMediaType.unknown => throw ArgumentError.value(
        decision.type,
        'decision.type',
        'has no library folder',
      ),
    };
    final name = _titleName(decision);
    if (name == null) {
      throw ArgumentError.value(decision.title, 'decision.title', 'is empty');
    }
    return p.posix.join(root, name);
  }

  /// One target per file of [group], in [MediaGroup.files] order.
  static List<PlannedTarget> plan(MediaGroup group, GroupDecision decision) {
    final files = group.files;
    if (decision.type == GroupMediaType.unknown) {
      return [
        for (final f in files) PlannedTarget(file: f, problem: 'not decided'),
      ];
    }
    final title = sanitize(decision.title);
    if (title.isEmpty) {
      return [
        for (final f in files) PlannedTarget(file: f, problem: 'no title'),
      ];
    }

    final base = titleFolder(decision);
    final series = decision.type == GroupMediaType.series;
    final targets = <String, String>{};
    final problems = <String, String>{};

    void place(ParsedFile f, String target) => targets[f.relativePath] = target;
    void fail(ParsedFile f, String problem) {
      targets.remove(f.relativePath);
      problems[f.relativePath] = problem;
    }

    final mains = [
      for (final v in group.videos)
        if (v.extraType == null) v,
    ];
    for (final v in group.videos) {
      if (v.extraType != null) place(v, _extraTarget(base, v));
    }

    if (series) {
      for (final v in mains) {
        if (v.episode == null) {
          fail(v, 'no episode number');
          continue;
        }
        // Specials have their own numbering; an offset that maps absolute
        // episodes onto a season says nothing about them.
        final season = v.special ? 0 : v.season ?? decision.season ?? 1;
        final offset = v.special ? 0 : decision.episodeOffset;
        final episode = v.episode! + offset;
        if (episode < 0) {
          fail(v, 'episode offset below zero');
          continue;
        }
        final end = v.episodeEnd == null
            ? ''
            : '-E${_pad(v.episodeEnd! + offset)}';
        place(
          v,
          p.posix.join(
            base,
            'Season ${_pad(season)}',
            '$title S${_pad(season)}E${_pad(episode)}$end${v.extension}',
          ),
        );
      }
    } else {
      final name = p.posix.basename(base);
      final parts = {for (final v in mains) v.part};
      final distinctParts =
          !parts.contains(null) && parts.length == mains.length;
      for (final v in mains) {
        if (mains.length > 1 && !distinctParts) {
          fail(v, 'several videos, no part numbers');
        } else {
          final part = v.part == null ? '' : ' - part${v.part}';
          place(v, p.posix.join(base, '$name$part${v.extension}'));
        }
      }
    }

    // Collisions among videos first, so their companions then learn their
    // video could not be placed rather than colliding in turn.
    _failCollisions(group.videos, targets, fail);

    // A movie's lone subtitle rarely shares the video's old name exactly, but
    // Jellyfin only pairs a subtitle whose name starts with the video's.
    final loneMovie = !series && mains.length == 1
        ? targets[mains.single.relativePath]
        : null;

    for (final c in group.companions) {
      final video = group.videoFor(c);
      if (video != null) {
        final videoTarget = targets[video.relativePath];
        if (videoTarget == null) {
          fail(c, 'its video could not be placed');
        } else {
          place(c, _besideVideo(c, videoTarget));
        }
      } else if (c.extraType != null) {
        place(c, _extraTarget(base, c));
      } else if (c.extension == '.nfo') {
        place(c, p.posix.join(base, series ? 'tvshow.nfo' : 'movie.nfo'));
      } else if (c.kind == 'Subtitle' && loneMovie != null) {
        place(c, _besideVideo(c, loneMovie));
      } else {
        place(c, p.posix.join(base, p.basename(c.relativePath)));
      }
    }

    // Only companions lose here: every video left is already unique, and one
    // stray artwork file must not unplace the episode it happens to shadow.
    _failCollisions(files, targets, fail, keepVideos: true);

    return [
      for (final f in files)
        PlannedTarget(
          file: f,
          target: targets[f.relativePath],
          problem: targets.containsKey(f.relativePath)
              ? null
              : problems[f.relativePath],
        ),
    ];
  }

  static String? _titleName(GroupDecision decision) {
    final title = sanitize(decision.title);
    if (title.isEmpty) return null;
    return decision.year == null ? title : '$title (${decision.year})';
  }

  static String _extraTarget(String base, ParsedFile f) =>
      p.posix.join(base, f.extraType!, p.basename(f.relativePath));

  static String _besideVideo(ParsedFile c, String videoTarget) {
    final stem = p.posix.withoutExtension(videoTarget);
    if (c.kind == 'Subtitle') {
      final language = c.language == null ? '' : '.${c.language}';
      return '$stem$language${c.extension}';
    }
    if (c.kind == 'Image') return '$stem-thumb${c.extension}';
    if (c.extension == '.nfo') return '$stem.nfo';
    return p.posix.join(
      p.posix.dirname(videoTarget),
      p.basename(c.relativePath),
    );
  }

  // Case-insensitive, because two targets differing only in case are one file
  // on Windows and macOS.
  static void _failCollisions(
    List<ParsedFile> files,
    Map<String, String> targets,
    void Function(ParsedFile, String) fail, {
    bool keepVideos = false,
  }) {
    final owners = <String, List<ParsedFile>>{};
    for (final f in files) {
      final target = targets[f.relativePath];
      if (target != null) {
        owners.putIfAbsent(target.toLowerCase(), () => []).add(f);
      }
    }
    for (final clash in owners.values) {
      if (clash.length < 2) continue;
      for (final f in clash) {
        if (!(keepVideos && f.isVideo)) fail(f, 'duplicate target');
      }
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
