import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/models/scrape_recipe.dart';
import 'package:jellyfin_media_management_tool/services/scrape/builtin_recipes.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_learner.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_prompt.dart';

import '../../helpers/ai.dart';

final _fixture = io.File(
  'test/fixtures/giga_product_7743.html',
).readAsStringSync();

final _pageUrl = Uri.parse(
  'https://www.giga-web.jp/product/index.php?product_id=7743',
);

/// A recipe that finds nothing on the fixture — the shape of a plausible-looking
/// but wrong first attempt.
const _uselessRecipe = '''
{ "fields": { "title": { "selector": "#nothing-here" } } }
''';

void main() {
  final document = html_parser.parse(_fixture);

  group('RecipeLearner.parseRecipe', () {
    test('forces domain, origin and schema version', () {
      final recipe = RecipeLearner.parseRecipe(
        '{"domain":"evil.example","origin":"builtin","schemaVersion":99,'
        '"fields":{"title":{"selector":"h1"}}}',
        _pageUrl,
      )!;

      // A model naming someone else's domain would produce a recipe that
      // silently applies to the wrong site.
      expect(recipe.domain, 'www.giga-web.jp');
      expect(recipe.origin, RecipeOrigin.llm);
      expect(recipe.schemaVersion, ScrapeRecipe.currentSchemaVersion);
    });

    test('fills in a path pattern when the model omitted one', () {
      final recipe = RecipeLearner.parseRecipe(
        '{"fields":{"title":{"selector":"h1"}}}',
        _pageUrl,
      )!;

      expect(recipe.pathPattern, '/product/*');
    });

    test('tolerates markdown fences and surrounding prose', () {
      final recipe = RecipeLearner.parseRecipe(
        'Sure! Here you go:\n```json\n'
        '{"fields":{"title":{"selector":"h1"}}}\n```\nHope that helps.',
        _pageUrl,
      );

      expect(recipe, isNotNull);
    });

    test('rejects text with no JSON object', () {
      expect(
        RecipeLearner.parseRecipe('I cannot help with that.', _pageUrl),
        isNull,
      );
    });

    test('rejects a recipe with no rules at all', () {
      // It would "succeed" at extracting nothing, forever.
      expect(RecipeLearner.parseRecipe('{"domain":"x"}', _pageUrl), isNull);
    });

    test('discards counters the model invented', () {
      final recipe = RecipeLearner.parseRecipe(
        '{"successCount":99,"failCount":7,'
        '"fields":{"title":{"selector":"h1"}}}',
        _pageUrl,
      )!;

      expect(recipe.successCount, 0);
      expect(recipe.failCount, 0);
      expect(recipe.isRetired, isFalse);
    });
  });

  group('RecipeLearner.learn', () {
    test('accepts a recipe that extracts the required fields', () async {
      final provider = ScriptedProvider([BuiltinRecipes.gigaWebJson]);

      final learned = await RecipeLearner(
        provider,
      ).learn(html: _fixture, document: document, pageUrl: _pageUrl);

      expect(learned, isNotNull);
      expect(learned!.attempts, 1);
      expect(provider.calls, 1);
      expect(learned.extracted.title, isNotNull);
      expect(learned.extracted.code, 'SPSF-43');
      expect(learned.promptTokens, 10);
    });

    test('marks every extracted field as LLM-sourced', () async {
      final learned = await RecipeLearner(
        ScriptedProvider([BuiltinRecipes.gigaWebJson]),
      ).learn(html: _fixture, document: document, pageUrl: _pageUrl);

      // The badge in the preview — and NfoMerge's refusal to let a guess
      // overwrite an existing value — both key off this.
      expect(learned!.extracted.origins[MetadataField.title], FieldOrigin.llm);
      expect(learned.extracted.origins[MetadataField.code], FieldOrigin.llm);
    });

    test(
      'retries once with the shortfall as feedback, then succeeds',
      () async {
        final provider = ScriptedProvider([
          _uselessRecipe,
          BuiltinRecipes.gigaWebJson,
        ]);

        final learned = await RecipeLearner(
          provider,
        ).learn(html: _fixture, document: document, pageUrl: _pageUrl);

        expect(learned, isNotNull);
        expect(learned!.attempts, 2);
        expect(provider.calls, 2);
        // Handing the model its own miss is the point of the retry.
        expect(provider.userPrompts.first, isNot(contains('did not work')));
        expect(provider.userPrompts[1], contains('did not work'));
        expect(provider.userPrompts[1], contains('title'));
        // Tokens accumulate across both attempts.
        expect(learned.promptTokens, 20);
      },
    );

    test(
      'gives up after two attempts rather than burning more tokens',
      () async {
        final provider = ScriptedProvider([_uselessRecipe]);

        final learned = await RecipeLearner(
          provider,
        ).learn(html: _fixture, document: document, pageUrl: _pageUrl);

        expect(learned, isNull);
        expect(provider.calls, RecipeLearner.maxAttempts);
      },
    );

    test('does not mutate the document it verifies against', () async {
      final plotBefore = document.querySelector('#story_list2')?.text;
      await RecipeLearner(
        ScriptedProvider([BuiltinRecipes.gigaWebJson]),
      ).learn(html: _fixture, document: document, pageUrl: _pageUrl);

      expect(document.querySelector('#story_list2')?.text, plotBefore);
    });
  });

  group('ScrapePrompt', () {
    test('suggests a sibling-page glob', () {
      expect(ScrapePrompt.suggestPathPattern(_pageUrl), '/product/*');
      expect(
        ScrapePrompt.suggestPathPattern(Uri.parse('https://e.test/a/b/c')),
        '/a/b/*',
      );
      expect(
        ScrapePrompt.suggestPathPattern(Uri.parse('https://e.test/only')),
        '/*',
      );
      expect(ScrapePrompt.suggestPathPattern(Uri.parse('https://e.test/')), '');
    });

    test('names what a failed attempt missed', () {
      expect(
        ScrapePrompt.describeShortfall(MediaMetadata()),
        contains('title'),
      );
      expect(
        ScrapePrompt.describeShortfall(MediaMetadata(title: 'x')),
        contains('code or poster'),
      );
      // A title plus something identifying the release is good enough.
      expect(
        ScrapePrompt.describeShortfall(MediaMetadata(title: 'x', code: 'A-1')),
        isNull,
      );
    });

    test('carries the built-in recipe as the worked example', () {
      // Few-shot straight from the shipped recipe, so the example can never
      // drift from the schema the parser accepts.
      expect(ScrapePrompt.systemPrompt, contains('"keyValue"'));
      expect(ScrapePrompt.systemPrompt, contains('作品番号'));
      expect(ScrapePrompt.systemPrompt, contains('regexInt'));
      // The trap that motivates the whole human-review rule.
      expect(ScrapePrompt.systemPrompt, contains('PREFER THE LONGER COPY'));
    });
  });
}
