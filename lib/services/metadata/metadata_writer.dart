/// The single chokepoint for every byte the scraper puts on disk.
///
/// `applyOrganizeAction` is the equivalent for *moves*, and deliberately is
/// not reused here: its contract (refuse to clobber an existing target, fall
/// back to copy+delete across volumes) is about relocating a file that already
/// exists, whereas this writes new content and sometimes has to overwrite.
/// The obligations it carries over are the ones that matter:
///
/// * every target validated with `PathSafety.isWithin(baseDir, …)`, passing
///   `context:` so an injected POSIX filesystem is not parsed with Windows
///   rules;
/// * all path building through the `path` package, never string concatenation;
/// * one failure never aborts the batch — results are counted and reported.
///
/// **`backup` genuinely copies here.** Elsewhere in this app the word only
/// gates whether an undo manifest gets recorded (see `HistoryService`), because
/// a move is reversible by moving back. Overwriting an NFO is not reversible
/// that way, so the previous file is really copied into the backup directory
/// before it is replaced. Images are not backed up: they can be downloaded
/// again, and the manifest records which ones were created so undo can delete
/// them.
library;

import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../file_label_service.dart';
import '../organize/filename_parser.dart';
import '../path_safety.dart';
import '../scrape/media_code.dart';
import 'nfo_writer.dart';

const FileSystem _defaultFs = LocalFileSystem();

/// One binary asset to write, already downloaded.
///
/// Taking bytes rather than a URL keeps this class free of the network, so the
/// whole write path can be tested against an in-memory filesystem.
class ImageAsset {
  /// Path relative to the title folder, e.g. `poster.jpg` or
  /// `extrafanart/backdrop-1.jpg`.
  final String relativePath;
  final List<int> bytes;

  const ImageAsset({required this.relativePath, required this.bytes});
}

/// What a write actually did, per file.
class WrittenFile {
  final String path;
  final bool created;
  final bool overwritten;
  final String? backupPath;

  const WrittenFile({
    required this.path,
    this.created = false,
    this.overwritten = false,
    this.backupPath,
  });
}

class MetadataWriteResult {
  final List<WrittenFile> written;
  final Map<String, String> failures;

  const MetadataWriteResult({required this.written, required this.failures});

  int get succeeded => written.length;
  int get failed => failures.length;
  bool get hasFailures => failures.isNotEmpty;

  /// Paths that did not exist before this write — undo deletes exactly these.
  List<String> get createdPaths => [
    for (final w in written)
      if (w.created) w.path,
  ];

  /// Paths that were replaced, with where the original was saved.
  Map<String, String> get restorablePaths => {
    for (final w in written)
      if (w.overwritten && w.backupPath != null) w.path: w.backupPath!,
  };
}

/// Where one scrape's NFO lands: [fileName] in [dir], with a [kind] root.
class NfoTarget {
  final String dir;
  final String fileName;
  final NfoKind kind;

  const NfoTarget({
    required this.dir,
    required this.fileName,
    required this.kind,
  });
}

class MetadataWriter {
  final FileSystem fs;

  const MetadataWriter({this.fs = _defaultFs});

  /// Writes [nfoXml] and [images] into [baseDir].
  ///
  /// [nfoFileName] is a plain file name (`movie.nfo`, or the video's base name
  /// plus `.nfo`), not a path. [backupDir] receives a copy of any file about
  /// to be overwritten; pass null to skip backups, in which case
  /// [MetadataWriteResult.restorablePaths] is empty and undo can only delete.
  ///
  /// Never throws for a per-file problem — the failure is recorded against the
  /// path and the remaining files are still written.
  Future<MetadataWriteResult> write({
    required String baseDir,
    required String nfoFileName,
    String? nfoXml,
    List<ImageAsset> images = const [],
    String? backupDir,
  }) async {
    final path = fs.path;
    final written = <WrittenFile>[];
    final failures = <String, String>{};

    Future<void> writeOne(String relativePath, List<int> bytes) async {
      final target = path.normalize(path.join(baseDir, relativePath));
      try {
        if (!PathSafety.isWithin(baseDir, target, context: path)) {
          throw FileSystemException('Path escapes base directory', target);
        }
        final file = fs.file(target);
        final existed = await file.exists();
        String? backupPath;
        if (existed && backupDir != null) {
          backupPath = await _backUp(file, backupDir, relativePath);
        }
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        written.add(
          WrittenFile(
            path: target,
            created: !existed,
            overwritten: existed,
            backupPath: backupPath,
          ),
        );
      } catch (e) {
        failures[target] = e.toString();
      }
    }

    if (nfoXml != null && nfoXml.trim().isNotEmpty) {
      // NFO is written as UTF-8 without a BOM: the XML declaration already
      // announces the encoding, and a BOM trips up some Kodi-era readers.
      await writeOne(nfoFileName, utf8.encode(nfoXml));
    }
    for (final image in images) {
      if (image.bytes.isEmpty) continue;
      await writeOne(image.relativePath, image.bytes);
    }

    return MetadataWriteResult(written: written, failures: failures);
  }

  /// Every `.nfo` under [rootDir], deepest-last, capped at [limit].
  ///
  /// The cap mirrors the 400-file ceiling on the organize walk: a library root
  /// picked by accident should come back with a big-but-finite list rather than
  /// stalling on a network share. Dotfiles and dot-directories are skipped, as
  /// they are everywhere else in the app.
  Future<List<String>> findNfoFiles(String rootDir, {int limit = 400}) async {
    final out = <String>[];
    try {
      final dir = fs.directory(rootDir);
      if (!await dir.exists()) return out;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (out.length >= limit) break;
        if (entity is! File) continue;
        if (!fs.path.basename(entity.path).toLowerCase().endsWith('.nfo')) {
          continue;
        }
        if (!PathSafety.isWithin(rootDir, entity.path, context: fs.path)) {
          continue;
        }
        // Skip anything under a dot-segment, not just dot-named files: a
        // `.git` or `.thumbnails` directory is exactly where a stray NFO
        // should not drag the whole library into a refresh.
        final relative = fs.path.relative(entity.path, from: rootDir);
        if (fs.path.split(relative).any((s) => s.startsWith('.'))) continue;
        out.add(entity.path);
      }
    } catch (_) {
      // A folder we cannot list yields what we already found, not an error —
      // one unreadable subdirectory must not sink a whole-library refresh.
    }
    return out;
  }

  /// Reads the NFO already at `baseDir/nfoFileName`, or null when there is
  /// none (or it cannot be read).
  Future<String?> readExisting(String baseDir, String nfoFileName) async {
    final path = fs.path;
    final target = path.normalize(path.join(baseDir, nfoFileName));
    if (!PathSafety.isWithin(baseDir, target, context: path)) return null;
    try {
      final file = fs.file(target);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Copies [file] into [backupDir], preserving its relative name. Returns the
  /// backup path, or null when the copy failed — a failed backup must not stop
  /// the write, but it must not be reported as restorable either.
  Future<String?> _backUp(
    File file,
    String backupDir,
    String relativePath,
  ) async {
    final path = fs.path;
    try {
      final target = path.normalize(path.join(backupDir, relativePath));
      if (!PathSafety.isWithin(backupDir, target, context: path)) return null;
      final backup = fs.file(target);
      await backup.parent.create(recursive: true);
      await file.copy(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// Where a scrape of the video at [videoPath] writes, and as what.
  ///
  /// Jellyfin reads a movie from `movie.nfo` or `<video>.nfo` (`movie.nfo`
  /// wins when both exist), but not `movie.nfo` in a *mixed folder*, and an
  /// episode only from `<video>.nfo`. So:
  ///
  /// * an episode — `SxxEyy`, a season or `Specials` folder, or an episode
  ///   number that is not a catalogue code's (see [_isEpisode]) — gets
  ///   `<video>.nfo` as `<episodedetails>`;
  /// * a part (`-cd1`, `-part2`) gets `<video>.nfo`, and a part Jellyfin
  ///   stacks with others gets the *first* part's: the stack is one movie
  ///   whose path is part one, so a `-cd2.nfo` would never be read;
  /// * an extra (`-featurette`, a `trailers` folder) gets `<video>.nfo`:
  ///   `movie.nfo` would speak for the whole folder, i.e. the feature;
  /// * any other video gets `movie.nfo`, unless the folder holds another
  ///   feature (extras and dotfiles do not count) or only a `<video>.nfo`
  ///   exists already — then `<video>.nfo`.
  ///
  /// A folder that cannot be listed counts as holding one video.
  Future<NfoTarget> nfoTargetFor(String videoPath) async {
    final path = fs.path;
    final dir = path.dirname(videoPath);
    final name = path.basename(videoPath);
    final own = nfoNameForVideo(name);
    final parsed = _parse(dir, name);

    if (_isEpisode(parsed, name, path.basename(dir))) {
      return NfoTarget(dir: dir, fileName: own, kind: NfoKind.episode);
    }
    if (parsed.extraType != null) {
      return NfoTarget(dir: dir, fileName: own, kind: NfoKind.movie);
    }
    final siblings = await _otherVideos(dir, name);

    final stack = _StackPart.of(name, path);
    if (parsed.part != null || stack != null) {
      var first = name;
      if (stack != null) {
        var lowest = stack.number;
        for (final other in siblings) {
          final part = _StackPart.of(other, path);
          if (part == null || part.key != stack.key) continue;
          if (part.number < lowest ||
              (part.number == lowest && other.compareTo(first) < 0)) {
            lowest = part.number;
            first = other;
          }
        }
      }
      return NfoTarget(
        dir: dir,
        fileName: nfoNameForVideo(first),
        kind: NfoKind.movie,
      );
    }

    // Parsed lazily: the first feature found settles it.
    if (siblings.any((other) => _parse(dir, other).extraType == null)) {
      return NfoTarget(dir: dir, fileName: own, kind: NfoKind.movie);
    }

    final movieNfo = NfoKind.movie.fileName!;
    // An existing <video>.nfo is updated in place rather than shadowed by a
    // new movie.nfo, which Jellyfin would read instead.
    final useOwn =
        !await _exists(path.join(dir, movieNfo)) &&
        await _exists(path.join(dir, own));
    return NfoTarget(
      dir: dir,
      fileName: useOwn ? own : movieNfo,
      kind: NfoKind.movie,
    );
  }

  /// The series folder above [dir]: [dir] itself, or the first folder up that
  /// only subdivides a title (`Season 01`, `S01`, `第1季`, `Specials`, …, as
  /// [FilenameParser.isContainerFolder] reads them) — where `tvshow.nfo` goes.
  static String seriesDirFor(String dir, {p.Context? context}) {
    final path = context ?? p.context;
    var current = path.normalize(dir);
    while (FilenameParser.isContainerFolder(path.basename(current))) {
      final parent = path.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    return current;
  }

  /// The names of the other videos in [dir]. Dotfiles are skipped, as
  /// everywhere in the app — a macOS `._Movie.mkv` is not a second feature.
  Future<List<String>> _otherVideos(String dir, String name) async {
    final path = fs.path;
    final out = <String>[];
    try {
      await for (final entity in fs.directory(dir).list()) {
        if (entity is! File) continue;
        final other = path.basename(entity.path);
        if (other == name || other.startsWith('.')) continue;
        if (FileLabelService.getLabel(path.extension(other)) != 'Video') {
          continue;
        }
        out.add(other);
      }
    } catch (_) {
      // Unreadable folder: assume the common case rather than fail the scrape
      // before it starts.
    }
    return out;
  }

  /// Parsed with its folder name, which is what marks `Season 01/01.mkv` as an
  /// episode and `trailers/x.mkv` as an extra.
  ParsedFile _parse(String dir, String name) =>
      FilenameParser.parse(fs.path.join(fs.path.basename(dir), name));

  /// Whether [f] is an episode rather than a movie.
  ///
  /// A catalogue code parses as an episode number (`SPSF-43` is "episode
  /// 43"), so a code vetoes the episode when it leads the name, after any
  /// `[group]` tags (`SPSF-43 Title 02`, `hhd800.com@ABC-123`), or when its
  /// number is the episode's (`[GIGA]SPSF-43`). An `EP03` marker is not a
  /// code, nor is a title word and a number (`Bleach 03`): a space counts as
  /// a code's separator only between capitals (`ABC 123`). A CRC tag
  /// (`[ABCD1234]`) neither leads nor matches, so it leaves the episode be.
  static bool _isEpisode(ParsedFile f, String name, String folderName) {
    if (f.season != null || f.specialLabel != null) return true;
    // `Specials/Show OVA.mkv`: a special with no number on it.
    if (f.special && FilenameParser.isSeasonFolder(folderName)) return true;
    final episode = f.episode;
    if (episode == null) return false;
    final lead = _leadingTags.matchAsPrefix(name)?.end ?? 0;
    for (final c in findMediaCodes(name)) {
      if (c.letters.toUpperCase() == 'EP') continue;
      if (c.separator == ' ' && c.letters != c.letters.toUpperCase()) continue;
      if (c.start == lead || c.number == episode) return false;
    }
    return true;
  }

  static final _leadingTags = RegExp(r'(?:\s*[\[【(][^\]】)]*[\]】)])*\s*');
  Future<bool> _exists(String target) async {
    try {
      return await fs.file(target).exists();
    } catch (_) {
      return false;
    }
  }

  /// `<video base name>.nfo` — the per-video form Jellyfin reads in a mixed
  /// folder, and the only one an episode can use. Prefer [nfoTargetFor], which
  /// knows when the plain `movie.nfo` is the right answer.
  static String nfoNameForVideo(String videoFileName) {
    final dot = videoFileName.lastIndexOf('.');
    final base = dot <= 0 ? videoFileName : videoFileName.substring(0, dot);
    return '$base.nfo';
  }
}

/// A file name in Jellyfin's multi-part stacking form: a part token at the end
/// of the name (`Movie-cd1.mkv`, `Movie (2026) [Part 2].mkv`). Files stack when
/// the text before the token, the token and the extension agree ([key]); a
/// name with anything after its number (`Movie-cd1 1080p.mkv`) never stacks.
class _StackPart {
  final String key;
  final int number;

  const _StackPart(this.key, this.number);

  static final _rule = RegExp(
    r'^(.*?)(?:(?<=[\]\)\}])|[ _.-]+)[\(\[]?(cd|dvd|part|pt|dis[ck])[ _.-]*'
    r'([0-9]+)[\)\]]?$',
    caseSensitive: false,
  );

  static _StackPart? of(String fileName, p.Context path) {
    final m = _rule.firstMatch(path.basenameWithoutExtension(fileName));
    if (m == null) return null;
    return _StackPart(
      '${m.group(1)!.toLowerCase()}|${m.group(2)!.toLowerCase()}'
      '|${path.extension(fileName).toLowerCase()}',
      int.parse(m.group(3)!),
    );
  }
}
