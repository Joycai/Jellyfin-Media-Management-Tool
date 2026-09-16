/// Tier 3 of the extraction ladder: ask the LLM to write a recipe for a site
/// that has no built-in one.
///
/// **A learned recipe is never stored from here.** It is handed back for the
/// user to review in the scrape preview, and only saved if they say so. The
/// reason is in `docs/spec/scrape-giga-recipe.md` §2.3: a page can carry a
/// folded synopsis and an expanded one, and a model that grabs the folded copy
/// produces a recipe that runs, returns non-empty values, and looks entirely
/// healthy while quietly storing truncated text for every title on the site.
/// The check below can only catch *empty* fields — never short ones — so a
/// human has to be the one who commits it.
///
/// It runs as a tool loop. The model explores the page through
/// [PageInspector] instead of reading a skeleton of all of it, tries drafts
/// with `test_recipe`, and hands the one it settles on to `submit_recipe`,
/// which refuses a recipe that does not extract a title and something that
/// identifies the release. The self-check that used to run after the fact now
/// runs where the model can act on it.
library;

import 'dart:convert';

import 'package:html/dom.dart';

import '../../models/media_metadata.dart';
import '../../models/scrape_recipe.dart';
import '../agent/agent_runtime.dart';
import '../ai/ai_cancel_token.dart';
import '../ai/ai_provider.dart';
import 'page_tools.dart';
import 'recipe_applier.dart';
import 'scrape_prompt.dart';
import 'scrape_transform.dart';

/// A recipe the model wrote, plus what it actually pulled off the page it was
/// written against.
class LearnedRecipe {
  /// Not yet in `RecipeStore` — see the library doc.
  final ScrapeRecipe recipe;

  /// What this recipe extracts from the page it was learned on. Every field is
  /// [FieldOrigin.llm], which is what makes the preview highlight them.
  final MediaMetadata extracted;

  /// Model turns the run took.
  final int rounds;
  final int promptTokens;
  final int completionTokens;

  const LearnedRecipe({
    required this.recipe,
    required this.extracted,
    required this.rounds,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });
}

class RecipeLearner {
  final AiProvider provider;

  /// Runs once before the first model call. The scrape panel passes
  /// `AiService.ensureTools`, so a model that cannot call tools fails with a
  /// message saying so rather than with "no recipe".
  final Future<void> Function()? beforeStart;

  /// An outline, a few inspections and queries, a test or two and a
  /// submission, with room for a model that needs to correct itself. Past
  /// this, the page needs tier 4.
  static const int maxRounds = 14;

  const RecipeLearner(this.provider, {this.beforeStart});

  /// Learns a recipe for [pageUrl] from [document], or returns null when the
  /// model does not submit one that works.
  Future<LearnedRecipe?> learn({
    required Document document,
    required Uri pageUrl,
    AiCancelToken? cancelToken,
  }) async {
    final state = _LearnState(PageInspector(document, pageUrl), pageUrl);
    if (state.page.outline.isEmpty) return null;

    await beforeStart?.call();
    cancelToken?.throwIfCancelled();
    final run = await AgentRuntime.run<_LearnState>(
      provider: provider,
      messages: [
        SystemMessage(ScrapePrompt.systemPrompt),
        UserMessage(
          ScrapePrompt.buildTaskPrompt(
            pageUrl: pageUrl,
            outline: state.page.outlinePage(1),
          ),
        ),
      ],
      tools: const [
        PageOutlineTool<_LearnState>(),
        InspectTool<_LearnState>(),
        QueryTool<_LearnState>(),
        _TestRecipeTool(),
        _SubmitRecipeTool(),
      ],
      context: state,
      maxRounds: maxRounds,
      isDone: () => state.submitted != null,
      nudge: () =>
          'You have not submitted a recipe yet. Check a draft with '
          'test_recipe, then call submit_recipe.',
      contextWindow: provider.config.contextWindow,
      cancelToken: cancelToken,
    );

    final recipe = state.submitted;
    if (recipe == null) return null;
    return LearnedRecipe(
      recipe: recipe,
      extracted: _asLlmOrigin(RecipeApplier.apply(document, recipe, pageUrl)),
      rounds: run.rounds,
      promptTokens: run.promptTokens,
      completionTokens: run.completionTokens,
    );
  }

  /// Parses model text into a recipe, or null when it is unusable.
  ///
  /// Tolerant of markdown fences and stray prose. The domain, origin and
  /// schema version are forced rather than trusted: a model that writes
  /// someone else's domain would produce a recipe that silently applies to the
  /// wrong site.
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

class _LearnState implements HasPage {
  @override
  final PageInspector page;
  final Uri pageUrl;
  ScrapeRecipe? submitted;

  _LearnState(this.page, this.pageUrl);
}

const _recipeParameters = {
  'type': 'object',
  'properties': {
    'recipe': {
      'type': 'object',
      'description': 'The recipe, in the shape the instructions show.',
    },
  },
  'required': ['recipe'],
};

/// The recipe argument, which a model may pass as an object or, less tidily,
/// as a JSON string.
ScrapeRecipe _recipeArgument(Map<String, dynamic> arguments, Uri pageUrl) {
  final text = switch (arguments['recipe']) {
    String s => s,
    Map<dynamic, dynamic> m => jsonEncode(m),
    _ => null,
  };
  final recipe = text == null ? null : RecipeLearner.parseRecipe(text, pageUrl);
  if (recipe == null) {
    throw const ToolError(
      'Pass the recipe as "recipe": a JSON object with at least one of '
      'fields, keyValue, tagGroups or constants, in the shape the '
      'instructions show.',
    );
  }
  return recipe;
}

/// One line per extracted field, with its length — the number that tells a
/// folded synopsis from the full one.
String _describe(MediaMetadata extracted) {
  final lines = <String>[
    for (final field in MetadataField.all)
      if (!extracted.isBlank(field))
        switch (extracted.get(field)) {
          List<Object?> items => '- $field: ${items.length} item(s)',
          final Object? value => () {
            final text = '$value';
            final shown = text.length > 120
                ? '${text.substring(0, 120)}…'
                : text;
            return '- $field (${text.length} chars): $shown';
          }(),
        },
  ];
  return lines.isEmpty ? 'It extracted nothing.' : lines.join('\n');
}

class _TestRecipeTool extends AgentTool<_LearnState> {
  const _TestRecipeTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'test_recipe',
    description:
        'Runs a draft recipe against this page and reports what each field '
        'extracts, with its length. Nothing is saved.',
    parameters: _recipeParameters,
  );

  @override
  String execute(Map<String, dynamic> arguments, _LearnState context) {
    final recipe = _recipeArgument(arguments, context.pageUrl);
    final extracted = RecipeApplier.apply(
      context.page.document,
      recipe,
      context.pageUrl,
    );
    final shortfall = ScrapePrompt.describeShortfall(extracted);
    return [
      _describe(extracted),
      shortfall == null
          ? 'This recipe can be submitted. Where a field could come from two '
                'places, compare their lengths first and prefer the longer '
                'copy.'
          : 'Not enough to submit yet. $shortfall',
    ].join('\n');
  }
}

class _SubmitRecipeTool extends AgentTool<_LearnState> {
  const _SubmitRecipeTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'submit_recipe',
    description:
        'Submits the finished recipe. It must extract a title and a code or '
        'poster from this page.',
    parameters: _recipeParameters,
  );

  @override
  String execute(Map<String, dynamic> arguments, _LearnState context) {
    final recipe = _recipeArgument(arguments, context.pageUrl);
    final extracted = RecipeApplier.apply(
      context.page.document,
      recipe,
      context.pageUrl,
    );
    final shortfall = ScrapePrompt.describeShortfall(extracted);
    if (shortfall != null) {
      throw ToolError(
        'Not accepted. $shortfall Fix the selectors, check them with '
        'test_recipe, and submit again.',
      );
    }
    context.submitted = recipe;
    return 'Recipe accepted.';
  }
}
