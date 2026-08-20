/// Tier 3 of the extraction ladder: ask the LLM to write a recipe for a site
/// that has no built-in one.
///
/// **A learned recipe is never stored from here.** It is handed back for the
/// user to review in the scrape preview, and only saved if they say so. The
/// reason is in `docs/spec/scrape-giga-recipe.md` §2.3: a page can carry a
/// folded synopsis and an expanded one, and a model that grabs the folded copy
/// produces a recipe that runs, returns non-empty values, and looks entirely
/// healthy while quietly storing truncated text for every title on the site.
/// The self-check below can only catch *empty* fields — never short ones — so
/// a human has to be the one who commits it.
library;

import 'scrape_transform.dart';

import 'package:html/dom.dart';

import '../../models/media_metadata.dart';
import '../../models/scrape_recipe.dart';
import '../ai/ai_cancel_token.dart';
import '../ai/ai_provider.dart';
import 'html_cleaner.dart';
import 'recipe_applier.dart';
import 'scrape_prompt.dart';

/// A recipe the model wrote, plus what it actually pulled off the page it was
/// written against.
class LearnedRecipe {
  /// Not yet in `RecipeStore` — see the library doc.
  final ScrapeRecipe recipe;

  /// The self-check's output: what this recipe extracts from the page it was
  /// learned on. Every field is [FieldOrigin.llm], which is what makes the
  /// preview highlight them.
  final MediaMetadata extracted;

  /// 1 when the first attempt worked, 2 when the retry did.
  final int attempts;
  final int promptTokens;
  final int completionTokens;

  const LearnedRecipe({
    required this.recipe,
    required this.extracted,
    required this.attempts,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });
}

class RecipeLearner {
  final AiProvider provider;

  /// One retry, carrying the first attempt's shortfall as feedback. A third
  /// try is not worth the tokens: if the model cannot find a title with the
  /// skeleton in front of it twice, the page needs tier 4.
  static const int maxAttempts = 2;

  const RecipeLearner(this.provider);

  /// Learns a recipe for [pageUrl] from [html], or returns null when the model
  /// cannot produce one that works.
  ///
  /// [document] is the already-parsed page, used for the self-check so the
  /// verification runs against exactly the tree the real extraction would.
  Future<LearnedRecipe?> learn({
    required String html,
    required Document document,
    required Uri pageUrl,
    AiCancelToken? cancelToken,
  }) async {
    final skeleton = HtmlCleaner.clean(html);
    if (skeleton.isEmpty) return null;

    var promptTokens = 0;
    var completionTokens = 0;
    String? feedback;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      cancelToken?.throwIfCancelled();

      final response = await provider.complete(
        systemPrompt: ScrapePrompt.systemPrompt,
        userPrompt: ScrapePrompt.buildUserPrompt(
          pageUrl: pageUrl,
          skeleton: skeleton,
          feedback: feedback,
        ),
        cancelToken: cancelToken,
      );
      promptTokens += response.promptTokens;
      completionTokens += response.completionTokens;

      final recipe = parseRecipe(response.text, pageUrl);
      if (recipe == null) {
        feedback = 'It was not valid JSON in the shape described above.';
        continue;
      }

      // Self-check: run it against the page it was written for. This is cheap,
      // local, and catches the common failure of selectors that match nothing.
      final extracted = RecipeApplier.apply(document, recipe, pageUrl);
      final shortfall = ScrapePrompt.describeShortfall(extracted);
      if (shortfall != null) {
        feedback = shortfall;
        continue;
      }

      return LearnedRecipe(
        recipe: recipe,
        extracted: _asLlmOrigin(extracted),
        attempts: attempt,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
    }
    return null;
  }

  /// Parses model text into a recipe, or null when it is unusable.
  ///
  /// Tolerant of markdown fences and stray prose, like `OrganizePlan`'s parser.
  /// The domain, origin and schema version are forced rather than trusted: a
  /// model that writes someone else's domain would produce a recipe that
  /// silently applies to the wrong site.
  static ScrapeRecipe? parseRecipe(String raw, Uri pageUrl) {
    final json = extractJsonMap(raw);
    if (json == null) return null;

    json['domain'] = pageUrl.host;
    json['origin'] = RecipeOrigin.llm.name;
    json['schemaVersion'] = ScrapeRecipe.currentSchemaVersion;
    // A learned recipe starts with a clean slate rather than whatever counters
    // the model felt like inventing.
    json.remove('successCount');
    json.remove('failCount');

    final pattern = (json['pathPattern'] as String?)?.trim();
    if (pattern == null || pattern.isEmpty) {
      json['pathPattern'] = ScrapePrompt.suggestPathPattern(pageUrl);
    }

    final recipe = ScrapeRecipe.fromJson(json);
    // Nothing to apply: a recipe with no rules would "succeed" at extracting
    // nothing forever.
    if (recipe.fields.isEmpty &&
        recipe.keyValue == null &&
        recipe.tagGroups.isEmpty &&
        recipe.constants.isEmpty) {
      return null;
    }
    return recipe;
  }

  /// Re-stamps every extracted field as LLM-sourced.
  ///
  /// `RecipeApplier` marks its output [FieldOrigin.recipe], which is right for
  /// a recipe a human vetted; for one the model just invented it would hide
  /// exactly the values that need a second look. `NfoMerge` also refuses to let
  /// an `llm` value overwrite an existing one, which is the behaviour we want
  /// here.
  static MediaMetadata _asLlmOrigin(MediaMetadata extracted) {
    for (final field in MetadataField.all) {
      if (!extracted.isBlank(field)) extracted.origins[field] = FieldOrigin.llm;
    }
    return extracted;
  }
}
