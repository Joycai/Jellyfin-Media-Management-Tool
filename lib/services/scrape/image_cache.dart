/// In-memory image bytes for one scrape, shared between the preview grid and
/// the write that follows it.
///
/// The preview used to show URLs rather than thumbnails, on the grounds that
/// pre-fetching thirty stills to draw a grid would defeat the per-host interval
/// `PageFetcher` exists to enforce. Showing them is worth more than that
/// argument protects — you cannot pick artwork you cannot see — but the
/// argument is still right, so two things hold:
///
/// * fetches go through [PageFetcher] as before, so the politeness floor still
///   applies and the grid fills in progressively rather than all at once;
/// * **every byte is kept.** The commit reads from here instead of downloading
///   again, so choosing three stills out of thirty costs exactly the thirty
///   fetches the grid already made — not thirty-three.
///
/// Scoped to one panel and dropped with it. Artwork is never load-bearing: a
/// URL that fails is remembered as failed and the tile shows a placeholder.
library;

import 'dart:async';

import '../../models/scrape_recipe.dart';
import 'page_fetcher.dart';

class ScrapeImageCache {
  final PageFetcher fetcher;

  /// The page the images were linked from. Image hosts commonly 403 a request
  /// whose `Referer` is not the page that embedded them.
  final Uri referer;

  final ScrapeRecipe? recipe;

  ScrapeImageCache({required this.fetcher, required this.referer, this.recipe});

  final Map<String, List<int>?> _bytes = {};
  final Map<String, Future<List<int>?>> _inFlight = {};

  /// Bytes already known for [url], or null when it has not been fetched or
  /// could not be. Synchronous, for painting a tile that is already loaded.
  List<int>? peek(String url) => _bytes[url];

  bool isLoaded(String url) => _bytes.containsKey(url);
  bool isFailed(String url) => _bytes.containsKey(url) && _bytes[url] == null;

  int get loadedCount => _bytes.values.where((b) => b != null).length;

  /// Fetches [url] once. Concurrent callers for the same URL share one request
  /// rather than queueing a second behind the host interval.
  Future<List<int>?> load(String url) {
    if (_bytes.containsKey(url)) return Future.value(_bytes[url]);
    return _inFlight[url] ??= _fetch(url);
  }

  Future<List<int>?> _fetch(String url) async {
    List<int>? bytes;
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme) {
        bytes = await fetcher.fetchBytes(uri, referer: referer, recipe: recipe);
      }
    } catch (_) {
      // Deliberately swallowed: a missing image degrades the result, it does
      // not fail the scrape. The null below marks it so it is not retried.
    }
    _bytes[url] = bytes;
    unawaited(_inFlight.remove(url));
    return bytes;
  }

  /// Loads [urls] in order, calling [onProgress] as each settles.
  ///
  /// Serial on purpose. `PageFetcher` serialises per host anyway, so firing
  /// thirty futures at once would only queue them inside the fetcher while
  /// making any progress report a lie.
  Future<void> loadAll(
    List<String> urls, {
    void Function()? onProgress,
    bool Function()? isCancelled,
  }) async {
    for (final url in urls) {
      if (isCancelled?.call() ?? false) return;
      if (_bytes.containsKey(url)) continue;
      await load(url);
      onProgress?.call();
    }
  }
}
