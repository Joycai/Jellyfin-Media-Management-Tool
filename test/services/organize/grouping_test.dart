import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/organize/filename_parser.dart';
import 'package:jellyfin_media_management_tool/services/organize/grouping.dart';
import 'package:path/path.dart' as p;

/// Paths are written with `/` and handed over with the platform separator.
String native(String path) => p.joinAll(path.split('/'));

List<MediaGroup> build(List<String> paths) => Grouping.build([
  for (final path in paths) FilenameParser.parse(native(path)),
]);

List<String> pathsOf(Iterable<ParsedFile> files) => [
  for (final f in files) p.split(f.relativePath).join('/'),
];

ParsedFile fileIn(MediaGroup group, String path) =>
    group.files.singleWhere((f) => f.relativePath == native(path));

void main() {
  test('a series with subtitles, poster and tvshow.nfo is one group', () {
    final groups = build([
      'Show/Show - 02.mkv',
      'Show/Show - 01.mkv',
      'Show/Show - 01.chs.ass',
      'Show/Show - 02.cht.ass',
      'Show/poster.jpg',
      'Show/tvshow.nfo',
    ]);

    expect(groups, hasLength(1));
    final g = groups.single;
    expect(g.id, 'g1');
    expect(g.folder, 'Show');
    expect(g.seriesKey, 'show');
    expect(g.titleGuess, 'Show');
    expect(pathsOf(g.videos), ['Show/Show - 01.mkv', 'Show/Show - 02.mkv']);
    expect(g.companions, hasLength(4));
    expect(
      g.videoFor(fileIn(g, 'Show/Show - 01.chs.ass'))?.relativePath,
      native('Show/Show - 01.mkv'),
    );
    expect(
      g.videoFor(fileIn(g, 'Show/Show - 02.cht.ass'))?.relativePath,
      native('Show/Show - 02.mkv'),
    );
    expect(g.videoFor(fileIn(g, 'Show/poster.jpg')), isNull);
    expect(g.videoFor(fileIn(g, 'Show/tvshow.nfo')), isNull);
  });

  test('two shows in one folder stay apart; shared artwork is not guessed', () {
    final groups = build([
      'Downloads/[A] Alpha - 01 [1080p].mkv',
      'Downloads/[A] Alpha - 02 [1080p].mkv',
      'Downloads/Beta.S01E01.mkv',
      'Downloads/Beta.S01E02.mkv',
      'Downloads/Alpha - 02.chs.ass',
      'Downloads/folder.jpg',
    ]);

    expect(
      [for (final g in groups) (g.id, g.seriesKey)],
      [('g1', ''), ('g2', 'alpha'), ('g3', 'beta')],
    );
    final [artwork, alpha, beta] = groups;

    expect(artwork.videos, isEmpty);
    expect(pathsOf(artwork.companions), ['Downloads/folder.jpg']);
    expect(alpha.videos, hasLength(2));
    expect(beta.videos, hasLength(2));
    expect(beta.companions, isEmpty);
    // Another release's subtitle shares no prefix but the same episode.
    final subtitle = fileIn(alpha, 'Downloads/Alpha - 02.chs.ass');
    expect(alpha.videoFor(subtitle)?.baseName, '[A] Alpha - 02 [1080p]');
  });

  test('a movie with its trailer, nfo and artwork', () {
    final groups = build([
      'Movies/Heat (1995)/Heat (1995).mkv',
      'Movies/Heat (1995)/Heat (1995)-trailer.mkv',
      'Movies/Heat (1995)/Heat (1995).nfo',
      'Movies/Heat (1995)/folder.jpg',
    ]);

    expect(groups, hasLength(1));
    final g = groups.single;
    expect(g.folder, p.join('Movies', 'Heat (1995)'));
    expect(g.videos, hasLength(2));
    expect(g.companions, hasLength(2));
    expect(
      g.videoFor(fileIn(g, 'Movies/Heat (1995)/Heat (1995).nfo'))?.relativePath,
      native('Movies/Heat (1995)/Heat (1995).mkv'),
    );
    expect(g.videoFor(fileIn(g, 'Movies/Heat (1995)/folder.jpg')), isNull);
  });

  test('an extra named after itself joins the folder\'s only title', () {
    final groups = build([
      'Film/Film.2019.1080p.mkv',
      'Film/Extras/Making Of.mkv',
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.folder, 'Film');
    expect(groups.single.videos, hasLength(2));
  });

  test('season subfolders fold into one group under the parent', () {
    final groups = build([
      'Show/Season 2/Show S02E01.mkv',
      'Show/Season 1/Show S01E02.mkv',
      'Show/Season 1/Show S01E01.mkv',
      'Show/Season 1/Show S01E01.en.srt',
      'Show/poster.jpg',
    ]);

    expect(groups, hasLength(1));
    final g = groups.single;
    expect(g.folder, 'Show');
    expect(pathsOf(g.videos), [
      'Show/Season 1/Show S01E01.mkv',
      'Show/Season 1/Show S01E02.mkv',
      'Show/Season 2/Show S02E01.mkv',
    ]);
    expect(
      g.videoFor(fileIn(g, 'Show/Season 1/Show S01E01.en.srt'))?.relativePath,
      native('Show/Season 1/Show S01E01.mkv'),
    );
    expect(pathsOf(g.companions), contains('Show/poster.jpg'));
  });

  test('bare episode files in season folders group by the show folder', () {
    final groups = build([
      'Show/Season 1/01.mkv',
      'Show/Season 1/02.mkv',
      'Show/Season 2/01.mkv',
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.seriesKey, 'folder:show');
    expect(groups.single.titleGuess, 'Show');
    expect(pathsOf(groups.single.videos), [
      'Show/Season 1/01.mkv',
      'Show/Season 1/02.mkv',
      'Show/Season 2/01.mkv',
    ]);
  });

  test('a Specials subfolder merges with the parent-folder episodes', () {
    final groups = build([
      'Show/Show - 01.mkv',
      'Show/Specials/Show - SP01.mkv',
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.videos, hasLength(2));
  });

  test('a folder without videos forms a companion-only group', () {
    final groups = build(['Show/Show - 01.mkv', 'Artwork/cover.jpg']);

    expect(groups, hasLength(2));
    expect(groups.first.id, 'g1');
    expect(groups.first.folder, 'Artwork');
    expect(groups.first.videos, isEmpty);
    expect(pathsOf(groups.first.files), ['Artwork/cover.jpg']);
    expect(groups.first.titleGuess, 'Artwork');
  });

  test('the longest prefix wins, and only at a word boundary', () {
    final g = build([
      'Show/Show - 1.mkv',
      'Show/Show - 10.mkv',
      'Show/Show - 10.ass',
      'Show/Show - 1.ass',
      'Show/Show.mkv',
      'Show/Show - 1.chs.ass',
    ]).single;

    expect(g.videoFor(fileIn(g, 'Show/Show - 10.ass'))?.baseName, 'Show - 10');
    expect(g.videoFor(fileIn(g, 'Show/Show - 1.ass'))?.baseName, 'Show - 1');
    expect(
      g.videoFor(fileIn(g, 'Show/Show - 1.chs.ass'))?.baseName,
      'Show - 1',
    );
  });

  test('ids are stable regardless of input order', () {
    final paths = [
      'B/Beta - 01.mkv',
      'A/Alpha - 01.mkv',
      'A/Gamma - 01.mkv',
      'A/Alpha - 01.chs.ass',
      'B/poster.jpg',
    ];
    List<(String, String, String, String)> summary(List<MediaGroup> gs) => [
      for (final g in gs)
        (g.id, g.folder, g.seriesKey, pathsOf(g.files).join(' | ')),
    ];

    final forward = summary(build(paths));
    expect(summary(build(paths.reversed.toList())), forward);
    expect(
      [for (final g in forward) (g.$1, g.$3)],
      [('g1', 'alpha'), ('g2', 'gamma'), ('g3', 'beta')],
    );
  });

  test('titleGuess takes the most common video title', () {
    final g = build([
      'Mixed/[A] Foo - 01.mkv',
      'Mixed/[B] Foo - 02.mkv',
      'Mixed/Foo.S01E03.mkv',
      'Mixed/FOO - 04.mkv',
    ]).single;

    expect(g.titleGuess, 'Foo');
  });
}
