/// The one place that talks to a scraped site.
///
/// Everything awkward about fetching a third-party page lives here so the rest
/// of the pipeline can assume it is handed a correctly decoded string:
///
/// * **encoding** — see [HtmlDecoding]; `http`'s default of latin1 mangles
///   Japanese pages;
/// * **cookies** — an age gate is usually one static flag (`old_check=yes`),
///   with a user-imported `cookies.txt` as the fallback;
/// * **headers** — the default Dart user agent gets refused by some sites, and
///   image CDNs check `Referer` against the page the image was linked from;
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
  final Uri url;
  final String html;
  final int statusCode;
  final String charset;

  /// True when the charset had no codec available; the text may be lossy.
  final bool degraded;

  const FetchedPage({
    required this.url,
    required this.html,
    required this.statusCode,
    required this.charset,
    this.degraded = false,
  });
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
    cancelToken?.throwIfCancelled();
    await _throttle(url.host, _intervalFor(recipe));
    cancelToken?.throwIfCancelled();

    final client = cancelToken?.client ?? _client;
    final http.Response response;
    try {
      response = await client
          .get(url, headers: headersFor(url, recipe: recipe))
          .timeout(_timeout);
    } on TimeoutException {
      throw PageFetchException('Timed out fetching $url');
    } on http.ClientException catch (e) {
      // Cancellation closes the client, which shows up here as a plain
      // ClientException with no distinguishing type.
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      throw PageFetchException('Network error: ${e.message}');
    }
    cancelToken?.throwIfCancelled();

    if (response.statusCode >= 400) {
      throw PageFetchException(
        'HTTP ${response.statusCode} fetching $url',
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
      url: response.request?.url ?? url,
      html: decoded.html,
      statusCode: response.statusCode,
      charset: decoded.charset,
      degraded: decoded.degraded,
    );
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
  Map<String, String> headersFor(Uri url, {ScrapeRecipe? recipe}) {
    final headers = <String, String>{
      'User-Agent': defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,image/*;q=0.9,*/*;q=0.8',
      ...?recipe?.headers,
    };
    final cookie = cookies.headerFor(url, staticCookies: recipe?.cookies);
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

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
