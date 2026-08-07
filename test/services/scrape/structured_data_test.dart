import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/services/scrape/structured_data.dart';

final _pageUrl = Uri.parse(
  'https://www.giga-web.jp/product/index.php?product_id=7743',
);

void main() {
  group('site-wide template detection', () {
    test('GIGA publishes a site-wide OpenGraph block and it is rejected', () {
      // This is the finding that made the guard mandatory: the page's og:title
      // is the site name and its og:url points at the home page. Trusting it
      // would give every title in a library identical metadata — worse than
      // extracting nothing, because nothing looks broken.
      final document = html_parser.parse(
        File('test/fixtures/giga_product_7743.html').readAsStringSync(),
      );
      final result = StructuredData.inspect(document, _pageUrl);

      expect(result.openGraph['og:title'], isNotNull);
      expect(result.openGraph['og:url'], 'https://www.giga-web.jp/');
      expect(result.siteWide, isTrue);
      expect(result.jsonLd, isEmpty);

      // ...and nothing from it reaches the metadata.
      expect(StructuredData.toMetadata(result, _pageUrl), isNull);
    });

    test('a self-referencing og:url is accepted', () {
      final og = {
        'og:url': 'https://www.giga-web.jp/product/index.php?product_id=7743',
        'og:title': 'A Real Title',
        'og:site_name': 'The Site',
      };
      expect(StructuredData.isSiteWideTemplate(og, _pageUrl), isFalse);
    });

    test('a relative og:url is resolved before comparison', () {
      final og = {'og:url': '/product/index.php?product_id=7743'};
      expect(StructuredData.isSiteWideTemplate(og, _pageUrl), isFalse);
    });

    test('og:title equal to og:site_name is rejected even without og:url', () {
      final og = {'og:title': 'The Site', 'og:site_name': 'The Site'};
      expect(StructuredData.isSiteWideTemplate(og, _pageUrl), isTrue);
    });

    test('a different query string counts as a different page', () {
      final og = {
        'og:url': 'https://www.giga-web.jp/product/index.php?product_id=1',
      };
      expect(StructuredData.isSiteWideTemplate(og, _pageUrl), isTrue);
    });
  });

  group('OpenGraph extraction', () {
    test('reads title, description and image, resolving relative images', () {
      final document = html_parser.parse('''
<html><head>
<meta property="og:url" content="/product/index.php?product_id=7743">
<meta property="og:title" content="Some Title">
<meta property="og:description" content="Some description.">
<meta property="og:image" content="/img/cover.jpg">
</head><body></body></html>
''');
      final m = StructuredData.toMetadata(
        StructuredData.inspect(document, _pageUrl),
        _pageUrl,
      );
      expect(m, isNotNull);
      expect(m!.title, 'Some Title');
      expect(m.plot, 'Some description.');
      expect(m.posterUrl, 'https://www.giga-web.jp/img/cover.jpg');
    });
  });

  group('JSON-LD extraction', () {
    test('reads a Movie node including nested actor objects', () {
      final document = html_parser.parse('''
<html><head>
<meta property="og:url" content="/product/index.php?product_id=7743">
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Movie",
  "name": "Ld Title",
  "description": "Ld plot.",
  "datePublished": "2026/08/14",
  "genre": ["Action", "Drama"],
  "actor": [{"@type": "Person", "name": "First Actor"}, "Second Actor"],
  "director": {"@type": "Person", "name": "The Director"},
  "image": ["https://cdn.example/a.jpg"],
  "aggregateRating": {"@type": "AggregateRating", "ratingValue": 4.2}
}
</script>
</head><body></body></html>
''');
      final m = StructuredData.toMetadata(
        StructuredData.inspect(document, _pageUrl),
        _pageUrl,
      );
      expect(m, isNotNull);
      expect(m!.title, 'Ld Title');
      expect(m.premiered, '2026-08-14');
      expect(m.genres, ['Action', 'Drama']);
      expect(m.actors.map((a) => a.name), ['First Actor', 'Second Actor']);
      expect(m.director, 'The Director');
      expect(m.posterUrl, 'https://cdn.example/a.jpg');
      expect(m.rating, 4.2);
    });

    test('unwraps @graph', () {
      final document = html_parser.parse('''
<html><head>
<script type="application/ld+json">
{"@graph": [{"@type": "WebSite"}, {"@type": "Movie", "name": "In Graph"}]}
</script>
</head><body></body></html>
''');
      final result = StructuredData.inspect(document, _pageUrl);
      expect(result.jsonLd, hasLength(2));
      expect(StructuredData.toMetadata(result, _pageUrl)?.title, 'In Graph');
    });

    test('malformed JSON-LD is skipped, not fatal', () {
      final document = html_parser.parse('''
<html><head>
<script type="application/ld+json">{ this is not json </script>
<script type="application/ld+json">{"@type": "Movie", "name": "Survivor"}</script>
</head><body></body></html>
''');
      final result = StructuredData.inspect(document, _pageUrl);
      expect(result.jsonLd, hasLength(1));
      expect(StructuredData.toMetadata(result, _pageUrl)?.title, 'Survivor');
    });

    test('an unrelated schema type is ignored', () {
      final document = html_parser.parse('''
<html><head>
<script type="application/ld+json">
{"@type": "BreadcrumbList", "name": "Breadcrumbs"}
</script>
</head><body></body></html>
''');
      final result = StructuredData.inspect(document, _pageUrl);
      expect(StructuredData.toMetadata(result, _pageUrl), isNull);
    });
  });
}
