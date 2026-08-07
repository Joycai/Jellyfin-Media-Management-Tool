import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/scrape/html_decoding.dart';

void main() {
  group('charset detection', () {
    test('prefers the Content-Type header', () {
      expect(
        HtmlDecoding.charsetFromContentType('text/html; charset=UTF-8'),
        'utf-8',
      );
      expect(
        HtmlDecoding.charsetFromContentType('text/html;charset="Shift_JIS"'),
        'shift_jis',
      );
      expect(HtmlDecoding.charsetFromContentType('text/html'), isNull);
      expect(HtmlDecoding.charsetFromContentType(null), isNull);
    });

    test('falls back to the meta tag, in both HTML5 and legacy spellings', () {
      expect(
        HtmlDecoding.charsetFromMeta(utf8.encode('<meta charset="utf-8">')),
        'utf-8',
      );
      expect(
        HtmlDecoding.charsetFromMeta(
          utf8.encode(
            '<meta http-equiv="Content-Type" content="text/html; charset=EUC-JP">',
          ),
        ),
        'euc-jp',
      );
    });

    test('sniffs the meta tag out of non-ASCII bytes without choking', () {
      // The declaration has to be readable before we know the encoding, which
      // is why the prefix is read as latin1.
      final bytes = [
        ...utf8.encode('<html><head><meta charset="utf-8"><title>'),
        0xE7, 0x89, 0xB9, // 特
        ...utf8.encode('</title></head>'),
      ];
      expect(HtmlDecoding.charsetFromMeta(bytes), 'utf-8');
    });
  });

  group('decode', () {
    test('defaults to UTF-8 when nothing declares a charset', () {
      // This is the bug being defended against: http.Response.body would fall
      // back to latin1 here and render every Japanese page as mojibake.
      final decoded = HtmlDecoding.decode(utf8.encode('<p>特撮ヒロイン</p>'));
      expect(decoded.html, contains('特撮ヒロイン'));
      expect(decoded.charset, 'utf-8');
      expect(decoded.degraded, isFalse);
    });

    test('honours a declared latin1 charset', () {
      final decoded = HtmlDecoding.decode(
        latin1.encode('café'),
        contentType: 'text/html; charset=iso-8859-1',
      );
      expect(decoded.html, 'café');
    });

    test('strips a UTF-8 BOM', () {
      final decoded = HtmlDecoding.decode([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('<html>'),
      ]);
      expect(decoded.html, '<html>');
    });

    test('flags an unsupported charset instead of pretending it worked', () {
      final decoded = HtmlDecoding.decode(
        utf8.encode('<p>x</p>'),
        contentType: 'text/html; charset=shift_jis',
      );
      expect(decoded.charset, 'shift_jis');
      expect(decoded.degraded, isTrue);
      // ASCII markup still survives, so selectors keep working.
      expect(decoded.html, contains('<p>'));
    });

    test('uses a registered codec when one is available', () {
      addTearDown(() => HtmlDecoding.codecs.remove('x-test'));
      HtmlDecoding.codecs['x-test'] = (bytes) => 'decoded-by-plugin';

      final decoded = HtmlDecoding.decode([
        1,
        2,
        3,
      ], contentType: 'text/html; charset=x-test');
      expect(decoded.html, 'decoded-by-plugin');
      expect(decoded.degraded, isFalse);
    });

    test('malformed UTF-8 degrades to replacement characters, not a throw', () {
      final decoded = HtmlDecoding.decode([0xC3, 0x28, 0x41]);
      expect(decoded.html, endsWith('A'));
    });
  });
}
