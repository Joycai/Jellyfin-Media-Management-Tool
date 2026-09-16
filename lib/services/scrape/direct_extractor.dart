/// Asks the model to read a page and report the metadata directly.
///
/// This is the manual override, not the default. The recipe ladder is tried
/// first and costs nothing on a site we already know; this exists for the two
/// cases it cannot serve:
///
/// * a site with no recipe where the user does not want to wait for one to be
///   learned and approved — they want the fields, now;
/// * a page where the recipe is right but the user wants something else out of
///   it, expressed in their own words ("the actress's other credits are in the
///   sidebar, use those as tags").
///
/// The trade-off is deliberate and worth stating plainly, because it is the
/// opposite of `RecipeLearner`'s: these values are the *model's*, not the
/// page's. Nothing verifies them against the document, so every field is
/// stamped [FieldOrigin.llm] — which makes the preview flag it in amber and
/// stops `NfoMerge` from letting it overwrite anything already on disk. It also
/// costs a call per title, so a folder refresh never uses it.
///
/// It runs as a tool loop over [PageInspector]: the model reads the parts of
/// the page it needs and submits fields as it finds them, so the page never
/// has to fit the window in one piece.
library;

import 'dart:convert';

import 'package:html/dom.dart';

import '../../models/media_metadata.dart';
import '../agent/agent_runtime.dart';
import '../ai/ai_cancel_token.dart';
import '../ai/ai_provider.dart';
import 'page_tools.dart';
import 'scrape_transform.dart';

/// What the model read off one page.
class DirectExtraction {
  /// Every non-blank field stamped [FieldOrigin.llm].
  final MediaMetadata metadata;

  final int promptTokens;
  final int completionTokens;

  const DirectExtraction({
    required this.metadata,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });
}

class DirectExtractor {
  final AiProvider provider;

  /// Runs once before the first model call. The scrape panel passes
  /// `AiService.ensureTools`, so a model that cannot call tools fails with a
  /// message saying so rather than with an empty result.
  final Future<void> Function()? beforeStart;

  /// Outline, a few sections, the images, a submission or two — with room for
  /// a model that reads more carefully than that.
  static const int maxRounds = 12;

  const DirectExtractor(this.provider, {this.beforeStart});

  /// Reads [document] and returns what the model found, or null when it
  /// submitted nothing usable.
  ///
  /// [instructions] is the user's own free text, appended verbatim as an extra
  /// requirement. It is theirs to write and is not sanitised beyond being
  /// clearly delimited — it steers the same request they already chose to make.
  Future<DirectExtraction?> extract({
    required Document document,
    required Uri pageUrl,
    String? instructions,
    AiCancelToken? cancelToken,
  }) async {
    final state = _ExtractState(PageInspector(document, pageUrl));
    if (state.page.outline.isEmpty && state.page.images.isEmpty) return null;

    await beforeStart?.call();
    cancelToken?.throwIfCancelled();
    final run = await AgentRuntime.run<_ExtractState>(
      provider: provider,
      messages: [
        SystemMessage(systemPrompt),
        UserMessage(
          buildTaskPrompt(
            pageUrl: pageUrl,
            outline: state.page.outlinePage(1),
            imageCount: state.page.images.length,
            instructions: instructions,
          ),
        ),
      ],
      tools: const [
        PageOutlineTool<_ExtractState>(),
        ReadSectionTool<_ExtractState>(),
        ListImagesTool<_ExtractState>(),
        _SubmitFieldsTool(),
      ],
      context: state,
      maxRounds: maxRounds,
      // Submitting does not end the run: the model may add fields it finds
      // later, and says it is finished by replying without a tool call.
      isDone: () => state.submissions > 0,
      stopWhenDone: false,
      nudge: () => state.submissions > 0
          ? null
          : 'You have not submitted anything yet. Read the page with '
                'read_section, then call submit_fields with what it states.',
      contextWindow: provider.config.contextWindow,
      cancelToken: cancelToken,
    );

    if (state.metadata.isEmpty) return null;
    return DirectExtraction(
      metadata: state.metadata,
      promptTokens: run.promptTokens,
      completionTokens: run.completionTokens,
    );
  }

  static final String systemPrompt =
      '''
You read one media product page and report its metadata.

You cannot see the page directly. Explore it with the tools:
- page_outline shows its structure, with node ids;
- read_section returns the text of a node, or of the whole page, a page at a
  time;
- list_images numbers the page's images.
Then call submit_fields with what you found. You may call it more than once;
a later value replaces an earlier one. When nothing is left to add, reply in
one short sentence without calling a tool.

Fields: ${MetadataField.all.join(', ')}

Types:
- runtimeMinutes: integer minutes. Convert "1h 25m" to 85. If the page gives a
  main feature and a bonus separately, report the main feature.
- rating: number.
- premiered: "YYYY-MM-DD". Convert any local date format to it.
- genres, tags: arrays of strings.
- actors: array of { "name": "...", "role": "..." }; omit role if unknown.
- poster, fanart: the NUMBER of an image from list_images. extraFanart: an
  array of image numbers.
- everything else: a string.

Rules:
- Report only what the page states. If a field is not on the page, leave it
  out. An omitted field is correct; a guessed one is a bug.
- Never invent an image: use only numbers list_images showed you.
- WHEN THE SAME TEXT APPEARS TWICE, ONCE TRUNCATED AND ONCE IN FULL, REPORT THE
  FULL COPY. Pages fold long synopses behind a "read more" control and leave
  both copies in the markup.
- Keep the original language. Do not translate, romanise or summarise.
- plot is the story synopsis. outline is a separate short blurb or staff
  comment, if the page has one; do not duplicate plot into it.''';

  static String buildTaskPrompt({
    required Uri pageUrl,
    required String outline,
    required int imageCount,
    String? instructions,
  }) {
    final extra = instructions?.trim() ?? '';
    return [
      'URL: $pageUrl',
      if (extra.isNotEmpty) ...[
        'Additional requirement from the user — follow it as well as the rules '
            'above, but never at the cost of inventing a value:',
        '"""',
        extra,
        '"""',
      ],
      '',
      'The page has $imageCount candidate image(s); call list_images to see '
          'them.',
      '',
      outline,
    ].join('\n');
  }

  /// Turns model JSON into metadata, dropping anything unusable.
  ///
  /// [allowedImages] is the list the model was told to choose from; a URL
  /// outside it is discarded rather than trusted, because a hallucinated
  /// poster URL is indistinguishable from a real one until it 404s at download
  /// time — by which point it is in the NFO.
  static MediaMetadata? parseFields(String raw, List<String> allowedImages) {
    final json = extractJsonMap(raw);
    if (json == null) return null;

    final allowed = allowedImages.toSet();
    final out = MediaMetadata();
    for (final field in MetadataField.all) {
      var value = json[field];
      if (value == null) continue;
      if (field == MetadataField.poster || field == MetadataField.fanart) {
        if (!allowed.contains(value.toString().trim())) continue;
      } else if (field == MetadataField.extraFanart) {
        if (value is! List) continue;
        final kept = [
          for (final v in value)
            if (allowed.contains(v.toString().trim())) v.toString().trim(),
        ];
        if (kept.isEmpty) continue;
        value = kept;
      }
      // `set` coerces defensively and silently drops what it cannot use, so a
      // single malformed field never costs the rest of the extraction.
      out.set(field, value, FieldOrigin.llm);
    }
    return out.isEmpty ? null : out;
  }
}

class _ExtractState implements HasPage {
  @override
  final PageInspector page;
  final MediaMetadata metadata = MediaMetadata();
  int submissions = 0;

  _ExtractState(this.page);
}

class _SubmitFieldsTool extends AgentTool<_ExtractState> {
  const _SubmitFieldsTool();

  static final Map<String, Object?> _schema = {
    'type': 'object',
    'properties': {
      for (final field in MetadataField.all)
        field: switch (field) {
          MetadataField.runtimeMinutes => {
            'type': 'integer',
            'description': 'Minutes of the main feature.',
          },
          MetadataField.rating => {'type': 'number'},
          MetadataField.premiered => {
            'type': 'string',
            'description': 'YYYY-MM-DD',
          },
          MetadataField.genres || MetadataField.tags => {
            'type': 'array',
            'items': {'type': 'string'},
          },
          MetadataField.actors => {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'role': {'type': 'string'},
              },
              'required': ['name'],
            },
          },
          MetadataField.poster || MetadataField.fanart => {
            'type': 'integer',
            'description': 'The number of an image from list_images.',
          },
          MetadataField.extraFanart => {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': 'Numbers of images from list_images.',
          },
          _ => {'type': 'string'},
        },
    },
  };

  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'submit_fields',
    description:
        'Stores metadata you found on the page. Pass only the fields the page '
        'states; a later value for a field replaces an earlier one.',
    parameters: _schema,
  );

  @override
  String execute(Map<String, dynamic> arguments, _ExtractState context) {
    final images = context.page.images;
    final translated = <String, Object?>{};
    for (final MapEntry(:key, :value) in arguments.entries) {
      switch (key) {
        case MetadataField.poster || MetadataField.fanart:
          final url = _image(value, images);
          if (url == null) {
            throw ToolError(
              '$key must be the number of an image from list_images '
              '(1 to ${images.length}).',
            );
          }
          translated[key] = url;
        case MetadataField.extraFanart:
          if (value is! List) {
            throw const ToolError(
              'extraFanart must be a list of image numbers from list_images.',
            );
          }
          translated[key] = [for (final v in value) ?_image(v, images)];
        default:
          translated[key] = value;
      }
    }

    final parsed = DirectExtractor.parseFields(jsonEncode(translated), images);
    if (parsed == null) {
      throw ToolError(
        'Nothing usable was submitted. Use these field names: '
        '${MetadataField.all.join(', ')} — with values the page states.',
      );
    }
    final stored = [
      for (final field in MetadataField.all)
        if (!parsed.isBlank(field)) field,
    ];
    for (final field in stored) {
      context.metadata.set(field, translated[field], FieldOrigin.llm);
    }
    context.submissions++;
    return 'Stored: ${stored.join(', ')}. Submit again to add or correct '
        'fields; reply without a tool call when nothing is left.';
  }

  /// The URL a model's image reference names: a 1-based number from
  /// list_images, or — leniently — a URL that is on the list.
  static String? _image(Object? value, List<String> images) {
    final number = switch (value) {
      num v => v.toInt(),
      String v => int.tryParse(v.trim()),
      _ => null,
    };
    if (number != null) {
      return number >= 1 && number <= images.length ? images[number - 1] : null;
    }
    final url = value?.toString().trim();
    return url != null && images.contains(url) ? url : null;
  }
}
