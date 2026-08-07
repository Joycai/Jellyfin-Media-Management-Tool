import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_reader.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_writer.dart';

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
      expect(xml, contains('<sorttitle>SPSF-43</sorttitle>'));
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

    test('prefixes the display title with the code but keeps the original', () {
      final xml = NfoWriter.write(_sample());
      expect(xml, contains('<title>SPSF-43 美少女戦士セーラーディオーレ 絶望の餌食</title>'));
      expect(
        xml,
        contains('<originaltitle>美少女戦士セーラーディオーレ 絶望の餌食</originaltitle>'),
      );
    });

    test('does not double up a title that already starts with the code', () {
      final m = _sample()..title = 'SPSF-43 Already Prefixed';
      expect(
        NfoWriter.write(m),
        contains('<title>SPSF-43 Already Prefixed</title>'),
      );
    });

    test('prefixing can be turned off', () {
      final xml = NfoWriter.write(
        _sample(),
        options: const NfoOptions(prefixTitleWithCode: false),
      );
      expect(xml, contains('<title>美少女戦士セーラーディオーレ 絶望の餌食</title>'));
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
  });
}
