/// Prompts for tier 3: asking the model to write a [ScrapeRecipe] for a site
/// it has never seen.
///
/// Static and pure, mirroring `AiPrompt` — no provider dependency, so the exact
/// text can be asserted in a test.
///
/// The one idea worth restating: the model is asked for **selectors, not
/// content**. A model that reads the page and hands back the title has produced
/// something that works once; a model that hands back `#works_pic h5` has
/// produced something that works for every title on the site and can be
/// reviewed, stored, and retired when the site changes.
library;

import '../../models/media_metadata.dart';
import 'builtin_recipes.dart';

class ScrapePrompt {
  static final String systemPrompt =
      '''
You write extraction recipes for media product pages. You are given a stripped
skeleton of one page's HTML. Return a JSON recipe describing HOW to find each
field with CSS selectors — never the field values themselves.

Fields you may target (anything else is ignored):
${MetadataField.all.join(', ')}

Two extraction shapes, and you should use both when the page offers both:

- "fields": one entry per field.
    { "selector": "css, css2", "attr": "text|src|href",
      "multiple": true, "resolve": true, "strip": ["css"],
      "transform": "<spec>" }
  "selector" is a priority-ordered list: the FIRST that matches wins.
  "attr" defaults to "text". "resolve" makes a src/href absolute.
  "strip" removes descendants before reading text (use it to drop
  "show more" / "close" links that live inside a text block).

- "keyValue": a definition table (dl/dt/dd, or tr/th/td).
    { "container": "css for one row", "key": "dt", "value": "dd",
      "labelMap": { "<label text on the page>": { "field": "code",
                    "from": "a", "multiple": true, "transform": "<spec>" } } }
  PREFER THIS wherever the page has a labelled table. A label like
  "Runtime" or "作品番号" survives a redesign that renames every CSS class.
  Copy the label text exactly as it appears, including any non-Latin script.

Optional extras:
- "tagGroups": [{ "container": "...", "header": "...", "items": "...",
                  "route": { "<header substring>": "genres" } }]
  For pages that reuse one container id for several tag blocks that are only
  told apart by their heading text.
- "constants": { "studio": "..." } for values fixed across the whole site.
- "derive": { "series": { "from": "code", "transform": "regex:^([A-Za-z]+)" } }
  computes one field from another already-extracted one.
- "skipStructuredData": true when the page's OpenGraph/JSON-LD block is a
  site-wide template (og:title is the site name, og:url is the home page)
  rather than a description of THIS product.
- "cookies": "name=value; name2=value2" for a static gate such as an age check.
  Never invent a session or login cookie.

transform grammar (the value after "transform"):
  text                  the string unchanged (the default)
  int                   first number as an integer
  double                first number as a decimal
  date                  ISO yyyy-MM-dd from the first year/month/day triple;
                        it already handles 2026/08/14, 2026-08-14 and
                        2026年8月14日, so never write a format string
  regex:<pattern>       first capture group, as text
  regexInt:<pattern>    first capture group, as an integer

Rules:
- Selectors must come from the skeleton you were given. Do not guess ids or
  class names that are not there.
- WHEN THE SAME TEXT APPEARS TWICE, PREFER THE LONGER COPY. Pages routinely
  ship a truncated synopsis for display and the full one hidden next to it.
  Put the full one first in the selector list. Picking the short one produces
  a recipe that looks perfectly healthy and silently stores truncated text.
- Prefer an id or a stable-looking class over a long descendant chain.
- Omit a field you cannot locate. A missing field is fine; a wrong selector
  pollutes every title on the site.
- Output ONLY the JSON object. No markdown fences, no prose.

Here is a complete, working recipe for a different site. Match its structure:

${BuiltinRecipes.gigaWebJson.trim()}
''';

  /// The user turn: which page this is, plus its skeleton.
  ///
  /// [feedback] is set on the retry and names what the previous attempt failed
  /// to extract. Handing the model its own miss is worth far more than simply
  /// asking again at a higher temperature.
  static String buildUserPrompt({
    required Uri pageUrl,
    required String skeleton,
    String? feedback,
  }) {
    final b = StringBuffer()
      ..writeln('Domain: ${pageUrl.host}')
      ..writeln('URL: $pageUrl')
      ..writeln('Suggested pathPattern: ${suggestPathPattern(pageUrl)}')
      ..writeln();
    if (feedback != null && feedback.isNotEmpty) {
      b
        ..writeln('Your previous recipe did not work. $feedback')
        ..writeln('Look again at the skeleton and choose different selectors.')
        ..writeln();
    }
    b
      ..writeln('Page skeleton:')
      ..writeln(skeleton);
    return b.toString();
  }

  /// A glob covering sibling product pages: the path with its last segment
  /// replaced by `*`, so `/product/index.php` becomes `/product/*`.
  ///
  /// Only a suggestion — the model may return something narrower, and
  /// `ScrapeRecipe.matches` treats an empty pattern as "any path".
  static String suggestPathPattern(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    if (segments.length == 1) return '/*';
    return '/${segments.sublist(0, segments.length - 1).join('/')}/*';
  }

  /// Names the required fields a learned recipe failed to produce, for the
  /// retry turn. Returns null when the recipe is good enough to keep.
  ///
  /// "Good enough" is a title plus something that identifies the release — a
  /// catalogue code or a poster. A recipe that finds only a title has almost
  /// certainly locked onto the site's header.
  static String? describeShortfall(MediaMetadata extracted) {
    final missing = <String>[
      if (extracted.isBlank(MetadataField.title)) 'title',
      if (extracted.isBlank(MetadataField.code) &&
          extracted.isBlank(MetadataField.poster))
        'code or poster',
    ];
    if (missing.isEmpty) return null;
    return 'It extracted nothing for: ${missing.join(', ')}.';
  }
}
