import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/organize/filename_parser.dart';
import 'package:jellyfin_media_management_tool/services/organize/grouping.dart';
import 'package:jellyfin_media_management_tool/services/organize/jellyfin_naming.dart';
import 'package:path/path.dart' as p;

MediaGroup single(List<String> paths) {
  final groups = Grouping.build([
    for (final path in paths) FilenameParser.parse(p.joinAll(path.split('/'))),
  ]);
  expect(groups, hasLength(1));
  return groups.single;
}

/// Source (written with `/`) → target.
Map<String, String?> targetsOf(List<PlannedTarget> plan) => {
  for (final t in plan) p.split(t.file.relativePath).join('/'): t.target,
};

Map<String, String?> problemsOf(List<PlannedTarget> plan) => {
  for (final t in plan) p.split(t.file.relativePath).join('/'): t.problem,
};

const show = GroupDecision(
  type: GroupMediaType.series,
  title: 'Show',
  year: 2020,
);
const heat = GroupDecision(
  type: GroupMediaType.movie,
  title: 'Heat',
  year: 1995,
);

void main() {
  group('sanitize', () {
    test('removes characters Windows forbids', () {
      final backslash = String.fromCharCode(0x5C);
      expect(
        JellyfinNaming.sanitize(
          'Re:Zero <Kara> "Hajimeru" a/b${backslash}c|d?e*',
        ),
        'ReZero Kara Hajimeru abcde',
      );
    });

    test('removes control characters and collapses whitespace', () {
      final tab = String.fromCharCode(9);
      final bell = String.fromCharCode(7);
      expect(
        JellyfinNaming.sanitize('Tab${tab}bed$bell  here'),
        'Tab bed here',
      );
      expect(JellyfinNaming.sanitize('  Some   Title  '), 'Some Title');
    });

    test('trims trailing dots and spaces', () {
      expect(JellyfinNaming.sanitize('Title...'), 'Title');
      expect(JellyfinNaming.sanitize('Mr. Robot. . '), 'Mr. Robot');
    });

    test('suffixes reserved device names', () {
      expect(JellyfinNaming.sanitize('con'), 'con_');
      expect(JellyfinNaming.sanitize('Con Air'), 'Con Air');
    });
  });

  group('titleFolder', () {
    test('movie and series, with and without a year', () {
      expect(JellyfinNaming.titleFolder(heat), 'Movies/Heat (1995)');
      expect(
        JellyfinNaming.titleFolder(
          const GroupDecision(type: GroupMediaType.series, title: 'Show'),
        ),
        'Shows/Show',
      );
      expect(
        JellyfinNaming.titleFolder(
          const GroupDecision(
            type: GroupMediaType.series,
            title: 'Re:Zero',
            year: 2016,
          ),
        ),
        'Shows/ReZero (2016)',
      );
    });

    test('refuses an undecided type', () {
      expect(
        () => JellyfinNaming.titleFolder(
          const GroupDecision(type: GroupMediaType.unknown, title: 'X'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('series', () {
    test('episodes go into season folders', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 01.mkv', 'Show/Show - 02.mp4']),
        show,
      );

      expect(targetsOf(plan), {
        'Show/Show - 01.mkv': 'Shows/Show (2020)/Season 01/Show S01E01.mkv',
        'Show/Show - 02.mp4': 'Shows/Show (2020)/Season 01/Show S01E02.mp4',
      });
      expect(plan.every((t) => t.problem == null), isTrue);
    });

    test('season comes from the file, then the decision, then 1', () {
      final group = single(['Show/Show S03E04.mkv', 'Show/Show - 05.mkv']);

      expect(
        targetsOf(
          JellyfinNaming.plan(
            group,
            const GroupDecision(
              type: GroupMediaType.series,
              title: 'Show',
              season: 2,
            ),
          ),
        ),
        {
          'Show/Show S03E04.mkv': 'Shows/Show/Season 03/Show S03E04.mkv',
          'Show/Show - 05.mkv': 'Shows/Show/Season 02/Show S02E05.mkv',
        },
      );
      expect(
        targetsOf(JellyfinNaming.plan(group, show))['Show/Show - 05.mkv'],
        'Shows/Show (2020)/Season 01/Show S01E05.mkv',
      );
    });

    test('specials go to season 00', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 01.mkv', 'Show/Show SP01.mkv']),
        show,
      );

      expect(
        targetsOf(plan)['Show/Show SP01.mkv'],
        'Shows/Show (2020)/Season 00/Show S00E01.mkv',
      );
    });

    test('a half episode keeps its label in season 00', () {
      final plan = JellyfinNaming.plan(
        single([
          'Show/Show - 18.mkv',
          'Show/Show - 18.5 Recap.mkv',
          'Show/Show - 19.mkv',
        ]),
        show,
      );

      // Jellyfin reads S01E18.5 as a second episode 18, and its docs ask for a
      // descriptive name in Season 00 for a special the metadata source lacks.
      expect(targetsOf(plan), {
        'Show/Show - 18.mkv': 'Shows/Show (2020)/Season 01/Show S01E18.mkv',
        'Show/Show - 18.5 Recap.mkv':
            'Shows/Show (2020)/Season 00/Show - 18.5 Recap.mkv',
        'Show/Show - 19.mkv': 'Shows/Show (2020)/Season 01/Show S01E19.mkv',
      });
    });

    test('the episode offset renumbers regular episodes only', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 13.mkv', 'Show/Show SP02.mkv']),
        const GroupDecision(
          type: GroupMediaType.series,
          title: 'Show',
          season: 2,
          episodeOffset: -12,
        ),
      );

      expect(targetsOf(plan), {
        'Show/Show - 13.mkv': 'Shows/Show/Season 02/Show S02E01.mkv',
        'Show/Show SP02.mkv': 'Shows/Show/Season 00/Show S00E02.mkv',
      });
    });

    test('an offset that goes below zero is refused', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 01.mkv']),
        const GroupDecision(
          type: GroupMediaType.series,
          title: 'Show',
          episodeOffset: -5,
        ),
      );

      expect(plan.single.target, isNull);
      expect(plan.single.problem, 'episode offset below zero');
    });

    test('multi-episode files', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show S01E01-E02.mkv']),
        show,
      );

      expect(
        plan.single.target,
        'Shows/Show (2020)/Season 01/Show S01E01-E02.mkv',
      );
    });

    test('numbers are padded to at least two digits', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 105.mkv', 'Show/Show S12E03.mkv']),
        show,
      );

      expect(targetsOf(plan), {
        'Show/Show S12E03.mkv': 'Shows/Show (2020)/Season 12/Show S12E03.mkv',
        'Show/Show - 105.mkv': 'Shows/Show (2020)/Season 01/Show S01E105.mkv',
      });
    });

    test('a video without an episode number needs review', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 01.mkv', 'Show/Show.mkv']),
        show,
      );

      expect(targetsOf(plan)['Show/Show.mkv'], isNull);
      expect(problemsOf(plan)['Show/Show.mkv'], 'no episode number');
      expect(targetsOf(plan)['Show/Show - 01.mkv'], isNotNull);
    });

    test(
      'two videos on one target both need review, and so do their companions',
      () {
        final plan = JellyfinNaming.plan(
          single([
            'Show/[A] Show - 01.mkv',
            'Show/[B] Show - 01.mkv',
            'Show/[A] Show - 01.chs.ass',
          ]),
          show,
        );

        expect(problemsOf(plan), {
          'Show/[A] Show - 01.mkv': 'duplicate target',
          'Show/[B] Show - 01.mkv': 'duplicate target',
          'Show/[A] Show - 01.chs.ass': 'its video could not be placed',
        });
        expect(plan.every((t) => t.target == null), isTrue);
      },
    );
  });

  group('movie', () {
    test('a single video', () {
      final group = single(['Heat/Heat.1995.1080p.BluRay.mkv']);

      expect(
        JellyfinNaming.plan(group, heat).single.target,
        'Movies/Heat (1995)/Heat (1995).mkv',
      );
      expect(
        JellyfinNaming.plan(
          group,
          const GroupDecision(type: GroupMediaType.movie, title: 'Heat'),
        ).single.target,
        'Movies/Heat/Heat.mkv',
      );
    });

    test('parts', () {
      final plan = JellyfinNaming.plan(
        single(['Film/Film - cd1.mkv', 'Film/Film - cd2.mkv']),
        const GroupDecision(
          type: GroupMediaType.movie,
          title: 'Film',
          year: 2001,
        ),
      );

      expect(targetsOf(plan), {
        'Film/Film - cd1.mkv': 'Movies/Film (2001)/Film (2001) - part1.mkv',
        'Film/Film - cd2.mkv': 'Movies/Film (2001)/Film (2001) - part2.mkv',
      });
    });

    test('several videos without distinct parts need review', () {
      for (final paths in [
        ['Film/Film 1080p.mkv', 'Film/Film 720p.mkv'],
        ['Film/Film - cd1.mkv', 'Film/Film cd1 720p.mkv'],
      ]) {
        final plan = JellyfinNaming.plan(single(paths), heat);

        expect(plan.map((t) => t.target), everyElement(isNull));
        expect(
          plan.map((t) => t.problem),
          everyElement('several videos, no part numbers'),
        );
      }
    });
  });

  group('extras', () {
    test('a movie trailer', () {
      final plan = JellyfinNaming.plan(
        single(['Heat/Heat (1995).mkv', 'Heat/Heat (1995)-trailer.mkv']),
        heat,
      );

      expect(targetsOf(plan), {
        'Heat/Heat (1995).mkv': 'Movies/Heat (1995)/Heat (1995).mkv',
        'Heat/Heat (1995)-trailer.mkv':
            'Movies/Heat (1995)/trailers/Heat (1995)-trailer.mkv',
      });
    });

    test('a series creditless opening', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 01.mkv', 'Show/Show - NCOP1.mkv']),
        show,
      );

      expect(
        targetsOf(plan)['Show/Show - NCOP1.mkv'],
        'Shows/Show (2020)/extras/Show - NCOP1.mkv',
      );
    });
  });

  group('companions of one video', () {
    test('follow the video by kind', () {
      final plan = JellyfinNaming.plan(
        single([
          'Show/Show - 01.mkv',
          'Show/Show - 01.chs.ass',
          'Show/Show - 01.srt',
          'Show/Show - 01.jpg',
          'Show/Show - 01.nfo',
          'Show/Show - 01.txt',
        ]),
        show,
      );

      const episode = 'Shows/Show (2020)/Season 01/Show S01E01';
      expect(targetsOf(plan), {
        'Show/Show - 01.mkv': '$episode.mkv',
        'Show/Show - 01.chs.ass': '$episode.zh-Hans.ass',
        'Show/Show - 01.jpg': '$episode-thumb.jpg',
        'Show/Show - 01.nfo': '$episode.nfo',
        'Show/Show - 01.srt': '$episode.srt',
        'Show/Show - 01.txt': 'Shows/Show (2020)/Season 01/Show - 01.txt',
      });
    });

    test('need review when their video does', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show.mkv', 'Show/Show.chs.ass']),
        show,
      );

      expect(problemsOf(plan), {
        'Show/Show.mkv': 'no episode number',
        'Show/Show.chs.ass': 'its video could not be placed',
      });
    });
  });

  group('folder-level companions', () {
    test('series artwork and tvshow.nfo', () {
      final plan = JellyfinNaming.plan(
        single(['Show/Show - 01.mkv', 'Show/tvshow.nfo', 'Show/poster.jpg']),
        show,
      );

      expect(
        targetsOf(plan)['Show/tvshow.nfo'],
        'Shows/Show (2020)/tvshow.nfo',
      );
      expect(
        targetsOf(plan)['Show/poster.jpg'],
        'Shows/Show (2020)/poster.jpg',
      );
    });

    test('movie nfo, artwork, and a subtitle for the lone video', () {
      final plan = JellyfinNaming.plan(
        single([
          'Heat/Heat (1995).mkv',
          'Heat/info.nfo',
          'Heat/folder.jpg',
          'Heat/Heat.1995.BluRay.en.srt',
        ]),
        heat,
      );

      expect(targetsOf(plan), {
        'Heat/Heat (1995).mkv': 'Movies/Heat (1995)/Heat (1995).mkv',
        'Heat/Heat.1995.BluRay.en.srt': 'Movies/Heat (1995)/Heat (1995).en.srt',
        'Heat/folder.jpg': 'Movies/Heat (1995)/folder.jpg',
        'Heat/info.nfo': 'Movies/Heat (1995)/movie.nfo',
      });
    });

    test('colliding companions need review; the video is kept', () {
      final plan = JellyfinNaming.plan(
        single([
          'Show/Season 1/Show S01E01.mkv',
          'Show/Season 1/poster.jpg',
          'Show/poster.jpg',
        ]),
        show,
      );

      expect(problemsOf(plan), {
        'Show/Season 1/Show S01E01.mkv': null,
        'Show/Season 1/poster.jpg': 'duplicate target',
        'Show/poster.jpg': 'duplicate target',
      });
    });

    test('a companion-only group', () {
      final plan = JellyfinNaming.plan(
        single(['Artwork/cover.jpg']),
        const GroupDecision(type: GroupMediaType.movie, title: 'X'),
      );

      expect(plan.single.target, 'Movies/X/cover.jpg');
    });
  });

  group('refusals', () {
    // Built per test: expect() inside single() cannot run at declaration time.
    MediaGroup showGroup() => single(['Show/Show - 01.mkv', 'Show/poster.jpg']);

    test('unknown type', () {
      final plan = JellyfinNaming.plan(
        showGroup(),
        const GroupDecision(type: GroupMediaType.unknown, title: 'Show'),
      );

      expect(plan.map((t) => t.target), everyElement(isNull));
      expect(plan.map((t) => t.problem), everyElement('not decided'));
    });

    test('a title that is empty after sanitizing', () {
      for (final title in ['', '   ', '???']) {
        final plan = JellyfinNaming.plan(
          showGroup(),
          GroupDecision(type: GroupMediaType.series, title: title),
        );

        expect(plan.map((t) => t.target), everyElement(isNull));
        expect(plan.map((t) => t.problem), everyElement('no title'));
      }
    });

    test('the title is sanitized in every segment', () {
      final plan = JellyfinNaming.plan(
        showGroup(),
        const GroupDecision(type: GroupMediaType.series, title: 'Re:Zero'),
      );

      expect(targetsOf(plan), {
        'Show/Show - 01.mkv': 'Shows/ReZero/Season 01/ReZero S01E01.mkv',
        'Show/poster.jpg': 'Shows/ReZero/poster.jpg',
      });
    });

    test('targets come back in group.files order', () {
      final g = showGroup();
      final plan = JellyfinNaming.plan(g, show);

      expect([for (final t in plan) t.file], g.files);
    });
  });
}
