import 'dart:io';

import 'package:path/path.dart' as p;

enum RenameRule { matchFolder, featurette, interview, part, tvShow, subtitle }

class RenameService {
  /// Builds a Jellyfin-conventional filename from [baseName] (the media's own
  /// name, normally its folder) and [extension] (leading dot included).
  ///
  /// Split out of [getNewName] so the organize preview can apply the same rules
  /// to a *planned* target path, which has no file on disk yet.
  static String buildName(
    String baseName,
    String extension,
    RenameRule rule, {
    String? extra,
  }) {
    switch (rule) {
      case RenameRule.matchFolder:
        return '$baseName$extension';
      case RenameRule.featurette:
        return '$baseName-featurette$extension';
      case RenameRule.interview:
        return '$baseName-interview$extension';
      case RenameRule.part:
        return '$baseName-part${extra ?? "1"}$extension';
      case RenameRule.tvShow:
        // extra format expected: "S01E01"
        return '$baseName.${extra ?? "S01E01"}$extension';
      case RenameRule.subtitle:
        // extra format expected: "VideoFileName.chi.[default]"
        return '$extra$extension';
    }
  }

  static String getNewName(File file, RenameRule rule, {String? extra}) =>
      buildName(
        p.basename(file.parent.path),
        p.extension(file.path),
        rule,
        extra: extra,
      );

  /// The name a rule should build on for a Jellyfin-shaped relative target such
  /// as `Shows/Some Show (2006)/Season 01/ep.mkv`.
  ///
  /// Season and Specials folders are containers, not the media's name, so we
  /// walk past them to the series folder — otherwise a TV rename would produce
  /// `Season 01.S01E01.mkv`. Falls back to the file's own name for a flat
  /// target that has no usable folder.
  static String baseNameForTarget(String relativeTargetPath) {
    final normalized = p.normalize(relativeTargetPath);
    final segments = p
        .split(p.dirname(normalized))
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    for (var i = segments.length - 1; i >= 0; i--) {
      if (!_isContainerFolder(segments[i])) return segments[i];
    }
    return p.basenameWithoutExtension(normalized);
  }

  static final _containerFolder = RegExp(
    r'^(season\s*\d+|specials)$',
    caseSensitive: false,
  );

  static bool _isContainerFolder(String name) =>
      _containerFolder.hasMatch(name.trim());

  static Future<File> rename(File file, String newName) async {
    final newPath = p.join(file.parent.path, newName);
    return await file.rename(newPath);
  }
}
