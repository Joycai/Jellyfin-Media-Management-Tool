import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/services/agent/agent_runtime.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_tools.dart';

final _fixture = io.File(
  'test/fixtures/giga_product_7743.html',
).readAsStringSync();

final _pageUrl = Uri.parse(
  'https://www.giga-web.jp/product/index.php?product_id=7743',
);

PageInspector _inspector([String? html]) =>
    PageInspector(html_parser.parse(html ?? _fixture), _pageUrl);

void main() {
  test('the outline names notable elements with ids a tool can use', () {
    final page = _inspector();

    final outline = page.outlinePage(1);

    expect(outline, startsWith('Outline of $_pageUrl'));
    final firstNode = RegExp(r'\bn(\d+) <').firstMatch(outline)!;
    expect(() => page.elementFor('n${firstNode.group(1)}'), returnsNormally);
  });

  test('a table of identical rows is summarised, not listed', () {
    final page = _inspector(
      '<html><body><div id="list">'
      '${'<div class="row">entry</div>' * 500}'
      '</div></body></html>',
    );

    expect(page.outline, hasLength(lessThan(10)));
    expect(page.outline.join('\n'), contains('… 497 more <div.row>'));
  });

  test('outline pages are capped and say how to get the next', () {
    final page = _inspector(
      '<html><body>'
      '${List.generate(150, (i) => '<p class="c$i">paragraph $i</p>').join()}'
      '</body></html>',
    );

    final first = page.outlinePage(1);
    expect(first.split('\n').length, PageInspector.outlinePageLines + 1);
    expect(first, contains('page=2'));
    expect(() => page.outlinePage(9), throwsA(isA<ToolError>()));
  });

  test('query reports matches with ids, and rejects a broken selector', () {
    final page = _inspector();

    final result = page.query('#story_list2');

    expect(result, contains('match "#story_list2"'));
    expect(result, contains(RegExp(r'n\d+ <')));
    expect(page.query('#no-such-element'), startsWith('No element matches'));
    expect(() => page.query('div[[['), throwsA(isA<ToolError>()));
  });

  test('text is read a page at a time', () {
    final page = _inspector(
      '<html><body><p class="plot">${'あらすじ。' * 2000}</p></body></html>',
    );

    final text = page.textPage(null, 1);

    expect(text, contains('page 1 of'));
    expect(text.length, lessThan(PageInspector.textPageChars + 200));
    expect(text, contains('call read_section with page=2'));
  });

  test('markup drops scripts and keeps the selector-worthy attributes', () {
    final page = _inspector(
      '<html><body><div id="box" class="product" style="color:red">'
      '<script>var x = 1;</script><span class="code">SPSF-43</span>'
      '</div></body></html>',
    );
    page.query('#box');

    final markup = page.markupPage('n0', 1);

    expect(markup, contains('id="box"'));
    expect(markup, contains('class="code"'));
    expect(markup, isNot(contains('script')));
    expect(markup, isNot(contains('style=')));
  });

  test('an unknown node id is refused with how to get a valid one', () {
    expect(
      () => _inspector().elementFor('n9999'),
      throwsA(
        isA<ToolError>().having(
          (e) => e.message,
          'message',
          contains('page_outline or query'),
        ),
      ),
    );
  });

  test('images are numbered from one', () {
    final page = _inspector(
      '<html><body><img src="/a.jpg"><img src="/b.png"></body></html>',
    );

    expect(page.imagesPage(1), contains('1. https://www.giga-web.jp/a.jpg'));
    expect(page.imagesPage(1), contains('2. https://www.giga-web.jp/b.png'));
  });
}
