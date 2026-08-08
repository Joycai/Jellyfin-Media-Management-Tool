/// Compresses a product page into a "skeleton" cheap enough to send to a model.
///
/// Tier 3 asks the LLM for *selectors*, not content, so everything that cannot
/// appear in a selector is dead weight: scripts, styling, inline SVG paths, and
/// the bulk of the visible text. A 200 KB page reduces to roughly 20–30 KB, and
/// the main-region heuristic usually takes it well below that.
///
/// Pure and static, like `AiPrompt` — no provider, no filesystem, unit-testable
/// on a fixture.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class HtmlCleaner {
  /// Elements dropped whole. None of them can hold metadata a recipe would
  /// target, and `script`/`style` alone are usually most of a page's bytes.
  static const droppedTags = {
    'script',
    'style',
    'svg',
    'noscript',
    'iframe',
    'template',
    'head',
    'link',
    'meta',
    'form',
    'input',
    'button',
    'select',
    'textarea',
    'canvas',
    'video',
    'audio',
    'embed',
    'object',
  };

  /// Attributes kept. `id` and `class` are what a selector is built from;
  /// `itemprop` is microdata worth targeting; `href`/`src`/`data-src` are the
  /// values a rule extracts. `data-src` earns its place because lazy-loading
  /// images put the real URL there and leave `src` as a placeholder.
  static const keptAttributes = {
    'id',
    'class',
    'itemprop',
    'href',
    'src',
    'data-src',
  };

  /// Text nodes are cut to this many characters. The model needs enough to
  /// recognise a label like `作品番号` or to tell two candidate blocks apart —
  /// never the whole synopsis.
  static const int defaultMaxTextLength = 80;

  /// Hard ceiling on the returned string, so one pathological page cannot
  /// blow the context window.
  static const int defaultMaxChars = 60000;

  /// Containers that usually hold the real content, most specific first.
  static const _mainCandidates = [
    'main',
    '[role=main]',
    '#main',
    '#content',
    '#container',
    '.main',
    '.content',
    'article',
  ];

  /// A candidate must hold at least this share of the body's text before it is
  /// trusted as "the main region" — otherwise a decorative `<main>` wrapper
  /// around a sidebar would throw away the part we actually want.
  static const double _mainTextShare = 0.4;

  /// Returns the cleaned skeleton of [html].
  ///
  /// Parses its own copy, so the caller's document is never mutated — the
  /// scrape pipeline reuses that document for extraction and for the learned
  /// recipe's self-check.
  static String clean(
    String html, {
    int maxTextLength = defaultMaxTextLength,
    int maxChars = defaultMaxChars,
  }) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return '';

    _strip(body, maxTextLength);

    final region = _mainRegion(body);
    final out = _collapse(region.innerHtml);
    return out.length <= maxChars
        ? out
        : '${out.substring(0, maxChars)}\n<!-- truncated -->';
  }

  /// Removes dead elements, comments and attributes, and shortens text, depth
  /// first so a child is handled before its parent is measured.
  static void _strip(Element element, int maxTextLength) {
    // Copy first: removing while iterating the live child list skips siblings.
    for (final node in List<Node>.of(element.nodes)) {
      if (node is Comment) {
        node.remove();
        continue;
      }
      if (node is Text) {
        final collapsed = _collapse(node.data);
        if (collapsed.isEmpty) {
          node.remove();
        } else {
          node.data = collapsed.length <= maxTextLength
              ? collapsed
              : '${collapsed.substring(0, maxTextLength)}…';
        }
        continue;
      }
      if (node is Element) {
        if (droppedTags.contains(node.localName)) {
          node.remove();
          continue;
        }
        node.attributes.removeWhere(
          (name, _) => !keptAttributes.contains(name.toString()),
        );
        _strip(node, maxTextLength);
      }
    }
  }

  /// Narrows to the sub-tree holding the bulk of the text, or returns [body]
  /// when no candidate is convincing enough.
  static Element _mainRegion(Element body) {
    final total = body.text.trim().length;
    if (total == 0) return body;
    for (final selector in _mainCandidates) {
      final Element? candidate;
      try {
        candidate = body.querySelector(selector);
      } catch (_) {
        // Recipes are not the only source of unparseable selectors — some
        // engines reject `[role=main]` unquoted. Skip rather than fail.
        continue;
      }
      if (candidate == null) continue;
      if (candidate.text.trim().length >= total * _mainTextShare) {
        return candidate;
      }
    }
    return body;
  }

  static String _collapse(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
