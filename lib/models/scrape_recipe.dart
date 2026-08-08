/// A "recipe" describes how to pull metadata out of one site's product page.
///
/// Recipes are data, not code: they ship built in, get learned by the LLM, or
/// get hand-edited, and they round-trip through `scrapers.json`. Keeping them
/// declarative is what lets a new site be supported without a release.
///
/// Two extraction shapes are supported, because real pages use both:
///
/// * [fields] — one CSS selector per field. Good for the title, the poster,
///   the synopsis block.
/// * [keyValue] — walk a `dl/dt/dd` (or `tr/th/td`) table and map the *label
///   text* to a field. Preferred wherever a page has one: labels like
///   `作品番号` survive a redesign that renames every CSS class.
library;

import 'dart:convert';

/// How to read one value out of a matched element.
class FieldRule {
  /// Selectors in priority order; the first one that matches wins. This is how
  /// "prefer the expanded synopsis, fall back to the collapsed one" is
  /// expressed as data.
  final List<String> selectors;

  /// `text` for the element's text, otherwise an attribute name (`src`, `href`).
  final String attr;

  /// Collect every match instead of the first.
  final bool multiple;

  /// Resolve the value against the page URL (for `src`/`href`).
  final bool resolve;

  /// Descendant selectors removed before reading text — used to drop
  /// "show more / collapse" links that live inside the text block.
  final List<String> strip;

  /// See `RecipeApplier` for the supported transform grammar.
  final String? transform;

  const FieldRule({
    required this.selectors,
    this.attr = 'text',
    this.multiple = false,
    this.resolve = false,
    this.strip = const [],
    this.transform,
  });

  Map<String, dynamic> toJson() => {
    'selector': selectors.join(', '),
    if (attr != 'text') 'attr': attr,
    if (multiple) 'multiple': true,
    if (resolve) 'resolve': true,
    if (strip.isNotEmpty) 'strip': strip,
    if (transform != null) 'transform': transform,
  };

  factory FieldRule.fromJson(Map<String, dynamic> json) => FieldRule(
    selectors: _selectorList(json['selector']),
    attr: (json['attr'] as String?)?.trim() ?? 'text',
    multiple: json['multiple'] == true,
    resolve: json['resolve'] == true,
    strip: _stringList(json['strip']),
    transform: (json['transform'] as String?)?.trim(),
  );

  /// Accepts either a list or a single comma-joined selector string, since an
  /// LLM will produce both and CSS itself treats `a, b` as a group.
  static List<String> _selectorList(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return raw
            ?.toString()
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [];
  }

  static List<String> _stringList(Object? raw) => raw is List
      ? raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
      : const [];
}

/// One row of a key/value table: which field the label maps to, and how to
/// read the value cell.
class LabelRule {
  final String field;

  /// Take every `<a>` (or whatever selector) inside the value cell instead of
  /// the cell's flat text — that is how a multi-actor cell is split.
  final String? from;
  final bool multiple;
  final String? transform;

  const LabelRule({
    required this.field,
    this.from,
    this.multiple = false,
    this.transform,
  });

  Map<String, dynamic> toJson() => {
    'field': field,
    if (from != null) 'from': from,
    if (multiple) 'multiple': true,
    if (transform != null) 'transform': transform,
  };

  factory LabelRule.fromJson(Map<String, dynamic> json) => LabelRule(
    field: (json['field'] as String?)?.trim() ?? '',
    from: (json['from'] as String?)?.trim(),
    multiple: json['multiple'] == true,
    transform: (json['transform'] as String?)?.trim(),
  );
}

/// A `dl/dt/dd`-style table of labelled values.
class KeyValueRule {
  /// Selector for each row (e.g. `#works_txt dl`).
  final String container;

  /// Selector for the label cell, relative to a row.
  final String key;

  /// Selector for the value cell, relative to a row.
  final String value;

  /// Page label (exact, after whitespace normalization) -> rule.
  final Map<String, LabelRule> labelMap;

  const KeyValueRule({
    required this.container,
    this.key = 'dt',
    this.value = 'dd',
    this.labelMap = const {},
  });

  Map<String, dynamic> toJson() => {
    'container': container,
    'key': key,
    'value': value,
    'labelMap': {for (final e in labelMap.entries) e.key: e.value.toJson()},
  };

  factory KeyValueRule.fromJson(Map<String, dynamic> json) => KeyValueRule(
    container: (json['container'] as String?)?.trim() ?? '',
    key: (json['key'] as String?)?.trim() ?? 'dt',
    value: (json['value'] as String?)?.trim() ?? 'dd',
    labelMap: {
      for (final e in ((json['labelMap'] as Map?) ?? const {}).entries)
        if (e.value is Map)
          e.key.toString(): LabelRule.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
    },
  );
}

/// Several tag blocks that are only told apart by their header text.
///
/// Exists because pages routinely reuse one id for "genre tags" and
/// "character tags"; matching on the header is the only reliable split.
class TagGroupRule {
  final String container;
  final String header;
  final String items;

  /// Substring of the header text -> target field key.
  final Map<String, String> route;

  const TagGroupRule({
    required this.container,
    required this.header,
    required this.items,
    this.route = const {},
  });

  Map<String, dynamic> toJson() => {
    'container': container,
    'header': header,
    'items': items,
    'route': route,
  };

  factory TagGroupRule.fromJson(Map<String, dynamic> json) => TagGroupRule(
    container: (json['container'] as String?)?.trim() ?? '',
    header: (json['header'] as String?)?.trim() ?? '',
    items: (json['items'] as String?)?.trim() ?? '',
    route: {
      for (final e in ((json['route'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
  );
}

/// Compute one field from another already-extracted one.
class DeriveRule {
  final String from;
  final String transform;

  const DeriveRule({required this.from, required this.transform});

  Map<String, dynamic> toJson() => {'from': from, 'transform': transform};

  factory DeriveRule.fromJson(Map<String, dynamic> json) => DeriveRule(
    from: (json['from'] as String?)?.trim() ?? '',
    transform: (json['transform'] as String?)?.trim() ?? '',
  );
}

/// Where a recipe came from. Built-in recipes are never overwritten by a
/// learned one in place — a learned recipe is stored separately and wins by
/// being more specific, so a bad learning run can always be discarded.
enum RecipeOrigin { builtin, llm, user }

/// Everything needed to fetch and parse one site's product pages.
class ScrapeRecipe {
  /// Host this applies to, matched case-insensitively with an optional
  /// leading `www.` on either side.
  final String domain;

  /// Glob over the URL path (`*` matches any run of characters). Empty means
  /// "any path on this domain".
  final String pathPattern;

  final int schemaVersion;

  /// Static request cookies, e.g. an age-gate flag. Sent verbatim.
  final String? cookies;

  /// A URL to request once per host before the first page, so the server can
  /// establish a session.
  ///
  /// Age gates increasingly work this way: clicking "I am over 18" sets a flag
  /// cookie *and* marks the session verified server-side, so replaying the flag
  /// on its own gets you the gate again. Relative values resolve against the
  /// page being fetched. Cookies the response sets are held in memory for the
  /// run and never persisted — see [CookieStore] for why that distinction
  /// matters.
  final String? sessionUrl;

  /// `Referer` to send on page fetches; relative values resolve against the
  /// page. Defaults to the site root, because some sites bounce a request that
  /// arrives with no referer at all. An empty string disables the header.
  final String? referer;

  final Map<String, String> headers;

  /// Politeness floor between two requests to the same host.
  final int minIntervalMs;

  /// Set when a site's OpenGraph/JSON-LD is a site-wide template and would
  /// otherwise poison every result with the same values.
  final bool skipStructuredData;

  final Map<String, FieldRule> fields;
  final KeyValueRule? keyValue;
  final List<TagGroupRule> tagGroups;

  /// Values that are constant for the whole site (e.g. the studio name).
  final Map<String, String> constants;

  final Map<String, DeriveRule> derive;

  final RecipeOrigin origin;

  /// Rolling health counters. Two consecutive failures retire the recipe —
  /// that is the entire implementation of "detect the site redesign".
  int successCount;
  int failCount;

  ScrapeRecipe({
    required this.domain,
    this.pathPattern = '',
    this.schemaVersion = 1,
    this.cookies,
    this.sessionUrl,
    this.referer,
    this.headers = const {},
    this.minIntervalMs = 800,
    this.skipStructuredData = false,
    this.fields = const {},
    this.keyValue,
    this.tagGroups = const [],
    this.constants = const {},
    this.derive = const {},
    this.origin = RecipeOrigin.builtin,
    this.successCount = 0,
    this.failCount = 0,
  });

  /// Current schema. Bump when a rule's meaning changes so stale learned
  /// recipes are discarded instead of silently misparsed.
  static const currentSchemaVersion = 1;

  /// Retired after this many consecutive failures.
  static const maxConsecutiveFailures = 2;

  bool get isRetired => failCount >= maxConsecutiveFailures;

  bool get isStale => schemaVersion != currentSchemaVersion;

  /// True when this recipe should handle [url].
  bool matches(Uri url) {
    if (_bareHost(url.host) != _bareHost(domain)) return false;
    if (pathPattern.isEmpty) return true;
    return _globMatches(pathPattern, url.path);
  }

  static String _bareHost(String host) {
    final h = host.toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  /// Minimal glob: `*` matches any run of characters, everything else is
  /// literal. Deliberately not a regex — recipes are user-editable data and a
  /// regex there is a footgun.
  static bool _globMatches(String pattern, String path) {
    final escaped = pattern.split('*').map(RegExp.escape).join('.*');
    return RegExp('^$escaped\$').hasMatch(path);
  }

  Map<String, dynamic> toJson() => {
    'domain': domain,
    if (pathPattern.isNotEmpty) 'pathPattern': pathPattern,
    'schemaVersion': schemaVersion,
    if (cookies != null) 'cookies': cookies,
    if (sessionUrl != null) 'sessionUrl': sessionUrl,
    if (referer != null) 'referer': referer,
    if (headers.isNotEmpty) 'headers': headers,
    'minIntervalMs': minIntervalMs,
    if (skipStructuredData) 'skipStructuredData': true,
    if (fields.isNotEmpty)
      'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
    if (keyValue != null) 'keyValue': keyValue!.toJson(),
    if (tagGroups.isNotEmpty)
      'tagGroups': [for (final g in tagGroups) g.toJson()],
    if (constants.isNotEmpty) 'constants': constants,
    if (derive.isNotEmpty)
      'derive': {for (final e in derive.entries) e.key: e.value.toJson()},
    'origin': origin.name,
    'successCount': successCount,
    'failCount': failCount,
  };

  factory ScrapeRecipe.fromJson(Map<String, dynamic> json) => ScrapeRecipe(
    domain: (json['domain'] as String?)?.trim() ?? '',
    pathPattern: (json['pathPattern'] as String?)?.trim() ?? '',
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
    cookies: (json['cookies'] as String?)?.trim(),
    sessionUrl: (json['sessionUrl'] as String?)?.trim(),
    referer: (json['referer'] as String?)?.trim(),
    headers: {
      for (final e in ((json['headers'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
    minIntervalMs: (json['minIntervalMs'] as num?)?.toInt() ?? 800,
    skipStructuredData: json['skipStructuredData'] == true,
    fields: {
      for (final e in ((json['fields'] as Map?) ?? const {}).entries)
        if (e.value is Map)
          e.key.toString(): FieldRule.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
    },
    keyValue: json['keyValue'] is Map
        ? KeyValueRule.fromJson(
            Map<String, dynamic>.from(json['keyValue'] as Map),
          )
        : null,
    tagGroups: [
      for (final g in (json['tagGroups'] as List?) ?? const [])
        if (g is Map) TagGroupRule.fromJson(Map<String, dynamic>.from(g)),
    ],
    constants: {
      for (final e in ((json['constants'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
    derive: {
      for (final e in ((json['derive'] as Map?) ?? const {}).entries)
        if (e.value is Map)
          e.key.toString(): DeriveRule.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
    },
    origin: RecipeOrigin.values.firstWhere(
      (o) => o.name == json['origin'],
      orElse: () => RecipeOrigin.user,
    ),
    successCount: (json['successCount'] as num?)?.toInt() ?? 0,
    failCount: (json['failCount'] as num?)?.toInt() ?? 0,
  );

  /// Convenience for tests and for the built-in table.
  static ScrapeRecipe parse(String jsonText) =>
      ScrapeRecipe.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);
}
