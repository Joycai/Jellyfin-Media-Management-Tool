import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/organize/filename_parser.dart';
import 'package:path/path.dart' as p;

/// Paths are written with `/` for readability and handed over with the
/// platform separator, the way a directory scan produces them.
ParsedFile parse(String path) =>
    FilenameParser.parse(p.joinAll(path.split('/')));

void main() {
  group('episodes', () {
    test('fansub release with group, resolution and language tags', () {
      final f = parse('[SubGroup] Some Show - 01 [1080p][CHS].mkv');

      expect(f.episode, 1);
      expect(f.season, isNull);
      expect(f.year, isNull);
      expect(f.titleGuess, 'Some Show');
      expect(f.language, 'zh-Hans');
      expect(f.kind, 'Video');
      expect(f.extension, '.mkv');
      expect(f.baseName, '[SubGroup] Some Show - 01 [1080p][CHS]');
      expect(f.folder, '');
    });

    test('scene release SxxEyy', () {
      final f = parse('Some.Show.S01E02.1080p.WEB-DL.x265.mkv');

      expect(f.season, 1);
      expect(f.episode, 2);
      expect(f.titleGuess, 'Some Show');
    });

    for (final name in [
      'Some Show S2 - 05.mkv',
      'Some Show Season 2 - 05.mkv',
      'Some Show 第二季 05.mkv',
      'Some Show 第2季 第05话.mkv',
      'Some Show 2nd Season - 05.mkv',
    ]) {
      test('season and episode in "$name"', () {
        final f = parse(name);

        expect(f.season, 2);
        expect(f.episode, 5);
        expect(f.titleGuess, 'Some Show');
      });
    }

    for (final name in [
      '[Group] Title [01][1080p].mkv',
      'Title EP01.mkv',
      'Title E01.mkv',
      'Title 第01集.mp4',
      'Title - 01v2.mkv',
      'Title [01v2].mkv',
    ]) {
      test('episode 1 in "$name"', () {
        final f = parse(name);

        expect(f.episode, 1);
        expect(f.episodeEnd, isNull);
        expect(f.titleGuess, 'Title');
      });
    }

    for (final name in [
      'Title S01E01-E02.mkv',
      'Title S01E01E02.mkv',
      'Title - 01-02.mkv',
      '[Group] Title [01-02][720p].mkv',
    ]) {
      test('multi-episode "$name"', () {
        final f = parse(name);

        expect(f.episode, 1);
        expect(f.episodeEnd, 2);
        expect(f.titleGuess, 'Title');
      });
    }

    test('1x05 form', () {
      final f = parse('Show 1x05.mkv');

      expect(f.season, 1);
      expect(f.episode, 5);
      expect(f.titleGuess, 'Show');
    });

    test('Chinese numerals', () {
      expect(parse('Show 第二十三话.mkv').episode, 23);
      final f = parse('Show 第十二季 第03集.mkv');
      expect(f.season, 12);
      expect(f.episode, 3);
    });

    test('an episode name after the number stays out of the title', () {
      final a = parse('Show - 01 - The Pilot.mkv');
      final b = parse('Show S01E02 Another Story.mkv');

      expect(a.titleGuess, 'Show');
      expect(b.titleGuess, 'Show');
      expect(a.seriesKey, b.seriesKey);
    });

    test('a title kept inside brackets', () {
      final f = parse('[Group][Title][01][1080p].mkv');

      expect(f.titleGuess, 'Title');
      expect(f.episode, 1);
    });

    test('a dashed episode may equal a resolution value', () {
      expect(parse('One Piece - 1080 [1080p].mkv').episode, 1080);
    });
  });

  group('never an episode', () {
    for (final name in [
      'Title [1080p].mkv',
      'Title 720p.mkv',
      'Title 2160p HDR.mkv',
      'Title 4K.mkv',
      'Title [1080].mkv',
      'Title [ABCD1234].mkv',
      'Title [12345678].mkv',
      'Title x264.mkv',
      'Title H.264.mkv',
      'Title HEVC 10bit.mkv',
      'Title AAC2.0.mkv',
      'Title DTS-5.1.mkv',
      'Title.7.1.mkv',
      'Title [DDP5.1].mkv',
    ]) {
      test('"$name"', () {
        final f = parse(name);

        expect(f.episode, isNull);
        expect(f.season, isNull);
        expect(f.titleGuess, 'Title');
      });
    }

    test('years', () {
      final bare = parse('Title 2019.mkv');
      expect(bare.year, 2019);
      expect(bare.episode, isNull);

      final bracketed = parse('[Group] Title [2019][1080p].mkv');
      expect(bracketed.year, 2019);
      expect(bracketed.episode, isNull);
      expect(bracketed.titleGuess, 'Title');
    });
  });

  group('movies', () {
    test('scene movie release', () {
      final f = parse('Movie.Name.2019.1080p.BluRay.x264.DTS-5.1.mkv');

      expect(f.year, 2019);
      expect(f.episode, isNull);
      expect(f.season, isNull);
      expect(f.titleGuess, 'Movie Name');
    });

    test('a parenthesized year outranks a year-like title word', () {
      final f = parse('Blade Runner 2049 (2017).mkv');

      expect(f.year, 2017);
      expect(f.episode, isNull);
      expect(f.titleGuess, 'Blade Runner 2049');
    });

    test('a sequel number beside a year is not an episode', () {
      final f = parse("Ocean's 11 (2001).mkv");

      expect(f.episode, isNull);
      expect(f.titleGuess, "Ocean's 11");
    });

    test('a title starting with a year keeps it', () {
      final f = parse('2001 A Space Odyssey 1968.mkv');

      expect(f.year, 1968);
      expect(f.titleGuess, '2001 A Space Odyssey');
    });

    test('a title that is a year', () {
      final f = parse('1917.mkv');

      expect(f.titleGuess, '1917');
      expect(f.year, isNull);
      expect(f.episode, isNull);
    });

    test('title words that look like tags', () {
      expect(parse('The Menu (2022).mkv').extraType, isNull);
      expect(parse('The Menu (2022).mkv').titleGuess, 'The Menu');
      expect(parse("Charlotte's Web (1973).mkv").titleGuess, "Charlotte's Web");
    });

    test('parts', () {
      final cd = parse('Title (2020) - cd1.mkv');
      expect(cd.part, 1);
      expect(cd.year, 2020);
      expect(cd.episode, isNull);
      expect(cd.titleGuess, 'Title');

      expect(parse('Title - part2.mkv').part, 2);
      expect(parse('Title.disc3.mkv').part, 3);
    });

    test('"Part 1" as a title word is not a part', () {
      final f = parse('Harry Potter Part 1 (2010).mkv');

      expect(f.part, isNull);
      expect(f.titleGuess, 'Harry Potter Part 1');
    });
  });

  group('specials', () {
    test('OVA without a number', () {
      final f = parse('Title - OVA.mkv');

      expect(f.special, isTrue);
      expect(f.episode, isNull);
      expect(f.titleGuess, 'Title');
    });

    test('SP01', () {
      final f = parse('Title SP01.mkv');

      expect(f.special, isTrue);
      expect(f.episode, 1);
      expect(f.titleGuess, 'Title');
    });

    test('Special 02', () {
      final f = parse('Title - Special 02.mkv');

      expect(f.special, isTrue);
      expect(f.episode, 2);
      expect(f.titleGuess, 'Title');
    });

    test('特别篇', () {
      expect(parse('Title 特别篇.mkv').special, isTrue);
    });

    test('"Special" as an ordinary title word', () {
      final f = parse('Special Forces (2011).mkv');

      expect(f.special, isFalse);
      expect(f.titleGuess, 'Special Forces');
    });

    test('a file inside a Specials folder', () {
      final f = parse('Show/Specials/Show - 01.mkv');

      expect(f.special, isTrue);
      expect(f.episode, 1);
    });
  });

  group('extras', () {
    for (final name in [
      'Title - NCOP1.mkv',
      '[Group] Title [NCED][1080p].mkv',
      'Title PV1.mkv',
      'Title CM01.mkv',
      'Title - Menu.mkv',
      '[Group] Title [Menu01].mkv',
    ]) {
      test('anime extra "$name"', () {
        final f = parse(name);

        expect(f.extraType, 'extras');
        expect(f.titleGuess, 'Title');
      });
    }

    const suffixes = {
      'trailer': 'trailers',
      'featurette': 'featurettes',
      'interview': 'interviews',
      'deleted': 'deleted scenes',
      'behindthescenes': 'behind the scenes',
      'scene': 'scenes',
      'short': 'shorts',
    };
    for (final MapEntry(key: suffix, value: folder) in suffixes.entries) {
      test('Jellyfin suffix -$suffix', () {
        final f = parse('Movie (2020)-$suffix.mkv');

        expect(f.extraType, folder);
        expect(f.year, 2020);
        expect(f.titleGuess, 'Movie');
        expect(f.seriesKey, parse('Movie (2020).mkv').seriesKey);
      });
    }

    test('videos inside an extras folder', () {
      expect(parse('Movie/Extras/Making Of.mkv').extraType, 'extras');
      expect(parse('Movie/Trailers/Teaser.mkv').extraType, 'trailers');
    });
  });

  group('language', () {
    const cases = {
      'Title - 01.chs.ass': 'zh-Hans',
      'Title - 01.sc.ass': 'zh-Hans',
      'Title - 01.cht.ass': 'zh-Hant',
      'Title - 01.tc.ass': 'zh-Hant',
      'Title - 01.zh.srt': 'zh',
      'Title - 01.zh-CN.srt': 'zh-Hans',
      'Title - 01.jpn.ass': 'ja',
      'Title - 01.ja.srt': 'ja',
      'Title - 01.eng.srt': 'en',
      'Title - 01.en.srt': 'en',
      'Title - 01.kor.srt': 'ko',
      'Title - 01.fre.srt': 'fre',
      'Title - 01.chs&jpn.ass': 'zh-Hans',
      'Title - 01.eng.forced.srt': 'en',
      'Title - 01 [简体].ass': 'zh-Hans',
      'Title - 01 [繁體].ass': 'zh-Hant',
    };
    for (final MapEntry(key: name, value: language) in cases.entries) {
      test('"$name" is $language', () {
        final f = parse(name);

        expect(f.language, language);
        expect(f.kind, 'Subtitle');
        expect(f.episode, 1);
        expect(f.titleGuess, 'Title');
        expect(f.seriesKey, parse('Title - 01.mkv').seriesKey);
      });
    }

    test('an ordinary word in the tail is not a language', () {
      final f = parse('Movie.The.End.srt');

      expect(f.language, isNull);
      expect(f.titleGuess, 'Movie The End');
    });

    test('a video keeps its dotted tail as release tags', () {
      expect(parse('Some.Show.S01E01.WEB.mkv').language, isNull);
    });
  });

  group('bare names', () {
    test('01.mkv at the root', () {
      final f = parse('01.mkv');

      expect(f.episode, 1);
      expect(f.titleGuess, '');
      expect(f.seriesKey, 'folder:');
      expect(f.folder, '');
    });

    test('S01E01.mkv', () {
      final f = parse('S01E01.mkv');

      expect(f.season, 1);
      expect(f.episode, 1);
      expect(f.titleGuess, '');
    });

    test('a season folder supplies the season and its parent the key', () {
      final f = parse('Show/Season 2/01.mkv');

      expect(f.season, 2);
      expect(f.episode, 1);
      expect(f.folder, p.join('Show', 'Season 2'));
      expect(f.seriesKey, 'folder:show');
    });

    test('nested folder key', () {
      expect(parse('Library/Anime/03.mkv').seriesKey, 'folder:library/anime');
    });
  });

  group('seriesKey', () {
    test('ignores release groups, tags, separators and episode numbers', () {
      final keys = {
        for (final name in [
          '[GroupA] Some Show - 01 [1080p].mkv',
          '[GroupB] Some Show - 12 [720p][CHS].mkv',
          'Some.Show.S01E03.1080p.WEB-DL.mkv',
          'Some_Show_-_04_[ABCD1234].mkv',
          'SOME SHOW - 05v2.mkv',
          'Some Show - 05.chs.ass',
        ])
          parse(name).seriesKey,
      };

      expect(keys, {'some show'});
    });

    test('different titles differ', () {
      expect(
        parse('Alpha - 01.mkv').seriesKey,
        isNot(parse('Beta - 01.mkv').seriesKey),
      );
    });

    test('extension is lowercased before labelling', () {
      final f = parse('Show - 01.MKV');

      expect(f.extension, '.mkv');
      expect(f.kind, 'Video');
    });
  });

  group('folders', () {
    test('isContainerFolder', () {
      for (final name in [
        'Season 1',
        'season 02',
        'S2',
        'Specials',
        'SPs',
        'Extras',
        'CDs',
        'CD1',
        '第二季',
        'Trailers',
      ]) {
        expect(FilenameParser.isContainerFolder(name), isTrue, reason: name);
      }
      for (final name in ['Show', 'Downloads', 'Some Show (2020)']) {
        expect(FilenameParser.isContainerFolder(name), isFalse, reason: name);
      }
    });

    test('containerParent', () {
      expect(
        FilenameParser.containerParent(p.join('Show', 'Season 1')),
        'Show',
      );
      expect(
        FilenameParser.containerParent(p.join('Show', 'Season 1', 'Extras')),
        'Show',
      );
      expect(FilenameParser.containerParent('Show'), 'Show');
      expect(FilenameParser.containerParent('Season 1'), '');
      expect(FilenameParser.containerParent(''), '');
    });
  });
}
