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

import '../path_safety.dart';

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

  /// Suggested NFO file name for a video.
  ///
  /// Jellyfin accepts `movie.nfo` or `<video base name>.nfo`; the latter is
  /// used because a folder holding two titles would otherwise have them fight
  /// over one `movie.nfo`.
  static String nfoNameForVideo(String videoFileName) {
    final dot = videoFileName.lastIndexOf('.');
    final base = dot <= 0 ? videoFileName : videoFileName.substring(0, dot);
    return '$base.nfo';
  }
}
