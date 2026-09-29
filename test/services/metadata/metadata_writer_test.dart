import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/metadata/metadata_writer.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_writer.dart';

import '../../helpers/fs.dart';

const _nfo = '<?xml version="1.0"?>\n<movie><title>ok</title></movie>\n';

List<int> _jpeg([int size = 1024]) => [
  0xFF,
  0xD8,
  0xFF,
  ...List.filled(size - 3, 0x41),
];

void main() {
  late FileSystem fs;
  late MetadataWriter writer;

  setUp(() {
    fs = newMemoryFs();
    writer = MetadataWriter(fs: fs);
  });

  group('writing', () {
    test('writes the NFO and the images under the title folder', () async {
      final result = await writer.write(
        baseDir: '/work',
        nfoFileName: 'SPSF-43.nfo',
        nfoXml: _nfo,
        images: [
          ImageAsset(relativePath: 'poster.jpg', bytes: _jpeg()),
          ImageAsset(
            relativePath: 'extrafanart/backdrop-1.jpg',
            bytes: _jpeg(),
          ),
        ],
      );

      expect(result.succeeded, 3);
      expect(result.hasFailures, isFalse);
      expect(fs.file('/work/SPSF-43.nfo').readAsStringSync(), _nfo);
      expect(fs.file('/work/poster.jpg').existsSync(), isTrue);
      expect(fs.file('/work/extrafanart/backdrop-1.jpg').existsSync(), isTrue);
      expect(result.createdPaths, hasLength(3));
    });

    test('writes the NFO as UTF-8 without a BOM', () async {
      const xml = '<movie><title>特撮ヒロイン</title></movie>';
      await writer.write(baseDir: '/work', nfoFileName: 'a.nfo', nfoXml: xml);
      final bytes = fs.file('/work/a.nfo').readAsBytesSync();
      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(utf8.decode(bytes), xml);
    });

    test('creates intermediate directories', () async {
      final result = await writer.write(
        baseDir: '/work',
        nfoFileName: 'nested/deep/a.nfo',
        nfoXml: _nfo,
      );
      expect(result.succeeded, 1);
      expect(fs.file('/work/nested/deep/a.nfo').existsSync(), isTrue);
    });

    test('skips empty payloads instead of writing empty files', () async {
      final result = await writer.write(
        baseDir: '/work',
        nfoFileName: 'a.nfo',
        nfoXml: '   ',
        images: [const ImageAsset(relativePath: 'poster.jpg', bytes: [])],
      );
      expect(result.succeeded, 0);
      expect(fs.file('/work/a.nfo').existsSync(), isFalse);
    });
  });

  group('path safety', () {
    test('refuses a target that escapes the base directory', () async {
      final result = await writer.write(
        baseDir: '/work',
        nfoFileName: '../escaped.nfo',
        nfoXml: _nfo,
      );
      expect(result.succeeded, 0);
      expect(result.failed, 1);
      expect(fs.file('/escaped.nfo').existsSync(), isFalse);
    });

    test('refuses an escaping image path but still writes the NFO', () async {
      // One bad entry must not abort the batch — same contract as
      // applyOrganizeAction.
      final result = await writer.write(
        baseDir: '/work',
        nfoFileName: 'a.nfo',
        nfoXml: _nfo,
        images: [
          ImageAsset(relativePath: '../../evil.jpg', bytes: _jpeg()),
          ImageAsset(relativePath: 'poster.jpg', bytes: _jpeg()),
        ],
      );
      expect(result.succeeded, 2);
      expect(result.failed, 1);
      expect(fs.file('/work/poster.jpg').existsSync(), isTrue);
      expect(fs.file('/evil.jpg').existsSync(), isFalse);
    });

    test(
      'reads paths in the injected filesystem style, not the host one',
      () async {
        final windows = newWindowsMemoryFs();
        final result = await MetadataWriter(
          fs: windows,
        ).write(baseDir: r'C:\work', nfoFileName: 'a.nfo', nfoXml: _nfo);
        expect(result.succeeded, 1);
        expect(windows.file(r'C:\work\a.nfo').existsSync(), isTrue);
      },
    );
  });

  group('overwrite and backup', () {
    test('backs the previous NFO up before replacing it', () async {
      // Unlike a move, overwriting an NFO is not reversible by putting a file
      // back where it came from, so `backup` here really does copy.
      seedFile(fs, '/work/a.nfo', contents: 'ORIGINAL');

      final result = await writer.write(
        baseDir: '/work',
        nfoFileName: 'a.nfo',
        nfoXml: _nfo,
        backupDir: '/backups/op-1',
      );

      expect(result.succeeded, 1);
      expect(result.createdPaths, isEmpty);
      expect(fs.file('/work/a.nfo').readAsStringSync(), _nfo);
      expect(fs.file('/backups/op-1/a.nfo').readAsStringSync(), 'ORIGINAL');
      expect(result.restorablePaths, hasLength(1));
    });

    test(
      'without a backup dir it still overwrites, but nothing is restorable',
      () async {
        seedFile(fs, '/work/a.nfo', contents: 'ORIGINAL');
        final result = await writer.write(
          baseDir: '/work',
          nfoFileName: 'a.nfo',
          nfoXml: _nfo,
        );
        expect(result.succeeded, 1);
        expect(result.restorablePaths, isEmpty);
        expect(result.written.single.overwritten, isTrue);
      },
    );

    test(
      'distinguishes created from overwritten so undo knows what to do',
      () async {
        seedFile(fs, '/work/a.nfo', contents: 'ORIGINAL');
        final result = await writer.write(
          baseDir: '/work',
          nfoFileName: 'a.nfo',
          nfoXml: _nfo,
          images: [ImageAsset(relativePath: 'poster.jpg', bytes: _jpeg())],
        );
        expect(result.createdPaths, ['/work/poster.jpg']);
        expect(result.restorablePaths, isEmpty);
      },
    );
  });

  group('readExisting', () {
    test('returns null when there is no NFO', () async {
      expect(await writer.readExisting('/work', 'a.nfo'), isNull);
    });

    test('reads one that is there', () async {
      seedFile(fs, '/work/a.nfo', contents: _nfo);
      expect(await writer.readExisting('/work', 'a.nfo'), _nfo);
    });

    test('refuses to read outside the base directory', () async {
      seedFile(fs, '/secret.nfo', contents: 'SECRET');
      expect(await writer.readExisting('/work', '../secret.nfo'), isNull);
    });
  });

  group('nfoTargetFor', () {
    Future<(String, NfoKind)> target(String videoPath) async {
      final t = await writer.nfoTargetFor(videoPath);
      expect(t.dir, fs.path.dirname(videoPath));
      return (t.fileName, t.kind);
    }

    test('a video alone in its folder gets movie.nfo', () async {
      // The name Jellyfin documents for movies, and the one verified against
      // a live library; no NFO has to exist yet.
      seedFile(fs, '/work/Title (2026)/Title.mkv', contents: 'v');
      seedFile(fs, '/work/Title (2026)/Title.srt', contents: 's');
      expect(await target('/work/Title (2026)/Title.mkv'), (
        'movie.nfo',
        NfoKind.movie,
      ));
    });

    test('a catalogue code is not read as an episode number', () async {
      seedFile(fs, '/work/SPSF-43/SPSF-43.mp4', contents: 'v');
      expect(await target('/work/SPSF-43/SPSF-43.mp4'), (
        'movie.nfo',
        NfoKind.movie,
      ));
    });

    test('a video sharing its folder with another gets its own name', () async {
      // A mixed folder to Jellyfin, where movie.nfo is not read at all.
      seedFile(fs, '/work/mixed/A.mkv', contents: 'a');
      seedFile(fs, '/work/mixed/B.mp4', contents: 'b');
      expect(await target('/work/mixed/A.mkv'), ('A.nfo', NfoKind.movie));
    });

    test('extras beside the feature do not make the folder mixed', () async {
      seedFile(fs, '/work/T/T.mkv', contents: 'v');
      seedFile(fs, '/work/T/T-trailer.mkv', contents: 't');
      seedFile(fs, '/work/T/T-featurette.mkv', contents: 'f');
      expect(await target('/work/T/T.mkv'), ('movie.nfo', NfoKind.movie));
    });

    test('a part or an extra gets its own name, even alone', () async {
      for (final video in [
        '/work/P/P-cd1.mkv',
        '/work/Q/Q-part1.mkv',
        '/work/R/R-featurette.mkv',
        '/work/S/featurettes/Making of.mkv',
      ]) {
        seedFile(fs, video, contents: 'v');
        final name = fs.path.basenameWithoutExtension(video);
        expect(await target(video), ('$name.nfo', NfoKind.movie));
      }
    });

    test('an episode gets its own name and <episodedetails>', () async {
      // Even alone: movie.nfo in a season folder is never read.
      seedFile(fs, '/tv/Show/Season 01/Show S01E01.mkv', contents: 'v');
      seedFile(fs, '/tv/Show/Season 02/01.mkv', contents: 'v');
      seedFile(fs, '/tv/Anime/Anime - 03.mkv', contents: 'v');
      seedFile(fs, '/tv/Anime/Anime - 04.mkv', contents: 'v');
      expect(await target('/tv/Show/Season 01/Show S01E01.mkv'), (
        'Show S01E01.nfo',
        NfoKind.episode,
      ));
      expect(await target('/tv/Show/Season 02/01.mkv'), (
        '01.nfo',
        NfoKind.episode,
      ));
      expect(await target('/tv/Anime/Anime - 03.mkv'), (
        'Anime - 03.nfo',
        NfoKind.episode,
      ));
    });

    test('an existing <video>.nfo is updated, not shadowed', () async {
      seedFile(fs, '/work/T/T.mkv', contents: 'v');
      seedFile(fs, '/work/T/T.nfo', contents: _nfo);
      expect(await target('/work/T/T.mkv'), ('T.nfo', NfoKind.movie));
    });

    test('movie.nfo wins when both exist, as it does in Jellyfin', () async {
      seedFile(fs, '/work/T/T.mkv', contents: 'v');
      seedFile(fs, '/work/T/T.nfo', contents: _nfo);
      seedFile(fs, '/work/T/movie.nfo', contents: _nfo);
      expect(await target('/work/T/T.mkv'), ('movie.nfo', NfoKind.movie));
    });

    test('a folder that cannot be listed counts as one video', () async {
      expect(await target('/missing/A.mkv'), ('movie.nfo', NfoKind.movie));
    });
  });

  group('seriesDirFor', () {
    test('walks past season and specials folders', () {
      final ctx = fs.path;
      expect(
        MetadataWriter.seriesDirFor('/tv/Show/Season 01', context: ctx),
        '/tv/Show',
      );
      expect(
        MetadataWriter.seriesDirFor('/tv/Show/Specials', context: ctx),
        '/tv/Show',
      );
      expect(MetadataWriter.seriesDirFor('/tv/Show', context: ctx), '/tv/Show');
      expect(MetadataWriter.seriesDirFor('/Season 1', context: ctx), '/');
    });
  });

  group('nfoNameForVideo', () {
    test('swaps the extension', () {
      expect(
        MetadataWriter.nfoNameForVideo('SPSF-43 Title.mkv'),
        'SPSF-43 Title.nfo',
      );
    });

    test('handles dots in the name and no extension at all', () {
      expect(
        MetadataWriter.nfoNameForVideo('A.Movie.2026.1080p.mkv'),
        'A.Movie.2026.1080p.nfo',
      );
      expect(MetadataWriter.nfoNameForVideo('noext'), 'noext.nfo');
      expect(MetadataWriter.nfoNameForVideo('.hidden'), '.hidden.nfo');
    });
  });
}
