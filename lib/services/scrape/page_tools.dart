/// Read-only tools for exploring one fetched product page, shared by the two
/// scrape agents: learning a recipe, which needs the page's structure, and
/// extracting fields directly, which needs its text.
///
/// The whole page never goes into the prompt. A 200 KB page is tens of
/// thousands of tokens and a small local model's window is a fraction of
/// that; a page trimmed to fit loses whatever happened to sit at the end.
/// Instead the model starts from an outline and asks for the parts it needs,
/// a page at a time, and every result is capped so no single call can flood
/// the context.
library;

import 'dart:math' as math;

import 'package:html/dom.dart';

import '../agent/agent_runtime.dart';
import '../ai/ai_provider.dart';
import 'html_cleaner.dart';
import 'page_digest.dart';

/// State a task exposes so the page tools can serve it.
abstract interface class HasPage {
  PageInspector get page;
}

/// Numbers the elements of one page so the model can point at them, and
/// renders the views the tools return.
class PageInspector {
  final Document document;
  final Uri pageUrl;

  final List<Element> _nodes = [];
  final Map<Element, String> _ids = {};
  List<String>? _outline;
  List<String>? _images;

  PageInspector(this.document, this.pageUrl);

  static const outlinePageLines = 60;
  static const textPageChars = 2500;
  static const markupPageChars = 3000;
  static const imagesPerPage = 30;
  static const queryShown = 5;

  /// A signature appearing more often than this among one element's children
  /// is summarised: a product table of two thousand identical rows is one
  /// line of outline, not two thousand.
  static const _repeatLimit = 6;

  static const _skipped = {
    'script',
    'style',
    'svg',
    'noscript',
    'iframe',
    'template',
    'head',
    'link',
    'meta',
    'button',
    'input',
    'select',
    'textarea',
    'canvas',
    'video',
    'audio',
    'embed',
    'object',
  };

  static const _structural = {
    'main',
    'article',
    'section',
    'header',
    'footer',
    'nav',
    'aside',
    'table',
    'dl',
    'ul',
    'ol',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };

  /// A stable id for [element], minted the first time any view shows it.
  String idOf(Element element) => _ids.putIfAbsent(element, () {
    _nodes.add(element);
    return 'n${_nodes.length - 1}';
  });

  /// The element a model-supplied node id refers to; null means the body.
  Element elementFor(Object? node) {
    final raw = node?.toString().trim() ?? '';
    if (raw.isEmpty) {
      final body = document.body;
      if (body == null) throw const ToolError('This page has no body.');
      return body;
    }
    final index = int.tryParse(raw.startsWith('n') ? raw.substring(1) : raw);
    if (index == null || index < 0 || index >= _nodes.length) {
      throw ToolError(
        'There is no node "$raw". Use a node id such as n12, as shown by '
        'page_outline or query.',
      );
    }
    return _nodes[index];
  }

  /// Absolute image URLs on the page, in document order.
  List<String> get images =>
      _images ??= PageDigest.of(document, pageUrl).images;

  List<String> get outline => _outline ??= _buildOutline();

  String outlinePage(int page) {
    final lines = outline;
    if (lines.isEmpty) return 'The page has no visible structure.';
    final pages = (lines.length / outlinePageLines).ceil();
    if (page > pages) {
      throw ToolError('The outline has only $pages page(s).');
    }
    final start = (page - 1) * outlinePageLines;
    final end = math.min(lines.length, start + outlinePageLines);
    return [
      'Outline of $pageUrl — lines ${start + 1}-$end of ${lines.length}, '
          'page $page of $pages'
          '${page < pages ? ' (call page_outline with page=${page + 1} for more)' : ''}:',
      ...lines.sublist(start, end),
    ].join('\n');
  }

  String query(String selector) {
    final List<Element> matches;
    try {
      matches = document.querySelectorAll(selector);
    } catch (_) {
      throw ToolError(
        '"$selector" is not a selector this page can be queried with. Use '
        'plain CSS: tag names, #id, .class, [attribute], and descendant or '
        'child combinators.',
      );
    }
    if (matches.isEmpty) return 'No element matches "$selector".';
    final shown = matches.take(queryShown).toList();
    return [
      '${matches.length} element(s) match "$selector"'
          '${matches.length > shown.length ? '; the first ${shown.length}' : ''}:',
      for (final element in shown) describe(element, excerpt: 160),
    ].join('\n');
  }

  String markupPage(Object? node, int page) => _paged(
    label: 'Markup of ${node ?? 'the page'}',
    text: HtmlCleaner.clean(
      elementFor(node).outerHtml,
      maxChars: 1 << 30,
      narrowToMain: false,
    ),
    page: page,
    size: markupPageChars,
    tool: 'inspect',
  );

  String textPage(Object? node, int page) => _paged(
    label: 'Text of ${node ?? 'the page'}',
    text: _collapse(elementFor(node).text),
    page: page,
    size: textPageChars,
    tool: 'read_section',
  );

  String imagesPage(int page) {
    final all = images;
    if (all.isEmpty) return 'The page has no candidate images.';
    final pages = (all.length / imagesPerPage).ceil();
    if (page > pages) {
      throw ToolError('The image list has only $pages page(s).');
    }
    final start = (page - 1) * imagesPerPage;
    final end = math.min(all.length, start + imagesPerPage);
    return [
      'Images ${start + 1}-$end of ${all.length}'
          '${page < pages ? ' (call list_images with page=${page + 1} for more)' : ''}:',
      for (var i = start; i < end; i++) '${i + 1}. ${all[i]}',
    ].join('\n');
  }

  /// One line for [element]: id, tag signature, the attribute a recipe would
  /// read, text length and the start of its text.
  String describe(Element element, {int excerpt = 50}) {
    final text = _collapse(element.text);
    final attribute = switch (element.localName) {
      'img' => element.attributes['src'] ?? element.attributes['data-src'],
      'a' => element.attributes['href'],
      _ => null,
    };
    final shortText = text.length > excerpt
        ? '${text.substring(0, excerpt)}…'
        : text;
    return [
      '${idOf(element)} <${_signature(element)}>',
      if (attribute != null)
        '${element.localName == 'a' ? 'href' : 'src'}=$attribute',
      'text=${text.length}',
      if (shortText.isNotEmpty) '"$shortText"',
    ].join(' ');
  }

  List<String> _buildOutline() {
    final body = document.body;
    if (body == null) return const [];
    final lines = <String>[];

    void walk(Element parent, int depth) {
      final children = parent.children
          .where((child) => !_skipped.contains(child.localName))
          .toList();
      for (final group in _bySignature(children)) {
        final repeated = group.length > _repeatLimit;
        for (final child in repeated ? group.take(3) : group) {
          final listed = _worthListing(child);
          if (listed) {
            lines.add('${'  ' * math.min(depth, 12)}${describe(child)}');
          }
          walk(child, listed ? depth + 1 : depth);
        }
        if (repeated) {
          lines.add(
            '${'  ' * math.min(depth, 12)}… ${group.length - 3} more '
            '<${_signature(group.first)}>',
          );
        }
      }
    }

    walk(body, 0);
    return lines;
  }

  /// Children grouped by signature, in order of first appearance.
  static List<List<Element>> _bySignature(List<Element> children) {
    final groups = <String, List<Element>>{};
    for (final child in children) {
      groups.putIfAbsent(_signature(child), () => []).add(child);
    }
    return groups.values.toList();
  }

  static bool _worthListing(Element element) {
    if (element.localName == 'img') return true;
    if (_collapse(element.text).isEmpty) return false;
    return element.id.isNotEmpty ||
        element.classes.isNotEmpty ||
        _structural.contains(element.localName);
  }

  static String _signature(Element element) {
    final id = element.id.isEmpty ? '' : '#${element.id}';
    final classes = element.classes.take(2).map((c) => '.$c').join();
    return '${element.localName}$id$classes';
  }

  static String _paged({
    required String label,
    required String text,
    required int page,
    required int size,
    required String tool,
  }) {
    if (text.isEmpty) return '$label is empty.';
    final pages = (text.length / size).ceil();
    if (page > pages) throw ToolError('$label has only $pages page(s).');
    final start = (page - 1) * size;
    var end = math.min(text.length, start + size);
    // Never split a surrogate pair across two pages.
    if (end < text.length && _isHighSurrogate(text.codeUnitAt(end - 1))) end--;
    return '$label — characters ${start + 1}-$end of ${text.length}, '
        'page $page of $pages'
        '${page < pages ? ' (call $tool with page=${page + 1} for more)' : ''}:\n'
        '${text.substring(start, end)}';
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static String _collapse(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _pageParameter = {
  'type': 'integer',
  'description': 'Page number, starting at 1.',
};

const _nodeParameter = {
  'type': 'string',
  'description': 'A node id such as n12, from page_outline or query.',
};

class PageOutlineTool<C extends HasPage> extends AgentTool<C> {
  const PageOutlineTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'page_outline',
    description:
        'Shows the structure of the page: one line per notable element, with '
        'its node id, tag, id and classes, text length and the start of its '
        'text. Repeated elements are summarised. Paged.',
    parameters: {
      'type': 'object',
      'properties': {'page': _pageParameter},
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, C context) =>
      context.page.outlinePage(pageArgument(arguments['page']));
}

class QueryTool<C extends HasPage> extends AgentTool<C> {
  const QueryTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'query',
    description:
        'Runs a CSS selector against the page and reports how many elements '
        'match, with the first few.',
    parameters: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'A CSS selector.'},
      },
      'required': ['selector'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, C context) {
    final selector = arguments['selector'];
    if (selector is! String || selector.trim().isEmpty) {
      throw const ToolError('Pass the CSS selector to try as "selector".');
    }
    return context.page.query(selector.trim());
  }
}

class InspectTool<C extends HasPage> extends AgentTool<C> {
  const InspectTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'inspect',
    description:
        'Shows the HTML markup of one node with scripts, styling and most '
        'attributes removed and long text shortened, a page at a time. Use it '
        'to read the ids, classes and labels a selector can target.',
    parameters: {
      'type': 'object',
      'properties': {'node': _nodeParameter, 'page': _pageParameter},
      'required': ['node'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, C context) => context.page
      .markupPage(arguments['node'], pageArgument(arguments['page']));
}

class ReadSectionTool<C extends HasPage> extends AgentTool<C> {
  const ReadSectionTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'read_section',
    description:
        'Returns the visible text of one node, or of the whole page when no '
        'node is given, a page at a time.',
    parameters: {
      'type': 'object',
      'properties': {'node': _nodeParameter, 'page': _pageParameter},
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, C context) =>
      context.page.textPage(arguments['node'], pageArgument(arguments['page']));
}

class ListImagesTool<C extends HasPage> extends AgentTool<C> {
  const ListImagesTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'list_images',
    description:
        'Lists the page\'s candidate images, numbered. Refer to an image by '
        'its number.',
    parameters: {
      'type': 'object',
      'properties': {'page': _pageParameter},
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, C context) =>
      context.page.imagesPage(pageArgument(arguments['page']));
}
