import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/models/scrape_recipe.dart';
import 'package:jellyfin_media_management_tool/services/scrape/builtin_recipes.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_applier.dart';

/// Real markup, trimmed. Everything the recipe touches is byte-for-byte what
/// the site served, including the two things that break naive scrapers: the
/// duplicated `id` attributes and the folded/expanded copies of the synopsis.
final _fixture = File(
  'test/fixtures/giga_product_7743.html',
).readAsStringSync();

final _pageUrl = Uri.parse(
  'https://www.giga-web.jp/product/index.php?product_id=7743',
);

MediaMetadata _run([ScrapeRecipe? recipe]) => RecipeApplier.apply(
  html_parser.parse(_fixture),
  recipe ?? BuiltinRecipes.all.first,
  _pageUrl,
);

void main() {
  group('normalizeWhitespace', () {
    test(
      'collapses the ideographic space Japanese pages use as a separator',
      () {
        expect(normalizeWhitespace('本編85分　メイキング5分'), '本編85分 メイキング5分');
      },
    );

    test('collapses newlines and tabs from template whitespace', () {
      expect(normalizeWhitespace('\n\t\t a \n b \t'), 'a b');
    });
  });

  group('built-in GIGA recipe', () {
    test('matches a product URL and not the rest of the site', () {
      final recipe = BuiltinRecipes.all.first;
      expect(recipe.matches(_pageUrl), isTrue);
      expect(
        recipe.matches(Uri.parse('https://www.giga-web.jp/search/index.php')),
        isFalse,
      );
      expect(
        recipe.matches(Uri.parse('https://example.com/product/index.php')),
        isFalse,
      );
    });

    test('is registered for lookup by URL', () {
      expect(BuiltinRecipes.forUrl(_pageUrl), isNotNull);
      expect(BuiltinRecipes.forUrl(Uri.parse('https://example.com/x')), isNull);
    });
  });

  group('RecipeApplier on the GIGA fixture', () {
    late MediaMetadata m;

    setUp(() => m = _run());

    test('extracts the title from the product heading, not <title>', () {
      // The page's own <title> is the site name; getting this from the h5 is
      // the whole reason this site needs a recipe.
      expect(m.title, '美少女戦士セーラーディオーレ 絶望の餌食');
    });

    test('reads the key/value table by Japanese label', () {
      expect(m.code, 'SPSF-43');
      expect(m.director, '坂田徹');
      expect(m.actors.map((a) => a.name), ['西元めいさ']);
    });

    test('parses the runtime out of prose containing a full-width space', () {
      // Source: "本編85分　メイキング5分" — 85 is the feature, 5 is the extra.
      expect(m.runtimeMinutes, 85);
    });

    test('normalizes the release date to ISO', () {
      expect(m.premiered, '2026-08-14');
      expect(m.year, 2026);
    });

    test('takes the expanded synopsis, not the truncated one', () {
      // #story_list1 is the collapsed copy and ends in an ellipsis; picking it
      // yields a plausible-looking but silently truncated plot, which is
      // exactly the failure an "is it empty?" check cannot catch.
      expect(m.plot, isNotNull);
      expect(m.plot, startsWith('セーラーディオーレは豪然たる妖魔との'));
      expect(m.plot, endsWith('[BAD END]'));
      expect(m.plot!.length, greaterThan(200));
    });

    test('strips the show-more/collapse link out of the text block', () {
      expect(m.plot, isNot(contains('▲閉じる')));
      expect(m.plot, isNot(contains('▼もっと見る')));
      expect(m.outline, isNot(contains('▲閉じる')));
    });

    test('keeps the marketing copy out of the plot', () {
      // The director's comment is a sales pitch, not a synopsis: it belongs in
      // <outline>, and it is an order of magnitude longer than the plot.
      expect(m.outline, startsWith('８０年代後半の超人気有名アイドル'));
      expect(m.outline!.length, greaterThan(m.plot!.length));
    });

    test('routes both tag blocks despite them sharing one id', () {
      // The page has two <div id="tag"> blocks. Using querySelector instead of
      // querySelectorAll silently drops the second one.
      expect(m.genres, hasLength(11));
      expect(m.genres.first, 'ピンヒールブーツ');
      expect(m.genres.last, '足舐め');
      expect(m.tags, contains('セーラーヒロイン'));
    });

    test('collects the sales-form links as tags', () {
      expect(m.tags, contains('HD版対応'));
      expect(m.tags, contains('【月額見放題】先行メイキング映像'));
    });

    test('reads the average rating', () {
      expect(m.rating, 3.5);
    });

    test('applies site constants and derivations', () {
      expect(m.studio, 'GIGA');
      expect(m.series, 'SPSF'); // from the code prefix
      expect(m.sortTitle, 'SPSF-43');
      expect(m.originalTitle, m.title);
    });

    test('resolves image URLs against the page URL', () {
      // Asserted loosely on purpose: this fixture is a browser "save page as",
      // so its image paths were rewritten to local file names containing
      // spaces. A live fetch carries the server's real relative paths — what
      // matters here is that resolution happened at all. The exact semantics
      // are pinned by the resolveUrl tests below.
      expect(m.posterUrl, isNotNull);
      expect(m.posterUrl, endsWith('pac_s.jpg'));
      // Sample stills come from <a href>, i.e. the full-size versions.
      expect(m.extraFanartUrls, hasLength(3));
      for (final url in m.extraFanartUrls) {
        expect(url, endsWith('.jpg'));
      }
    });

    test('records where every field came from', () {
      expect(m.origins[MetadataField.title], FieldOrigin.recipe);
      expect(m.origins[MetadataField.studio], FieldOrigin.recipe);
      expect(m.origins[MetadataField.series], FieldOrigin.derived);
    });

    test('is not empty', () {
      expect(m.isEmpty, isFalse);
    });
  });

  group('RecipeApplier robustness', () {
    test('a recipe whose selectors match nothing yields an empty result', () {
      final dead = ScrapeRecipe(
        domain: 'www.giga-web.jp',
        fields: {
          'title': const FieldRule(selectors: ['#nope .gone']),
        },
      );
      expect(_run(dead).isEmpty, isTrue);
    });

    test('an unparseable selector is ignored rather than thrown', () {
      final broken = ScrapeRecipe(
        domain: 'www.giga-web.jp',
        fields: {
          'title': const FieldRule(selectors: ['#works_pic h5', '<<<bad']),
          'plot': const FieldRule(selectors: ['((']),
        },
      );
      final m = _run(broken);
      expect(m.title, '美少女戦士セーラーディオーレ 絶望の餌食');
      expect(m.plot, isNull);
    });

    test('the first selector that matches wins, later ones are fallbacks', () {
      final ordered = ScrapeRecipe(
        domain: 'www.giga-web.jp',
        fields: {
          'plot': const FieldRule(
            selectors: ['#missing', '#story_list1 li.story_window'],
            strip: ['span'],
          ),
        },
      );
      // Explicitly asking for the collapsed copy must give the collapsed copy,
      // proving the fallback order is honoured rather than always preferring
      // the longest match.
      expect(_run(ordered).plot, endsWith('…'));
    });

    test('stripping does not mutate the document for later rules', () {
      final document = html_parser.parse(_fixture);
      final recipe = BuiltinRecipes.all.first;
      final first = RecipeApplier.apply(document, recipe, _pageUrl);
      final second = RecipeApplier.apply(document, recipe, _pageUrl);
      expect(second.plot, first.plot);
      expect(second.outline, first.outline);
    });

    test('resolveUrl handles relative, absolute and junk references', () {
      final base = Uri.parse('https://host.example/a/b/page.php?id=1');
      // `..` climbs out of /a/b/, not out of /a/.
      expect(
        RecipeApplier.resolveUrl(base, '../img/x.jpg'),
        'https://host.example/a/img/x.jpg',
      );
      expect(
        RecipeApplier.resolveUrl(base, '/top.png'),
        'https://host.example/top.png',
      );
      expect(
        RecipeApplier.resolveUrl(base, 'https://cdn.example/y.jpg'),
        'https://cdn.example/y.jpg',
      );
      // Not a URL at all: hand it back rather than losing the field.
      expect(
        RecipeApplier.resolveUrl(base, 'javascript:void(0)'),
        'javascript:void(0)',
      );
    });

    test('resolveUrl is total, even for references containing spaces', () {
      // Saved pages rewrite image paths to local file names with spaces in
      // them. Whatever Uri.parse decides to do with that, the helper must
      // return something rather than throwing mid-scrape.
      final base = Uri.parse('https://host.example/a/page.php');
      expect(
        RecipeApplier.resolveUrl(base, './some dir (x)/pac_s.jpg'),
        contains('pac_s.jpg'),
      );
    });
  });

  group('recipe JSON round-trip', () {
    test('survives serialization unchanged', () {
      final original = BuiltinRecipes.all.first;
      final restored = ScrapeRecipe.fromJson(original.toJson());
      expect(
        RecipeApplier.apply(
          html_parser.parse(_fixture),
          restored,
          _pageUrl,
        ).code,
        'SPSF-43',
      );
      expect(restored.cookies, 'old_check=yes; layout=jpn');
      expect(restored.skipStructuredData, isTrue);
    });

    test('accepts a selector given as a list as well as a comma string', () {
      final fromList = FieldRule.fromJson({
        'selector': ['#a', '#b'],
      });
      final fromString = FieldRule.fromJson({'selector': '#a, #b'});
      expect(fromList.selectors, ['#a', '#b']);
      expect(fromString.selectors, ['#a', '#b']);
    });
  });
}
