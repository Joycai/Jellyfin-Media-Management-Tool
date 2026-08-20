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
library;

import 'scrape_transform.dart';

import 'package:html/dom.dart';

import '../../models/media_metadata.dart';
import '../ai/ai_cancel_token.dart';
import '../ai/ai_provider.dart';
import 'page_digest.dart';

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

  const DirectExtractor(this.provider);

  /// Reads [document] and returns what the model found, or null when it
  /// returned nothing usable.
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
    final digest = PageDigest.of(document, pageUrl);
    if (digest.isEmpty) return null;

    cancelToken?.throwIfCancelled();
    final response = await provider.complete(
      systemPrompt: systemPrompt,
      userPrompt: buildUserPrompt(
        pageUrl: pageUrl,
        digest: digest,
        instructions: instructions,
      ),
      cancelToken: cancelToken,
    );

    final metadata = parseFields(response.text, digest.images);
    if (metadata == null) return null;
    return DirectExtraction(
      metadata: metadata,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
    );
  }

  static final String systemPrompt =
      '''
You read one media product page and report its metadata as JSON.

Return a single JSON object. Use only these keys, and omit any you cannot fill
from the page:
${MetadataField.all.join(', ')}

Types:
- runtimeMinutes: integer minutes. Convert "1h 25m" to 85. If the page gives a
  main feature and a bonus separately, report the main feature.
- rating: number.
- premiered: "YYYY-MM-DD". Convert any local date format to it.
- genres, tags, extraFanart: arrays of strings.
- actors: array of { "name": "...", "role": "..." }; omit role if unknown.
- poster, fanart: one image URL each, copied EXACTLY from the numbered list of
  images given below. extraFanart: an array of them.
- everything else: a string.

Rules:
- Report only what the page states. If a field is not on the page, omit the
  key. An omitted field is correct; a guessed one is a bug.
- Never invent an image URL. Every URL you return must appear in the list.
- WHEN THE SAME TEXT APPEARS TWICE, ONCE TRUNCATED AND ONCE IN FULL, RETURN THE
  FULL COPY. Pages fold long synopses behind a "read more" control and leave
  both copies in the markup.
- Keep the original language. Do not translate, romanise or summarise.
- plot is the story synopsis. outline is a separate short blurb or staff
  comment, if the page has one; do not duplicate plot into it.
- Return the JSON object alone, with no commentary.''';

  static String buildUserPrompt({
    required Uri pageUrl,
    required PageDigest digest,
    String? instructions,
  }) {
    final extra = instructions?.trim() ?? '';
    final images = <String>[
      for (var i = 0; i < digest.images.length; i++)
        '${i + 1}. ${digest.images[i]}',
    ];

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
      'Images available on the page (choose from these only):',
      images.isEmpty ? '(none)' : images.join('\n'),
      '',
      'Page text:',
      digest.text,
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
