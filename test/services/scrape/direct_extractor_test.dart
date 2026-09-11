import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
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
    test('stores what the model submits and ends when it says so', () async {
      final provider = ScriptedChatProvider([
        (_) => toolTurn([('read_section', <String, Object?>{})]),
        (_) => toolTurn([
          (
            'submit_fields',
            {
              'title': '美少女戦士セーラーディオーレ 絶望の餌食',
              'code': 'SPSF-43',
              'runtimeMinutes': 85,
              'director': '坂田徹',
            },
          ),
        ]),
        (_) => textTurn('Done.'),
      ]);

      final result = await DirectExtractor(
        provider,
      ).extract(document: html_parser.parse(_fixture), pageUrl: _page);

      expect(result!.metadata.code, 'SPSF-43');
      expect(result.metadata.runtimeMinutes, 85);
      expect(result.metadata.origins[MetadataField.code], FieldOrigin.llm);
      // The page's own text reached the model through read_section.
      final read = provider.seen[1].last as ToolResultMessage;
      expect(read.content, contains('SPSF-43'));
      expect(provider.calls, 3);
    });

    test('the page is offered as an outline, not in full', () async {
      final provider = ScriptedChatProvider([(_) => textTurn('Nothing.')]);

      await DirectExtractor(
        provider,
      ).extract(document: html_parser.parse(_fixture), pageUrl: _page);

      final task = provider.seen.first[1] as UserMessage;
      expect(task.content, contains('Outline of'));
      expect(task.content.length, lessThan(_fixture.length ~/ 2));
    });

    test(
      'images are chosen by number, and a number off the list is refused',
      () async {
        final document = html_parser.parse(
          '<html><body><h1 class="t">Title</h1>'
          '<img src="/cover.jpg"><img src="/still.jpg"></body></html>',
        );
        final provider = ScriptedChatProvider([
          (_) => toolTurn([
            ('submit_fields', {'title': 'Title', 'poster': 7}),
          ]),
          (_) => toolTurn([
            (
              'submit_fields',
              {
                'poster': 1,
                'extraFanart': [2],
              },
            ),
          ]),
          (_) => textTurn('Done.'),
        ]);

        final result = await DirectExtractor(
          provider,
        ).extract(document: document, pageUrl: Uri.parse('https://e.test/p'));

        final refusal = provider.seen[1].last as ToolResultMessage;
        expect(
          refusal.content,
          contains('poster must be the number of an image'),
        );
        expect(result!.metadata.posterUrl, 'https://e.test/cover.jpg');
        expect(result.metadata.extraFanartUrls, ['https://e.test/still.jpg']);
      },
    );

    test('passes the user\'s own instructions through, delimited', () async {
      final provider = ScriptedChatProvider([(_) => textTurn('Nothing.')]);

      await DirectExtractor(provider).extract(
        document: html_parser.parse(_fixture),
        pageUrl: _page,
        instructions: 'use the sidebar credits as tags',
      );

      final task = (provider.seen.first[1] as UserMessage).content;
      expect(task, contains('use the sidebar credits as tags'));
      expect(task, contains('"""'));
    });

    test('a model that submits nothing returns null after reminders', () async {
      final provider = ScriptedChatProvider([
        (_) => textTurn('I could not find anything.'),
      ]);

      final result = await DirectExtractor(
        provider,
      ).extract(document: html_parser.parse(_fixture), pageUrl: _page);

      expect(result, isNull);
      expect(provider.calls, 3, reason: 'one turn and two reminders');
    });

    test(
      'a submission with no usable field is refused with the names',
      () async {
        final provider = ScriptedChatProvider([
          (_) => toolTurn([
            ('submit_fields', {'nonsense': 'x'}),
          ]),
          (_) => textTurn('Giving up.'),
        ]);

        final result = await DirectExtractor(
          provider,
        ).extract(document: html_parser.parse(_fixture), pageUrl: _page);

        expect(result, isNull);
        expect(
          (provider.seen[1].last as ToolResultMessage).content,
          contains('Nothing usable was submitted'),
        );
      },
    );

    test('runs the readiness check before the first model call', () async {
      final provider = ScriptedChatProvider([(_) => textTurn('Nothing.')]);

      await expectLater(
        DirectExtractor(
          provider,
          beforeStart: () async => throw const AiException('no tools'),
        ).extract(document: html_parser.parse(_fixture), pageUrl: _page),
        throwsA(isA<AiException>()),
      );
      expect(provider.calls, 0);
    });
  });
}
