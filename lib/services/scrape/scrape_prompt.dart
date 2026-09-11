/// Prompts for tier 3: asking the model to write a [ScrapeRecipe] for a site
/// it has never seen.
///
/// Static and pure — no provider dependency, so the exact text can be
/// asserted in a test.
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
You write extraction recipes for media product pages: JSON describing HOW to
find each field with CSS selectors — never the field values themselves.

You cannot see the page directly. Explore it with the tools:
- page_outline shows its structure, with node ids;
- inspect shows the markup of one node, so you can read its ids, classes and
  labels;
- query tries a selector and shows what it matches.
Then call test_recipe with a draft recipe and read what it extracts. Fix the
selectors until it finds the fields, and call submit_recipe with the recipe.

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
- Selectors must come from what the tools showed you. Do not guess ids or
  class names you have not seen.
- WHEN THE SAME TEXT APPEARS TWICE, PREFER THE LONGER COPY. Pages routinely
  ship a truncated synopsis for display and the full one hidden next to it.
  test_recipe reports each value's length: compare them, and put the full
  copy first in the selector list. Picking the short one produces a recipe
  that looks perfectly healthy and silently stores truncated text.
- Prefer an id or a stable-looking class over a long descendant chain.
- Omit a field you cannot locate. A missing field is fine; a wrong selector
  pollutes every title on the site.
- Pass the recipe as the tool's "recipe" argument, as a JSON object.

Here is a complete, working recipe for a different site. Match its structure:

${BuiltinRecipes.gigaWebJson.trim()}
''';

  /// The task turn: which page this is, and the first page of its outline so
  /// the model can start exploring without spending a round asking for it.
  static String buildTaskPrompt({
    required Uri pageUrl,
    required String outline,
  }) => [
    'Domain: ${pageUrl.host}',
    'URL: $pageUrl',
    'Suggested pathPattern: ${suggestPathPattern(pageUrl)}',
    '',
    outline,
  ].join('\n');

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

  /// Names the required fields a recipe failed to produce, or null when it is
  /// good enough to keep.
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
