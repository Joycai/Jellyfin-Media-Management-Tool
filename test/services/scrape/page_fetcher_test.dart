import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/models/scrape_recipe.dart';
import 'package:jellyfin_media_management_tool/services/scrape/cookie_store.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_fetcher.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';

const _page = '<html><body><h1>the real page</h1></body></html>';

http.Response _html(String body, {int status = 200}) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

http.Response _redirect(String location) =>
    http.Response('', 302, headers: {'location': location});

/// A site behind a session-based age gate, modelled on the real one: the flag
/// cookie alone is not enough, the session has to have been through the gate,
/// and product pages additionally demand a same-origin Referer.
class _GatedSite {
  final List<http.Request> requests = [];
  final Set<String> verified = {};
  int gateHits = 0;
  var counter = 0;

  /// When true the gate must also be re-passed after the first product hit,
  /// standing in for a session that expires mid-run.
  bool expireAfterFirstPage = false;
  var _pagesServed = 0;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    final sid = _sessionIdOf(request);

    if (request.url.path == '/cookie_set.php') {
      gateHits++;
      final fresh = 'sid${++counter}';
      verified.add(fresh);
      return http.Response(
        '',
        302,
        headers: {
          'location': '/top.php',
          // Folded exactly the way `http` folds repeated Set-Cookie headers,
          // Expires comma and all.
          'set-cookie':
              'PHPSESSID=$fresh; path=/; secure, '
              'old_check=yes; expires=Thu, 01 Jan 2032 00:00:00 GMT; path=/',
        },
      );
    }
    if (request.url.path == '/top.php') return _html('<html>top</html>');

    // A product page: needs a verified session AND a same-origin referer.
    final referer = request.headers['Referer'] ?? request.headers['referer'];
    final sameOrigin =
        referer != null && referer.startsWith('https://gate.test');
    if (sid == null || !verified.contains(sid) || !sameOrigin) {
      return _redirect('/top.php');
    }
    if (expireAfterFirstPage && _pagesServed++ == 0) {
      verified.remove(sid);
    }
    return _html(_page);
  });

  String? _sessionIdOf(http.Request request) {
    for (final pair in (request.headers['Cookie'] ?? '').split(';')) {
      final eq = pair.indexOf('=');
      if (eq > 0 && pair.substring(0, eq).trim() == 'PHPSESSID') {
        return pair.substring(eq + 1).trim();
      }
    }
    return null;
  }
}

ScrapeRecipe _recipe({
  String? sessionUrl = '/cookie_set.php',
  String? referer,
  String cookies = 'old_check=yes',
}) => ScrapeRecipe(
  domain: 'gate.test',
  pathPattern: '/product/*',
  cookies: cookies,
  sessionUrl: sessionUrl,
  referer: referer,
  minIntervalMs: 0,
);

final _product = Uri.parse('https://gate.test/product/index.php?id=1');

void main() {
  group('session bootstrap', () {
    test('walks the gate, then reuses the session it was given', () async {
      // The whole point: a static `old_check=yes` is not a session. The gate
      // has to be walked so the server has something to mark as verified.
      final site = _GatedSite();
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);

      final page = await fetcher.fetch(_product, recipe: _recipe());

      expect(page.html, contains('the real page'));
      expect(page.wasRedirected, isFalse);
      expect(site.gateHits, 1);
      expect(fetcher.sessionCookiesFor('gate.test')['PHPSESSID'], 'sid1');
    });

    test('runs once per host, not once per page', () async {
      final site = _GatedSite();
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);

      await fetcher.fetch(_product, recipe: _recipe());
      await fetcher.fetch(
        Uri.parse('https://gate.test/product/index.php?id=2'),
        recipe: _recipe(),
      );

      expect(site.gateHits, 1);
    });

    test('a session that expires mid-run is re-established once', () async {
      final site = _GatedSite()..expireAfterFirstPage = true;
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);

      await fetcher.fetch(_product, recipe: _recipe());
      final second = await fetcher.fetch(
        Uri.parse('https://gate.test/product/index.php?id=2'),
        recipe: _recipe(),
      );

      expect(second.html, contains('the real page'));
      expect(site.gateHits, 2);
    });

    test('without the bootstrap the site just bounces us', () async {
      // Documents the failure this whole mechanism exists to fix: a 200, a
      // parseable page, and none of the requested title in it.
      final site = _GatedSite();
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);

      final page = await fetcher.fetch(
        _product,
        recipe: _recipe(sessionUrl: null),
      );

      expect(page.statusCode, 200);
      expect(page.html, isNot(contains('the real page')));
      expect(page.wasRedirected, isTrue);
      expect(page.url.path, '/top.php');
      expect(page.requestedUrl, _product);
    });

    test('a recipe cannot aim the gate at another host', () async {
      // Recipes are user-editable data, and one that could bootstrap against
      // evil.test would hand it the cookies we hold for this host.
      final site = _GatedSite();
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);

      await fetcher.fetch(
        _product,
        recipe: _recipe(sessionUrl: 'https://evil.test/steal'),
      );

      expect(
        site.requests.map((r) => r.url.host).toSet(),
        everyElement('gate.test'),
      );
    });
  });

  group('cookies', () {
    test('a folded Set-Cookie with an Expires comma is one cookie', () async {
      final site = _GatedSite();
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);

      await fetcher.fetch(_product, recipe: _recipe());

      final jar = fetcher.sessionCookiesFor('gate.test');
      expect(jar.keys, containsAll(['PHPSESSID', 'old_check']));
      // The date inside `expires=` must not have been read as a second cookie.
      expect(jar['old_check'], 'yes');
      expect(jar.length, 2);
    });

    test('an imported browser cookie outranks one we minted', () {
      final store = CookieStore(
        CookieStore.parseNetscape(
          'gate.test\tFALSE\t/\tFALSE\t0\tPHPSESSID\tmine',
        ),
      );

      final header = store.headerFor(
        Uri.parse('https://gate.test/x'),
        staticCookies: 'PHPSESSID=static; layout=jpn',
        sessionCookies: {'PHPSESSID': 'ours'},
      );

      expect(header, contains('PHPSESSID=mine'));
      expect(header, contains('layout=jpn'));
    });

    test('a session cookie beats the recipe constant', () {
      final header = CookieStore().headerFor(
        Uri.parse('https://gate.test/x'),
        staticCookies: 'PHPSESSID=static',
        sessionCookies: {'PHPSESSID': 'ours'},
      );

      expect(header, contains('PHPSESSID=ours'));
    });
  });

  group('referer', () {
    Future<String?> refererSent({String? recipeReferer}) async {
      final site = _GatedSite();
      final fetcher = PageFetcher(client: site.client, minIntervalMs: 0);
      await fetcher.fetch(
        _product,
        recipe: _recipe(referer: recipeReferer, sessionUrl: null),
      );
      return site.requests.first.headers['Referer'];
    }

    test('defaults to the site root', () async {
      expect(await refererSent(), 'https://gate.test/');
    });

    test('a recipe can point it somewhere else', () async {
      expect(
        await refererSent(recipeReferer: '/top.php'),
        'https://gate.test/top.php',
      );
    });

    test('an empty recipe value opts out entirely', () async {
      expect(await refererSent(recipeReferer: ''), isNull);
    });
  });

  group('redirects', () {
    test('reports where it landed, not where it was sent', () async {
      // `http` names the original request on a followed response, so following
      // redirects ourselves is the only way to resolve relative links against
      // the page they actually came from.
      final client = MockClient((request) async {
        if (request.url.path == '/a') return _redirect('/b/c');
        return _html(_page);
      });
      final fetcher = PageFetcher(client: client, minIntervalMs: 0);

      final page = await fetcher.fetch(Uri.parse('https://x.test/a'));

      expect(page.url.path, '/b/c');
      expect(page.requestedUrl.path, '/a');
      expect(page.wasRedirected, isTrue);
      expect(page.html, contains('the real page'));
    });

    test('a redirect loop gives up rather than spinning', () async {
      final client = MockClient((request) async => _redirect('/loop'));
      final fetcher = PageFetcher(client: client, minIntervalMs: 0);

      await expectLater(
        fetcher.fetch(Uri.parse('https://x.test/loop')),
        throwsA(
          isA<PageFetchException>().having(
            (e) => e.message,
            'message',
            contains('Too many redirects'),
          ),
        ),
      );
    });

    test('an error status is still an error', () async {
      final client = MockClient((request) async => _html('nope', status: 404));
      final fetcher = PageFetcher(client: client, minIntervalMs: 0);

      await expectLater(
        fetcher.fetch(Uri.parse('https://x.test/gone')),
        throwsA(
          isA<PageFetchException>().having((e) => e.statusCode, 'code', 404),
        ),
      );
    });
  });

  group('ScrapeService', () {
    test('a bounce is reported instead of passed off as a result', () async {
      // Without this the user gets an empty result and no idea why: the page
      // parsed fine, it was simply the wrong page.
      // No recipe matches gate.test, so nothing bootstraps the session and the
      // site does what it does to any unverified visitor.
      final site = _GatedSite();
      final service = ScrapeService(
        fetcher: PageFetcher(client: site.client, minIntervalMs: 0),
      );

      final result = await service.scrapeUrl(_product.toString());

      expect(result.notes, contains(ScrapeNote.redirectedAway));
    });
  });
}
