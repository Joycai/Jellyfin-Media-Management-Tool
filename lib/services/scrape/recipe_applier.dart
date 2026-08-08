/// Runs a [ScrapeRecipe] against a parsed page. Pure and synchronous — no
/// network, no filesystem, no Provider — so the whole extraction layer is
/// unit-testable against an offline fixture.
library;

import 'package:html/dom.dart';

import '../../models/media_metadata.dart';
import '../../models/scrape_recipe.dart';
import 'scrape_transform.dart';

/// Collapses every run of whitespace to a single space and trims.
///
/// `　` (IDEOGRAPHIC SPACE) is listed explicitly: Dart's `\s` does cover
/// it, but Japanese pages use it as a real separator (`本編85分　メイキング5分`)
/// and spelling it out keeps that non-obvious dependency visible.
String normalizeWhitespace(String input) =>
    input.replaceAll(RegExp(r'[\s　]+'), ' ').trim();

class RecipeApplier {
  /// Extracts everything [recipe] knows how to find from [document].
  ///
  /// [pageUrl] is needed to resolve relative `src`/`href` values — it is the
  /// URL the document was *fetched* from, not the one in the recipe.
  ///
  /// Never throws: a selector that fails to compile, a missing element or a
  /// transform that yields nothing all mean "this field was not found". The
  /// caller decides whether the result is good enough by looking at
  /// [MediaMetadata.isEmpty] or its own required-field list.
  static MediaMetadata apply(
    Document document,
    ScrapeRecipe recipe,
    Uri pageUrl,
  ) {
    final out = MediaMetadata(sourceUrl: pageUrl.toString());
    final root = document.documentElement;
    if (root == null) return out;

    // Site-wide constants first so a page-level value can override them.
    for (final e in recipe.constants.entries) {
      out.set(e.key, e.value, FieldOrigin.recipe);
    }
    for (final e in recipe.fields.entries) {
      final v = _extractField(root, e.value, pageUrl);
      if (v != null) out.set(e.key, v, FieldOrigin.recipe);
    }
    final kv = recipe.keyValue;
    if (kv != null) _applyKeyValue(root, kv, out);
    for (final g in recipe.tagGroups) {
      _applyTagGroup(root, g, out);
    }
    // Derivations run last and only fill gaps — a value actually printed on
    // the page always beats one we computed.
    for (final e in recipe.derive.entries) {
      if (!out.isBlank(e.key)) continue;
      final src = out.get(e.value.from);
      if (src == null) continue;
      final v = ScrapeTransform.apply(src.toString(), e.value.transform);
      if (v != null) out.set(e.key, v, FieldOrigin.derived);
    }
    return out;
  }

  // ---------------------------------------------------------------- fields

  static Object? _extractField(Element root, FieldRule rule, Uri pageUrl) {
    for (final selector in rule.selectors) {
      final matched = _queryAll(root, selector);
      if (matched.isEmpty) continue;

      // First selector that matches anything wins outright; later ones are
      // fallbacks, not additional sources. This is what makes
      // "#story_list2, #story_list1" mean "prefer expanded, else collapsed".
      if (!rule.multiple) {
        final v = _read(matched.first, rule, pageUrl);
        final t = v == null ? null : ScrapeTransform.apply(v, rule.transform);
        if (t != null) return t;
        continue; // matched but unreadable — let the next selector try
      }
      final values = <Object>[];
      for (final el in matched) {
        final v = _read(el, rule, pageUrl);
        if (v == null) continue;
        final t = ScrapeTransform.apply(v, rule.transform);
        if (t != null) values.add(t);
      }
      if (values.isNotEmpty) return values;
    }
    return null;
  }

  /// Reads one element per [rule]: its text (optionally with sub-elements
  /// stripped) or one of its attributes.
  static String? _read(Element el, FieldRule rule, Uri pageUrl) {
    String? raw;
    if (rule.attr == 'text') {
      var target = el;
      if (rule.strip.isNotEmpty) {
        // Clone before mutating: the caller's document may be reused by
        // another rule, and silently deleting nodes from it would make
        // extraction order-dependent.
        target = el.clone(true);
        for (final s in rule.strip) {
          for (final node in _queryAll(target, s)) {
            node.remove();
          }
        }
      }
      raw = _textOf(target);
    } else {
      raw = el.attributes[rule.attr];
    }
    if (raw == null) return null;
    final value = normalizeWhitespace(raw);
    if (value.isEmpty) return null;
    return rule.resolve ? resolveUrl(pageUrl, value) : value;
  }

  // ------------------------------------------------------------- key/value

  static void _applyKeyValue(Element root, KeyValueRule kv, MediaMetadata out) {
    if (kv.container.isEmpty) return;
    for (final row in _queryAll(root, kv.container)) {
      final keyEl = _queryFirst(row, kv.key);
      final valueEl = _queryFirst(row, kv.value);
      if (keyEl == null || valueEl == null) continue;

      final label = normalizeWhitespace(_textOf(keyEl));
      final rule = kv.labelMap[label];
      if (rule == null || rule.field.isEmpty) continue;

      Object? value;
      final from = rule.from;
      if (from != null && from.isNotEmpty) {
        final parts = <String>[];
        for (final el in _queryAll(valueEl, from)) {
          final t = normalizeWhitespace(_textOf(el));
          if (t.isNotEmpty) parts.add(t);
        }
        if (parts.isEmpty) continue;
        value = rule.multiple ? parts : parts.first;
      } else {
        final t = normalizeWhitespace(_textOf(valueEl));
        if (t.isEmpty) continue;
        value = rule.multiple ? [t] : t;
      }

      final Object? transformed;
      if (value is List) {
        final list = <Object>[];
        for (final v in value) {
          final t = ScrapeTransform.apply(v.toString(), rule.transform);
          if (t != null) list.add(t);
        }
        transformed = list.isEmpty ? null : list;
      } else {
        transformed = ScrapeTransform.apply(value.toString(), rule.transform);
      }
      if (transformed == null) continue;
      out.set(rule.field, transformed, FieldOrigin.recipe);
    }
  }

  // ------------------------------------------------------------ tag groups

  /// Routes each tag block to a field by matching its header text.
  ///
  /// Blocks that route to the same field are appended, not replaced, so a page
  /// listing genres in two separate boxes ends up with both.
  static void _applyTagGroup(
    Element root,
    TagGroupRule group,
    MediaMetadata out,
  ) {
    if (group.container.isEmpty) return;
    for (final block in _queryAll(root, group.container)) {
      final headerEl = _queryFirst(block, group.header);
      if (headerEl == null) continue;
      final header = normalizeWhitespace(_textOf(headerEl));

      String? field;
      for (final route in group.route.entries) {
        if (header.contains(route.key)) {
          field = route.value;
          break;
        }
      }
      if (field == null) continue;

      final items = <String>[];
      for (final el in _queryAll(block, group.items)) {
        final t = normalizeWhitespace(_textOf(el));
        if (t.isNotEmpty) items.add(t);
      }
      if (items.isEmpty) continue;

      final existing = out.get(field);
      out.set(field, [
        if (existing is List<String>) ...existing,
        ...items,
      ], FieldOrigin.recipe);
    }
  }

  // ---------------------------------------------------------------- helpers

  /// Resolves [reference] against [base]. Returns it unchanged when it is not
  /// parseable as a URL — some pages carry javascript: or data: junk in `src`,
  /// and dropping the field is worse than handing the raw value to the user.
  static String resolveUrl(Uri base, String reference) {
    try {
      return base.resolve(reference).toString();
    } on FormatException {
      return reference;
    }
  }

  /// `Node.text` is `String?`, but `Element` narrows the override to a
  /// non-nullable `String`. Kept as a helper so the call sites read the same
  /// either way if the package ever widens it back.
  static String _textOf(Element el) => el.text;

  /// querySelectorAll that swallows selector-compilation failures. Recipes can
  /// come from an LLM, so an unparseable selector is an expected input.
  static List<Element> _queryAll(Element scope, String selector) {
    if (selector.isEmpty) return const [];
    try {
      return scope.querySelectorAll(selector);
    } catch (_) {
      return const [];
    }
  }

  static Element? _queryFirst(Element scope, String selector) {
    if (selector.isEmpty) return null;
    try {
      return scope.querySelector(selector);
    } catch (_) {
      return null;
    }
  }
}
