/// The one place that talks to a scraped site.
///
/// Everything awkward about fetching a third-party page lives here so the rest
/// of the pipeline can assume it is handed a correctly decoded string:
///
/// * **encoding** — see [HtmlDecoding]; `http`'s default of latin1 mangles
///   Japanese pages;
/// * **cookies** — three sources, in order: a recipe's static flag
///   (`old_check=yes`), a session this fetcher established by walking the
///   site's own age gate, and a user-imported `cookies.txt`;
/// * **sessions** — a static flag is often *not* enough. Sites increasingly
///   record "this visitor confirmed their age" against the session rather than
///   in the cookie, so a recipe can name a `sessionUrl` to walk first;
/// * **redirects** — followed here rather than by `http`, because a followed
///   response drops the `Set-Cookie` headers sent along the way and reports
///   the original URL as its own. Following them ourselves keeps the cookies,
///   resolves relative links against the page we actually landed on, and makes
///   a silent bounce to a gate distinguishable from a real page;
/// * **headers** — the default Dart user agent gets refused by some sites;
///   image CDNs check `Referer` against the page the image was linked from,
///   and some sites check it on the page request too;
/// * **rate limiting** — one request at a time per host, with a floor between
///   them. Scraping a library of 300 titles should not look like an attack.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../models/scrape_recipe.dart';
import '../ai/ai_cancel_token.dart';
import 'cookie_store.dart';
import 'html_decoding.dart';

/// A page that was fetched and decoded.
class FetchedPage {
  /// The URL after redirects — this is what relative links resolve against.
  ///
  /// [PageFetcher] follows redirects itself to populate this honestly: the
  /// `http` package reports the *original* request on a followed response, so
  /// asking it would name the URL we asked for, not the one we landed on.
  final Uri url;

  /// The URL originally requested. Differs from [url] exactly when the site
  /// redirected us, which is how a silent bounce to a gate or a home page is
  /// told apart from a real page.
  final Uri requestedUrl;

  final String html;
  final int statusCode;
  final String charset;

  /// True when the charset had no codec available; the text may be lossy.
  final bool degraded;

  const FetchedPage({
    required this.url,
    Uri? requestedUrl,
    required this.html,
    required this.statusCode,
    required this.charset,
    this.degraded = false,
  }) : requestedUrl = requestedUrl ?? url;

  /// True when the server sent us somewhere else. A product page that answers
  /// with the site's front page is a failure wearing a 200.
  bool get wasRedirected => url.path != requestedUrl.path;
}

/// A fetch that failed in a way worth showing the user.
class PageFetchException implements Exception {
  final String message;
  final int? statusCode;

  const PageFetchException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class PageFetcher {
  /// A desktop-browser UA. Sites that reject the default `Dart/3.x` agent are
  /// common enough that not sending this is a bug, not a nicety.
  static const defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  static const _timeout = Duration(seconds: 30);

  /// Refuse anything larger than this; a product page is tens of KB and a
  /// multi-megabyte response means we asked for the wrong thing.
  static const maxPageBytes = 8 * 1024 * 1024;

  final http.Client _client;
  final CookieStore cookies;

  /// Overrides every recipe's [ScrapeRecipe.minIntervalMs] when set. Exists so
  /// the politeness floor can be raised globally, and so tests can drop it to
  /// zero instead of sleeping through it.
  final int? minIntervalMs;

  /// Redirect hops to follow before giving up. Matches `http`'s own default.
  static const maxRedirects = 5;

  /// Cookies the *server* gave us during this run, per host.
  ///
  /// Deliberately separate from [cookies] and never written to disk. The
  /// CookieStore's contract is that importing a browser session is the user's
  /// explicit, informed decision; a session we minted ourselves by walking
  /// through an age gate is ours to hold in memory and drop on exit.
  final Map<String, Map<String, String>> _session = {};

  /// Hosts whose session bootstrap has run, successfully or not. A site that
  /// fails to hand out a session must not be re-asked on every page.
  final Set<String> _bootstrapped = {};

  /// Last request time per host, for [_throttle].
  final Map<String, DateTime> _lastRequestAt = {};

  /// Serializes requests per host so the interval cannot be undercut by two
  /// concurrent scrapes of the same site.
  final Map<String, Future<void>> _hostQueue = {};

  PageFetcher({
    http.Client? client,
    CookieStore? cookieStore,
    this.minIntervalMs,
  }) : _client = client ?? http.Client(),
       cookies = cookieStore ?? CookieStore();

  int _intervalFor(ScrapeRecipe? recipe) =>
      minIntervalMs ?? recipe?.minIntervalMs ?? 800;

  /// Fetches and decodes [url].
  ///
  /// When [cancelToken] is given the request is issued on the token's own
  /// client, so cancelling closes the socket immediately — the same mechanism
  /// the AI calls use. A socket closed underneath us surfaces as a generic
  /// `ClientException`, which is re-mapped to [AiCancelled].
  Future<FetchedPage> fetch(
    Uri url, {
    ScrapeRecipe? recipe,
    AiCancelToken? cancelToken,
  }) async {
    await _ensureSession(url, recipe, cancelToken);
    var page = await _fetchOnce(url, recipe, cancelToken);

    // A session that expired mid-run looks exactly like never having had one:
    // the site bounces us to its front page. Re-run the gate once and retry
    // before reporting a failure the user can do nothing about.
    if (page.wasRedirected && (recipe?.sessionUrl?.isNotEmpty ?? false)) {
      _bootstrapped.remove(url.host.toLowerCase());
      _session.remove(url.host.toLowerCase());
      await _ensureSession(url, recipe, cancelToken);
      page = await _fetchOnce(url, recipe, cancelToken);
    }
    return page;
  }

  Future<FetchedPage> _fetchOnce(
    Uri url,
    ScrapeRecipe? recipe,
    AiCancelToken? cancelToken,
  ) async {
    // The referer is computed from the URL the user gave us and held constant
    // across hops, the way a browser keeps sending the document that linked
    // here rather than the last redirect it bounced through.
    final referer = _refererFor(url, recipe);
    var current = url;

    for (var hop = 0; ; hop++) {
      cancelToken?.throwIfCancelled();
      await _throttle(current.host, _intervalFor(recipe));
      cancelToken?.throwIfCancelled();

      final response = await _send(current, recipe, referer, cancelToken);
      _absorbCookies(current, response);

      final location = response.headers['location'];
      final isRedirect =
          const {301, 302, 303, 307, 308}.contains(response.statusCode) &&
          location != null &&
          location.trim().isNotEmpty;
      if (isRedirect) {
        if (hop >= maxRedirects) {
          throw PageFetchException('Too many redirects fetching $url');
        }
        current = current.resolve(location.trim());
        if (!const {'http', 'https'}.contains(current.scheme)) {
          throw PageFetchException(
            'Redirect to unsupported scheme: ${current.scheme}',
          );
        }
        continue;
      }

      if (response.statusCode >= 400) {
        throw PageFetchException(
          'HTTP ${response.statusCode} fetching $current',
          statusCode: response.statusCode,
        );
      }
      final size = response.bodyBytes.length;
      if (size > maxPageBytes) {
        throw PageFetchException('Response too large ($size bytes)');
      }

      final decoded = HtmlDecoding.decode(
        response.bodyBytes,
        contentType: response.headers['content-type'],
      );
      return FetchedPage(
        url: current,
        requestedUrl: url,
        html: decoded.html,
        statusCode: response.statusCode,
        charset: decoded.charset,
        degraded: decoded.degraded,
      );
    }
  }

  /// One request, redirects **not** followed.
  ///
  /// Following them inside `http` would lose every `Set-Cookie` sent on the way
  /// — which is exactly where an age gate puts the cookie that matters — and
  /// would report the original URL as the response's own.
  Future<http.Response> _send(
    Uri url,
    ScrapeRecipe? recipe,
    Uri? referer,
    AiCancelToken? cancelToken,
  ) async {
    final client = cancelToken?.client ?? _client;
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll(headersFor(url, recipe: recipe, referer: referer));
    try {
      final streamed = await client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw PageFetchException('Timed out fetching $url');
    } on http.ClientException catch (e) {
      // Cancellation closes the client, which shows up here as a plain
      // ClientException with no distinguishing type.
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      throw PageFetchException('Network error: ${e.message}');
    }
  }

  /// Walks a recipe's `sessionUrl` once per host, so the server can mark the
  /// session as having passed whatever gate it puts in front of its pages.
  ///
  /// Failure is swallowed on purpose: the page fetch that follows will produce
  /// a far better error than "the gate did not answer", and some sites work
  /// perfectly well without the bootstrap.
  Future<void> _ensureSession(
    Uri url,
    ScrapeRecipe? recipe,
    AiCancelToken? cancelToken,
  ) async {
    final sessionUrl = recipe?.sessionUrl;
    if (sessionUrl == null || sessionUrl.trim().isEmpty) return;
    if (!_bootstrapped.add(url.host.toLowerCase())) return;

    final target = url.resolve(sessionUrl.trim());
    // A recipe is user-editable data; it must not be able to aim the session
    // request at another host and leak the cookies we hold for this one.
    if (target.host.toLowerCase() != url.host.toLowerCase()) return;

    try {
      var current = target;
      for (var hop = 0; hop <= maxRedirects; hop++) {
        cancelToken?.throwIfCancelled();
        await _throttle(current.host, _intervalFor(recipe));
        final response = await _send(
          current,
          recipe,
          _refererFor(url, recipe),
          cancelToken,
        );
        _absorbCookies(current, response);

        final location = response.headers['location']?.trim();
        if (location == null || location.isEmpty) break;
        final next = current.resolve(location);
        if (next.host.toLowerCase() != url.host.toLowerCase()) break;
        current = next;
      }
    } on AiCancelled {
      rethrow;
    } catch (_) {
      // See above: the page fetch reports the real problem.
    }
  }

  /// Records every `Set-Cookie` on [response] against [url]'s host.
  void _absorbCookies(Uri url, http.Response response) {
    // `Set-Cookie` legitimately repeats, and `http` folds repeats into one
    // comma-joined string. Splitting that by hand is a trap — an `Expires`
    // attribute contains a comma — so use the package's own splitter.
    final raw = response.headersSplitValues['set-cookie'];
    if (raw == null || raw.isEmpty) return;

    final jar = _session.putIfAbsent(url.host.toLowerCase(), () => {});
    for (final header in raw) {
      final cookie = CookieStore.parseSetCookie(header);
      if (cookie == null) continue;
      if (cookie.value.isEmpty) {
        jar.remove(cookie.key);
      } else {
        jar[cookie.key] = cookie.value;
      }
    }
  }

  /// The `Referer` to send with a page request.
  ///
  /// Defaults to the site root rather than nothing: arriving at a product page
  /// with no referer at all is something a browser essentially never does, and
  /// sites do reject it. Same-origin, so it discloses nothing the request does
  /// not already say. A recipe can override it, or set it empty to opt out.
  Uri? _refererFor(Uri url, ScrapeRecipe? recipe) {
    final override = recipe?.referer;
    if (override == null) return url.resolve('/');
    if (override.trim().isEmpty) return null;
    return url.resolve(override.trim());
  }

  /// Downloads a binary asset. [referer] must be the page the asset was linked
  /// from — image hosts commonly 403 a request without it.
  ///
  /// Returns null rather than throwing when the response is not a usable
  /// image, because artwork is never load-bearing: a missing poster degrades
  /// the result, it does not fail the scrape.
  Future<List<int>?> fetchBytes(
    Uri url, {
    required Uri referer,
    ScrapeRecipe? recipe,
    int minBytes = 512,
    AiCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    await _throttle(url.host, _intervalFor(recipe));
    final client = cancelToken?.client ?? _client;
    try {
      final headers = headersFor(url, recipe: recipe)
        ..['Referer'] = referer.toString();
      final res = await client.get(url, headers: headers).timeout(_timeout);
      if (res.statusCode >= 400) return null;
      final type = res.headers['content-type']?.toLowerCase() ?? '';
      if (type.isNotEmpty && !type.startsWith('image/')) return null;
      // Guards against tracking pixels and error pages served as images.
      if (res.bodyBytes.length < minBytes) return null;
      if (res.bodyBytes.length > maxPageBytes) return null;
      return res.bodyBytes;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      return null;
    }
  }

  /// Request headers for [url]: recipe headers, then the defaults, then the
  /// merged cookie header.
  Map<String, String> headersFor(
    Uri url, {
    ScrapeRecipe? recipe,
    Uri? referer,
  }) {
    final headers = <String, String>{
      'User-Agent': defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,image/*;q=0.9,*/*;q=0.8',
      ...?recipe?.headers,
    };
    if (referer != null) headers['Referer'] = referer.toString();
    final cookie = cookies.headerFor(
      url,
      staticCookies: recipe?.cookies,
      sessionCookies: _session[url.host.toLowerCase()],
    );
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  /// Cookies held for [host] this run, for display and tests. Read-only: the
  /// jar is filled by responses, never by callers.
  Map<String, String> sessionCookiesFor(String host) =>
      Map.unmodifiable(_session[host.toLowerCase()] ?? const {});

  /// Waits until at least [intervalMs] has passed since the previous request
  /// to [host], and holds the slot so concurrent callers queue up instead of
  /// all firing at once.
  Future<void> _throttle(String host, int intervalMs) {
    final previous = _hostQueue[host] ?? Future<void>.value();
    final next = previous.then((_) async {
      final last = _lastRequestAt[host];
      if (last != null) {
        final elapsed = DateTime.now().difference(last).inMilliseconds;
        final wait = intervalMs - elapsed;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      }
      _lastRequestAt[host] = DateTime.now();
    });
    _hostQueue[host] = next;
    return next;
  }

  /// Closes the shared client. Requests issued on a cancel token own their own
  /// client and are unaffected.
  void close() => _client.close();
}
