import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/scrape/direct_extractor.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_digest.dart';

import '../../helpers/ai.dart';

final _fixture = io.File(
  'test/fixtures/giga_product_7743.html',
).readAsStringSync();

final _page = Uri.parse(
  'https://www.giga-web.jp/product/index.php?product_id=7743',
);

void main() {
  group('PageDigest', () {
    test('keeps the prose and drops the machinery', () {
      final digest = PageDigest.of(
        html_parser.parse('''
<html><head><title>t</title><style>.a{color:red}</style></head>
<body><script>var x = "not prose";</script>
<p>The   real    text.</p><noscript>fallback</noscript></body></html>'''),
        _page,
      );

      expect(digest.text, contains('The real text.'));
      expect(digest.text, isNot(contains('not prose')));
      expect(digest.text, isNot(contains('color:red')));
      expect(digest.text, isNot(contains('fallback')));
    });

    test('offers absolute image URLs, deduplicated', () {
      final digest = PageDigest.of(
        html_parser.parse('''
<html><body>
<img src="/a/one.jpg"><img src="/a/one.jpg"><img data-src="two.png">
<a href="/full/three.webp">big</a>
<a href="/page.php">not an image</a>
<img src="data:image/gif;base64,AAAA">
<img src="/icons/tiny.png" width="16" height="16">
</body></html>'''),
        Uri.parse('https://e.test/a/b.php'),
      );

      expect(digest.images, [
        'https://e.test/a/one.jpg',
        'https://e.test/a/two.png',
        'https://e.test/full/three.webp',
      ]);
    });

    test('does not mutate the caller\'s document', () {
      // The recipe tiers may still be reading this tree.
      final document = html_parser.parse(
        '<html><body><script>x</script>'
        '<p>hi</p></body></html>',
      );
      PageDigest.of(document, _page);

      expect(document.querySelectorAll('script'), hasLength(1));
    });
  });

  group('parseFields', () {
    test('refuses an image URL that was not on the page', () {
      // A hallucinated poster is indistinguishable from a real one until it
      // 404s, by which point it is already in the NFO.
      final m = DirectExtractor.parseFields(
        '{"title":"T","poster":"https://evil.test/made-up.jpg"}',
        const ['https://e.test/real.jpg'],
      );

      expect(m!.title, 'T');
      expect(m.posterUrl, isNull);
    });

    test('accepts one that was', () {
      final m = DirectExtractor.parseFields(
        '{"poster":"https://e.test/real.jpg",'
        '"extraFanart":["https://e.test/real.jpg","https://evil.test/x.jpg"]}',
        const ['https://e.test/real.jpg'],
      );

      expect(m!.posterUrl, 'https://e.test/real.jpg');
      expect(m.extraFanartUrls, ['https://e.test/real.jpg']);
    });

    test('coerces what it can and drops what it cannot', () {
      final m = DirectExtractor.parseFields(
        '{"title":"T","runtimeMinutes":"85","rating":"3.5",'
        '"genres":["a","b"],"actors":[{"name":"N","role":"R"}],'
        '"nonsense":"ignored","premiered":""}',
        const [],
      );

      expect(m!.runtimeMinutes, 85);
      expect(m.rating, 3.5);
      expect(m.genres, ['a', 'b']);
      expect(m.actors.single.role, 'R');
      expect(m.premiered, isNull);
    });

    test('stamps everything as LLM-sourced', () {
      // This is what makes the preview flag the values and stops NfoMerge
      // letting them overwrite anything already on disk.
      final m = DirectExtractor.parseFields('{"title":"T"}', const [])!;
      expect(m.origins[MetadataField.title], FieldOrigin.llm);
    });

    test('survives fences, prose and outright garbage', () {
      expect(
        DirectExtractor.parseFields(
          'Sure!\n```json\n{"title":"T"}\n```',
          const [],
        )!.title,
        'T',
      );
      expect(DirectExtractor.parseFields('no json here', const []), isNull);
      expect(DirectExtractor.parseFields('{"unknown":1}', const []), isNull);
    });
  });

  group('extract', () {
    test('reads a real page through a scripted model', () async {
      final provider = ScriptedProvider([
        '{"title":"美少女戦士セーラーディオーレ 絶望の餌食","code":"SPSF-43",'
            '"runtimeMinutes":85,"director":"坂田徹"}',
      ]);

      final result = await DirectExtractor(
        provider,
      ).extract(document: html_parser.parse(_fixture), pageUrl: _page);

      expect(result!.metadata.code, 'SPSF-43');
      expect(result.metadata.runtimeMinutes, 85);
      // The page's own text has to be in the prompt — this is the tier that
      // reads content rather than structure.
      expect(provider.userPrompts.single, contains('SPSF-43'));
    });

    test('passes the user\'s own instructions through, delimited', () async {
      final provider = ScriptedProvider(['{"title":"T"}']);

      await DirectExtractor(provider).extract(
        document: html_parser.parse(_fixture),
        pageUrl: _page,
        instructions: 'use the sidebar credits as tags',
      );

      final prompt = provider.userPrompts.single;
      expect(prompt, contains('use the sidebar credits as tags'));
      expect(prompt, contains('"""'));
    });

    test('a model that returns nothing usable is not an exception', () async {
      final provider = ScriptedProvider(['I could not find anything.']);

      final result = await DirectExtractor(
        provider,
      ).extract(document: html_parser.parse(_fixture), pageUrl: _page);

      expect(result, isNull);
    });
  });
}
