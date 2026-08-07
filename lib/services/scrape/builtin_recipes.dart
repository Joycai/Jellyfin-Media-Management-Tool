/// Recipes that ship with the app.
///
/// A built-in recipe is a starting point, not a lock: `RecipeStore` lets a
/// learned or user-edited recipe for the same domain take precedence, and a
/// built-in one is never mutated in place.
library;

import 'dart:convert';

import '../../models/scrape_recipe.dart';

class BuiltinRecipes {
  /// GIGA (www.giga-web.jp) — verified against a real product page on
  /// 2026-08-07, see `docs/spec/scrape-giga-recipe.md`.
  ///
  /// Three things about this site drove the shape of the recipe and are worth
  /// keeping in mind when adding the next one:
  ///
  /// * `skipStructuredData` is on because the page's OpenGraph block is a
  ///   *site-wide* template (`og:title` is the site name, `og:url` is the
  ///   home page). Trusting it would give every title identical metadata.
  /// * The real payload is a `dl/dt/dd` table, so most fields come from
  ///   [ScrapeRecipe.keyValue] keyed on Japanese labels rather than from CSS
  ///   classes — labels survive redesigns, class names do not.
  /// * The synopsis exists twice: `#story_list1` is truncated for display and
  ///   `#story_list2` holds the full text. The selector list puts the expanded
  ///   one first; getting this backwards yields a plausible-looking but
  ///   truncated plot, which no automatic check would catch.
  /// Raw string: the JSON below carries regex escapes (`\\s`, `\\d`) that must
  /// reach the JSON decoder intact.
  static const gigaWebJson = r'''
{
  "domain": "www.giga-web.jp",
  "pathPattern": "/product/*",
  "schemaVersion": 1,
  "cookies": "old_check=yes; layout=jpn",
  "headers": { "Accept-Language": "ja,en;q=0.8" },
  "minIntervalMs": 800,
  "skipStructuredData": true,
  "origin": "builtin",
  "fields": {
    "title":  { "selector": "#works_pic h5" },
    "plot":   { "selector": "#story_list2 li.story_window, #story_list1 li.story_window",
                "strip": ["span"] },
    "outline":{ "selector": "#eye_list2 li.story_window, #eye_list1 li.story_window",
                "strip": ["span"] },
    "rating": { "selector": "#review_header b", "transform": "double" },
    "poster": { "selector": "#works_pic img", "attr": "src", "resolve": true },
    "extraFanart": { "selector": "div.gasatsu a", "attr": "href",
                     "multiple": true, "resolve": true }
  },
  "keyValue": {
    "container": "#works_txt dl",
    "key": "dt",
    "value": "dd",
    "labelMap": {
      "作品番号":       { "field": "code" },
      "出演女優":       { "field": "actors",   "from": "a", "multiple": true },
      "監督":           { "field": "director", "from": "a" },
      "収録時間":       { "field": "runtimeMinutes",
                          "transform": "regexInt:本編\\s*(\\d+)\\s*分" },
      "DVDリリース日":  { "field": "premiered", "transform": "date" },
      "販売形態":       { "field": "tags", "from": "a", "multiple": true }
    }
  },
  "tagGroups": [
    {
      "container": "#tag",
      "header": "#tag_header",
      "items": "#tag_main a",
      "route": { "ジャンル": "genres", "キャラクター": "tags" }
    }
  ],
  "constants": { "studio": "GIGA" },
  "derive": {
    "series":       { "from": "code",  "transform": "regex:^([A-Za-z]+)" },
    "sortTitle":    { "from": "code",  "transform": "text" },
    "originalTitle":{ "from": "title", "transform": "text" }
  }
}
''';

  static final List<ScrapeRecipe> all = List.unmodifiable([
    ScrapeRecipe.fromJson(jsonDecode(gigaWebJson) as Map<String, dynamic>),
  ]);

  /// The built-in recipe for [url], or null.
  static ScrapeRecipe? forUrl(Uri url) {
    for (final r in all) {
      if (r.matches(url)) return r;
    }
    return null;
  }
}
