import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/scrape/html_cleaner.dart';

final _fixture = io.File(
  'test/fixtures/giga_product_7743.html',
).readAsStringSync();

void main() {
  group('HtmlCleaner.clean', () {
    test('drops scripts, styles and comments', () {
      final out = HtmlCleaner.clean('''
<html><body>
  <script>var a = 1;</script>
  <style>.x { color: red }</style>
  <!-- a comment -->
  <div id="keep">hello</div>
</body></html>
''');

      expect(out, contains('id="keep"'));
      expect(out, isNot(contains('var a')));
      expect(out, isNot(contains('color: red')));
      expect(out, isNot(contains('a comment')));
    });

    test('keeps only the attributes a selector can be built from', () {
      final out = HtmlCleaner.clean(
        '<html><body><a id="i" class="c" href="/x" '
        'onclick="boom()" style="color:red" data-track="1">t</a></body></html>',
      );

      expect(out, contains('id="i"'));
      expect(out, contains('class="c"'));
      expect(out, contains('href="/x"'));
      expect(out, isNot(contains('onclick')));
      expect(out, isNot(contains('style=')));
      expect(out, isNot(contains('data-track')));
    });

    test('keeps data-src, where lazy-loaded images hide the real URL', () {
      final out = HtmlCleaner.clean(
        '<html><body><img src="blank.gif" data-src="/real.jpg"></body></html>',
      );

      expect(out, contains('data-src="/real.jpg"'));
    });

    test('truncates long text but leaves short labels intact', () {
      final out = HtmlCleaner.clean(
        '<html><body><dl><dt>作品番号</dt>'
        '<dd>${'x' * 500}</dd></dl></body></html>',
        maxTextLength: 20,
      );

      // Labels are what a keyValue rule matches on, so they must survive whole.
      expect(out, contains('作品番号'));
      expect(out, contains('…'));
      expect(out, isNot(contains('x' * 21)));
    });

    test('narrows to the main region when one holds most of the text', () {
      final out = HtmlCleaner.clean('''
<html><body>
  <nav id="nav">menu</nav>
  <main><p id="body">${'content ' * 50}</p></main>
</body></html>
''');

      expect(out, contains('id="body"'));
      expect(out, isNot(contains('id="nav"')));
    });

    test('keeps the whole body when no candidate is convincing', () {
      final out = HtmlCleaner.clean('''
<html><body>
  <div id="sidebar">${'filler ' * 100}</div>
  <main><p id="tiny">x</p></main>
</body></html>
''');

      // A <main> holding 1% of the text is decorative; trusting it would throw
      // away the part we came for.
      expect(out, contains('id="sidebar"'));
      expect(out, contains('id="tiny"'));
    });

    test('respects the hard character ceiling', () {
      final out = HtmlCleaner.clean(
        '<html><body>${'<div class="c">t</div>' * 5000}</body></html>',
        maxChars: 1000,
      );

      expect(out.length, lessThan(1100));
      expect(out, contains('truncated'));
    });

    test('shrinks a real page substantially and keeps its anchors', () {
      final out = HtmlCleaner.clean(_fixture);

      expect(out.length, lessThan(_fixture.length));
      // The ids the built-in GIGA recipe targets must survive, or the model
      // could never rediscover them.
      expect(out, contains('works_txt'));
      expect(out, contains('story_list2'));
    });

    test('does not mutate the caller\'s copy of the HTML', () {
      final before = _fixture;
      HtmlCleaner.clean(_fixture);
      expect(_fixture, before);
    });
  });
}
