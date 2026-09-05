import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_merge.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_reader.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_writer.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_role.dart';

MediaMetadata _sample() => MediaMetadata(
  title: '美少女戦士セーラーディオーレ 絶望の餌食',
  code: 'SPSF-43',
  plot: 'セーラーディオーレは…[BAD END]',
  outline: '監督コメント本文。',
  premiered: '2026-08-14',
  runtimeMinutes: 85,
  rating: 3.5,
  studio: 'GIGA',
  series: 'SPSF',
  director: '坂田徹',
  genres: ['セーラー服', 'ツインテール'],
  tags: ['セーラーヒロイン'],
  actors: [const MetadataActor(name: '西元めいさ')],
  posterUrl: 'https://example.invalid/pac_s.jpg',
  sourceUrl: 'https://www.giga-web.jp/product/index.php?product_id=7743',
);

void main() {
  group('NfoWriter', () {
    test('writes a movie NFO Jellyfin can read', () {
      final xml = NfoWriter.write(_sample());

      expect(xml, startsWith('<?xml version="1.0" encoding="utf-8"'));
      expect(xml, contains('<movie>'));
      expect(
        xml,
        contains('<originaltitle>美少女戦士セーラーディオーレ 絶望の餌食</originaltitle>'),
      );
      expect(xml, contains('<sorttitle>SPSF43</sorttitle>'));
      expect(xml, contains('<premiered>2026-08-14</premiered>'));
      expect(xml, contains('<year>2026</year>'));
      expect(xml, contains('<runtime>85</runtime>'));
      expect(xml, contains('<studio>GIGA</studio>'));
      expect(xml, contains('<name>SPSF</name>')); // inside <set>
      expect(xml, contains('<genre>セーラー服</genre>'));
      expect(xml, contains('<tag>セーラーヒロイン</tag>'));
      expect(xml, contains('<name>西元めいさ</name>'));
      expect(
        xml,
        contains('<uniqueid type="custom" default="true">SPSF-43</uniqueid>'),
      );
    });

    test('builds the display title as code, name, year', () {
      // Calibrated against a real Jellyfin-written NFO: the code loses its
      // separator (so SPSF9 / SPSF10 / SPSF43 sort correctly) and the year is
      // appended. The catalogue number survives verbatim in <uniqueid>.
      final xml = NfoWriter.write(_sample());
      expect(
        xml,
        contains('<title>SPSF43 美少女戦士セーラーディオーレ 絶望の餌食 (2026)</title>'),
      );
      expect(
        xml,
        contains('<originaltitle>美少女戦士セーラーディオーレ 絶望の餌食</originaltitle>'),
      );
      expect(xml, contains('>SPSF-43</uniqueid>'));
    });

    test('does not double up a code the title already carries', () {
      // Matched with separators ignored, so the hyphenated form on the page is
      // recognised as the compact form we would have added.
      final m = _sample()..title = 'SPSF-43 Already Prefixed';
      expect(
        NfoWriter.write(m),
        contains('<title>SPSF-43 Already Prefixed (2026)</title>'),
      );
    });

    test('does not double up a year the title already carries', () {
      final m = _sample()..title = '美少女戦士 (2026)';
      expect(
        NfoWriter.write(m),
        contains('<title>SPSF43 美少女戦士 (2026)</title>'),
      );
    });

    test('prefixing can be turned off', () {
      final xml = NfoWriter.write(
        _sample(),
        options: const NfoOptions(
          prefixTitleWithCode: false,
          titleIncludesYear: false,
        ),
      );
      expect(xml, contains('<title>美少女戦士セーラーディオーレ 絶望の餌食</title>'));
    });

    test('the hyphenated code can be kept', () {
      final xml = NfoWriter.write(
        _sample(),
        options: const NfoOptions(compactCodeInTitles: false),
      );
      expect(xml, contains('<sorttitle>SPSF-43</sorttitle>'));
      expect(
        xml,
        contains('<title>SPSF-43 美少女戦士セーラーディオーレ 絶望の餌食 (2026)</title>'),
      );
    });

    test('omits empty elements entirely', () {
      // An empty <plot/> is not "no plot" to Jellyfin — it is a plot that
      // happens to be blank, and it will overwrite a good one.
      final xml = NfoWriter.write(MediaMetadata(title: 'Only A Title'));
      expect(xml, isNot(contains('<plot')));
      expect(xml, isNot(contains('<runtime')));
      expect(xml, isNot(contains('<set>')));
      expect(xml, isNot(contains('<uniqueid')));
    });

    test('records the source URL as a comment', () {
      expect(
        NfoWriter.write(_sample()),
        contains('scraped from https://www.giga-web.jp/product/'),
      );
    });

    test('names the art files it is told the writer will create', () {
      final xml = NfoWriter.write(
        _sample()..fanartUrl = 'https://example.invalid/001.png',
        options: const NfoOptions(
          posterFileName: 'poster.png',
          fanartFileName: 'fanart.png',
        ),
      );
      expect(xml, contains('<poster>poster.png</poster>'));
      expect(xml, contains('<fanart>fanart.png</fanart>'));
    });

    test('the default art names are the ones the images are saved under', () {
      // NfoOptions restates the stems rather than importing ImageRole, so this
      // is what stops the <art> block and the files on disk drifting apart.
      const options = NfoOptions();
      expect(options.posterFileName, '${ImageRole.poster.stem}.jpg');
      expect(options.fanartFileName, '${ImageRole.fanart.stem}.jpg');
      expect(
        NfoWriter.write(_sample()),
        contains('<poster>folder.jpg</poster>'),
      );
    });

    test('kinds map to and from Jellyfin file names and root elements', () {
      expect(NfoKind.movie.fileName, 'movie.nfo');
      expect(NfoKind.tvShow.fileName, 'tvshow.nfo');
      expect(NfoKind.forFileName('tvshow.nfo'), NfoKind.tvShow);
      expect(NfoKind.forFileName('TVSHOW.NFO'), NfoKind.tvShow);
      expect(NfoKind.forFileName('movie.nfo'), NfoKind.movie);
      expect(NfoKind.forFileName('SPSF-43.nfo'), NfoKind.movie);
      expect(NfoKind.fromRootElement('tvshow'), NfoKind.tvShow);
      expect(NfoKind.fromRootElement('episodedetails'), NfoKind.episode);
      expect(NfoKind.fromRootElement('video'), isNull);
    });

    test('emits the right root element per kind', () {
      expect(
        NfoWriter.write(_sample(), kind: NfoKind.episode),
        contains('<episodedetails>'),
      );
      expect(
        NfoWriter.write(_sample(), kind: NfoKind.tvShow),
        contains('<tvshow>'),
      );
    });
  });

  group('preserving an existing NFO', () {
    const existing = '''
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <title>Old Title</title>
  <plot>Old plot.</plot>
  <userrating>9</userrating>
  <playcount>3</playcount>
  <fileinfo><streamdetails><video><codec>hevc</codec></video></streamdetails></fileinfo>
</movie>
''';

    test('keeps elements this tool does not manage', () {
      // Someone else's scraper, or the user's own edits, must survive a
      // re-scrape. Losing watch state to a metadata refresh is unacceptable.
      final xml = NfoWriter.write(_sample(), existingXml: existing);
      expect(xml, contains('<userrating>9</userrating>'));
      expect(xml, contains('<playcount>3</playcount>'));
      expect(xml, contains('<codec>hevc</codec>'));
    });

    test('replaces the elements it does manage exactly once', () {
      final xml = NfoWriter.write(_sample(), existingXml: existing);
      expect(xml, isNot(contains('Old Title')));
      expect(xml, isNot(contains('Old plot.')));
      expect('<plot>'.allMatches(xml), hasLength(1));
      expect('<title>'.allMatches(xml), hasLength(1));
    });

    test('an unparseable previous file is ignored rather than fatal', () {
      final xml = NfoWriter.write(_sample(), existingXml: 'not xml at all <<<');
      expect(xml, contains('<movie>'));
      expect(xml, contains('SPSF-43'));
    });
  });

  group('a real Jellyfin-written NFO', () {
    // Verbatim from a library, trimmed only where it repeats. This is the
    // shape our output has to survive contact with: Jellyfin's own bookkeeping
    // (lockdata, dateadded), probed stream details, and a curated set of
    // genres and tags that took someone effort to get right.
    const jellyfin = '''
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <plot>セーラーディオーレは…[BAD END]</plot>
  <lockdata>false</lockdata>
  <dateadded>2026-07-31 00:00:00</dateadded>
  <title>SPSF43 美少女戦士セーラーディオーレ 絶望の餌食 (2026)</title>
  <originaltitle>美少女戦士セーラーディオーレ 絶望の餌食</originaltitle>
  <director>坂田徹</director>
  <year>2026</year>
  <sorttitle>SPSF43</sorttitle>
  <premiered>2026-08-14</premiered>
  <releasedate>2026-08-14</releasedate>
  <runtime>28</runtime>
  <genre>セーラーディオーレ</genre>
  <studio>ＧＩＧＡ（ギガ）</studio>
  <tag>リボンレオタード</tag>
  <art>
    <poster>/media/GIGA/SPSF43 …/folder.jpg</poster>
  </art>
  <actor>
    <name>西元めいさ</name>
    <role>セーラーディオーレ</role>
    <type>Actor</type>
  </actor>
  <fileinfo>
    <streamdetails>
      <video><codec>h264</codec><width>1000</width><durationinseconds>1696</durationinseconds></video>
      <audio><codec>aac</codec><channels>2</channels></audio>
    </streamdetails>
  </fileinfo>
</movie>
''';

    test('keeps Jellyfin\'s own bookkeeping and probed stream details', () {
      final xml = NfoWriter.write(_sample(), existingXml: jellyfin);

      expect(xml, contains('<lockdata>false</lockdata>'));
      expect(xml, contains('<dateadded>2026-07-31 00:00:00</dateadded>'));
      expect(xml, contains('<durationinseconds>1696</durationinseconds>'));
      expect(xml, contains('<channels>2</channels>'));
    });

    test('re-writing it produces the same title it already had', () {
      // The strongest signal that the format is calibrated: scraping a file
      // Jellyfin already wrote should not churn the field it cares most about.
      final xml = NfoWriter.write(_sample(), existingXml: jellyfin);
      expect(
        xml,
        contains('<title>SPSF43 美少女戦士セーラーディオーレ 絶望の餌食 (2026)</title>'),
      );
      expect(xml, contains('<sorttitle>SPSF43</sorttitle>'));
      expect('<title>'.allMatches(xml), hasLength(1));
    });

    test('the runtime the user has is not replaced by the page\'s', () {
      // Their file is a 28-minute cut; the product page advertises 85. A
      // conflict defaults to keep, so the truth about the file on disk wins.
      final existing = NfoReader.read(jellyfin)!;
      final plan = NfoMerge.suggest(existing, _sample());
      final merged = NfoMerge.resolve(existing, _sample(), plan);

      expect(
        plan.decisionFor(MetadataField.runtimeMinutes),
        MergeDecision.keep,
      );
      expect(merged.runtimeMinutes, 28);
    });
  });

  group('round-trip', () {
    test('everything written can be read back', () {
      final original = _sample();
      final restored = NfoReader.read(NfoWriter.write(original));

      expect(restored, isNotNull);
      expect(restored!.originalTitle, original.title);
      expect(restored.code, original.code);
      expect(restored.plot, original.plot);
      expect(restored.premiered, original.premiered);
      expect(restored.runtimeMinutes, 85);
      expect(restored.rating, 3.5);
      expect(restored.studio, 'GIGA');
      expect(restored.series, 'SPSF');
      expect(restored.director, '坂田徹');
      expect(restored.genres, original.genres);
      expect(restored.tags, original.tags);
      expect(restored.actors.map((a) => a.name), ['西元めいさ']);
      expect(restored.origins[MetadataField.title], FieldOrigin.existingNfo);
    });

    test('round-trips the source URL through the provenance comment', () {
      final original = _sample();
      final restored = NfoReader.read(NfoWriter.write(original))!;

      // This is what makes a folder-wide refresh possible without asking for
      // every URL a second time.
      expect(restored.sourceUrl, original.sourceUrl);
    });

    test('has no source URL when the NFO came from another tool', () {
      final restored = NfoReader.read(
        '<movie><title>X</title><!-- generated by something else --></movie>',
      )!;

      expect(restored.sourceUrl, isNull);
    });
  });
}
