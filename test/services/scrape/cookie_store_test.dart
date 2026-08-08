import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/scrape/cookie_store.dart';

/// A real export, as produced by a browser cookie-exporting extension.
/// `old_check` is the age gate; note its expiry of `0` (a session cookie) and
/// the mix of leading-dot and plain domains.
const _cookiesTxt = '''
# Netscape HTTP Cookie File
# http://curl.haxx.se/rfc/cookie_spec.html
# This is a generated file!  Do not edit.

www.giga-web.jp\tFALSE\t/\tTRUE\t0\tPHPSESSID\trscija2o0rfmq6495v88chgmpj
www.giga-web.jp\tFALSE\t/\tFALSE\t0\tWSLB\twww2
www.giga-web.jp\tFALSE\t/\tTRUE\t0\told_check\tyes
www.giga-web.jp\tFALSE\t/\tTRUE\t0\tlayout\tjpn
.giga-web.jp\tTRUE\t/\tFALSE\t1820665862\t_ga\tGA1.1.500114938.1786105763
.www.giga-web.jp\tTRUE\t/\tFALSE\t1788697862\tgiga_footstamp\t7743
''';

final _url = Uri.parse(
  'https://www.giga-web.jp/product/index.php?product_id=7743',
);
final _now = DateTime.utc(2026, 8, 7);

void main() {
  group('parseNetscape', () {
    test('parses every cookie line and skips comments and blanks', () {
      final cookies = CookieStore.parseNetscape(_cookiesTxt);
      expect(cookies.map((c) => c.name), [
        'PHPSESSID',
        'WSLB',
        'old_check',
        'layout',
        '_ga',
        'giga_footstamp',
      ]);
    });

    test('reads the age-gate flag as a non-expiring session cookie', () {
      final ageGate = CookieStore.parseNetscape(
        _cookiesTxt,
      ).firstWhere((c) => c.name == 'old_check');
      expect(ageGate.value, 'yes');
      expect(ageGate.expiresAt, 0);
      expect(ageGate.isExpired(DateTime.utc(2099)), isFalse);
      expect(ageGate.secureOnly, isTrue);
    });

    test('strips the leading dot and treats it as includeSubdomains', () {
      final ga = CookieStore.parseNetscape(
        _cookiesTxt,
      ).firstWhere((c) => c.name == '_ga');
      expect(ga.domain, 'giga-web.jp');
      expect(ga.includeSubdomains, isTrue);
    });

    test('honours the #HttpOnly_ prefix', () {
      final cookies = CookieStore.parseNetscape(
        '#HttpOnly_example.com\tFALSE\t/\tFALSE\t0\tsession\tabc',
      );
      expect(cookies, hasLength(1));
      expect(cookies.single.domain, 'example.com');
      expect(cookies.single.name, 'session');
    });

    test('keeps values containing "=" intact', () {
      final c = CookieStore.parseNetscape(
        'example.com\tFALSE\t/\tFALSE\t0\ttoken\ta=b=c',
      ).single;
      expect(c.value, 'a=b=c');
    });

    test('skips short and empty rows instead of throwing', () {
      expect(CookieStore.parseNetscape('a\tb\tc\n\n   \n'), isEmpty);
    });
  });

  group('matching', () {
    test('an expired cookie is not sent', () {
      final expired = CookieStore.parseNetscape(
        'example.com\tFALSE\t/\tFALSE\t1000000000\told\tv',
      ).single;
      expect(
        expired.matches(Uri.parse('https://example.com/'), now: _now),
        isFalse,
      );
    });

    test('a secure cookie is withheld over plain http', () {
      final store = CookieStore(CookieStore.parseNetscape(_cookiesTxt));
      final overHttp = store.headerFor(
        Uri.parse('http://www.giga-web.jp/product/index.php'),
        now: _now,
      );
      expect(overHttp, isNot(contains('old_check')));
      expect(overHttp, contains('WSLB=www2'));
    });

    test('a host-only cookie is not sent to a sibling host', () {
      final store = CookieStore(CookieStore.parseNetscape(_cookiesTxt));
      final other = store.headerFor(
        Uri.parse('https://shop.giga-web.jp/'),
        now: _now,
      );
      expect(other, isNot(contains('old_check'))); // host-only
      expect(other, contains('_ga=')); // includeSubdomains
    });

    test('path scoping', () {
      final scoped = CookieStore.parseNetscape(
        'example.com\tFALSE\t/deep\tFALSE\t0\tk\tv',
      ).single;
      expect(
        scoped.matches(Uri.parse('https://example.com/deep'), now: _now),
        isTrue,
      );
      expect(
        scoped.matches(Uri.parse('https://example.com/deep/page'), now: _now),
        isTrue,
      );
      expect(
        scoped.matches(Uri.parse('https://example.com/other'), now: _now),
        isFalse,
      );
      // /deeper must not match /deep — prefix matching has to be path-aware.
      expect(
        scoped.matches(Uri.parse('https://example.com/deeper'), now: _now),
        isFalse,
      );
    });
  });

  group('headerFor', () {
    test('a recipe cookie alone is enough for the age gate', () {
      // The whole point of tier 1: no import, no login, no session.
      final header = CookieStore().headerFor(
        _url,
        staticCookies: 'old_check=yes; layout=jpn',
        now: _now,
      );
      expect(header, 'old_check=yes; layout=jpn');
    });

    test('an imported cookie beats the recipe default for the same name', () {
      final store = CookieStore(
        CookieStore.parseNetscape(
          'www.giga-web.jp\tFALSE\t/\tFALSE\t0\tlayout\teng',
        ),
      );
      final header = store.headerFor(
        _url,
        staticCookies: 'old_check=yes; layout=jpn',
        now: _now,
      );
      expect(header, contains('layout=eng'));
      expect(header, isNot(contains('layout=jpn')));
      expect(header, contains('old_check=yes'));
    });

    test('is empty when there is nothing to send', () {
      expect(CookieStore().headerFor(_url, now: _now), isEmpty);
    });
  });

  group('store management', () {
    test('re-importing replaces that domain rather than duplicating it', () {
      final store = CookieStore(CookieStore.parseNetscape(_cookiesTxt));
      final before = store.cookies.length;
      store.importAll(
        CookieStore.parseNetscape(
          'www.giga-web.jp\tFALSE\t/\tFALSE\t0\told_check\tyes',
        ),
      );
      expect(store.cookies.length, lessThan(before));
      expect(
        store.cookies.where((c) => c.domain == 'www.giga-web.jp'),
        hasLength(1),
      );
      // The wildcard-domain cookies are a different domain and survive.
      expect(store.cookies.any((c) => c.domain == 'giga-web.jp'), isTrue);
    });

    test('round-trips through the Netscape format', () {
      final original = CookieStore.parseNetscape(_cookiesTxt);
      final reparsed = CookieStore.parseNetscape(
        CookieStore.toNetscape(original),
      );
      expect(
        reparsed.map((c) => '${c.domain}|${c.name}|${c.value}'),
        original.map((c) => '${c.domain}|${c.name}|${c.value}'),
      );
    });

    test('clearDomain removes a host regardless of leading dot', () {
      final store = CookieStore(CookieStore.parseNetscape(_cookiesTxt));
      store.clearDomain('.www.giga-web.jp');
      expect(store.cookies.any((c) => c.domain == 'www.giga-web.jp'), isFalse);
    });
  });
}
