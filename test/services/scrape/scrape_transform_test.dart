import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_transform.dart';

void main() {
  group('date', () {
    test('normalizes the formats product pages actually use', () {
      for (final input in [
        '2026/08/14',
        '2026-08-14',
        '2026.08.14',
        '2026年8月14日',
        'DVDリリース日 2026/8/14',
      ]) {
        expect(
          ScrapeTransform.apply(input, 'date'),
          '2026-08-14',
          reason: input,
        );
      }
    });

    test('refuses to read a product code as a date', () {
      // Anchoring on a four-digit year is what stops "SPSF-43" or "1080p"
      // from being turned into a release date.
      expect(ScrapeTransform.apply('SPSF-43', 'date'), isNull);
      expect(ScrapeTransform.apply('1080p HD', 'date'), isNull);
    });

    test('rejects an impossible month or day', () {
      expect(ScrapeTransform.apply('2026/13/01', 'date'), isNull);
      expect(ScrapeTransform.apply('2026/01/45', 'date'), isNull);
    });
  });

  group('numbers', () {
    test('int and double pull the number out of surrounding text', () {
      expect(ScrapeTransform.apply('11000円（税込）', 'int'), 11000);
      expect(ScrapeTransform.apply('3.50', 'double'), 3.5);
      expect(ScrapeTransform.apply('本編85分', 'int'), 85);
    });

    test('take the FIRST number, so aim the selector at the value', () {
      // Documents the sharp edge: '(out of 5) 3.50' would give 5, not 3.5.
      // Fields where the number is embedded in prose need a regex transform.
      expect(ScrapeTransform.apply('（5点満点中 3.50', 'double'), 5.0);
      expect(
        ScrapeTransform.apply('（5点満点中 3.50', r'regex:中\s*([\d.]+)'),
        '3.50',
      );
    });

    test('return null when there is no number', () {
      expect(ScrapeTransform.apply('なし', 'int'), isNull);
      expect(ScrapeTransform.apply('なし', 'double'), isNull);
    });
  });

  group('regex', () {
    test('regexInt captures the feature runtime, ignoring the extras', () {
      expect(
        ScrapeTransform.apply('本編85分 メイキング5分', r'regexInt:本編\s*(\d+)\s*分'),
        85,
      );
    });

    test('regex returns the first capture group', () {
      expect(ScrapeTransform.apply('SPSF-43', r'regex:^([A-Za-z]+)'), 'SPSF');
    });

    test('no match yields null rather than the whole string', () {
      expect(ScrapeTransform.apply('43', r'regex:^([A-Za-z]+)'), isNull);
    });

    test('an invalid pattern is null, not an exception', () {
      expect(ScrapeTransform.apply('anything', r'regex:(['), isNull);
    });
  });

  group('degradation', () {
    test('absent or unknown transforms pass the text through', () {
      // A typo in a hand-edited recipe should cost the transform, not the
      // field.
      expect(ScrapeTransform.apply(' spaced ', null), 'spaced');
      expect(ScrapeTransform.apply('x', 'text'), 'x');
      expect(ScrapeTransform.apply('x', 'nosuchtransform'), 'x');
    });

    test('empty input is always null', () {
      expect(ScrapeTransform.apply('   ', 'text'), isNull);
      expect(ScrapeTransform.apply('', 'date'), isNull);
    });
  });
}
