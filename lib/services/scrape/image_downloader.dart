/// Turns the image URLs on a [MediaMetadata] into files ready for
/// `MetadataWriter`.
///
/// Artwork is never load-bearing: every failure here degrades to "that image
/// is missing" and the NFO still gets written. That mirrors how
/// `ThumbnailService` treats a failed poster frame.
library;

import '../../models/media_metadata.dart';
import '../../models/scrape_recipe.dart';
import '../ai/ai_cancel_token.dart';
import '../metadata/metadata_writer.dart';
import 'page_fetcher.dart';

/// Which of the available images the user actually wants.
///
/// A product page can carry 30+ sample stills; downloading all of them by
/// default would bloat every library folder, so the preview picks a handful
/// and the user opts into more.
class ImageSelection {
  final bool poster;
  final bool fanart;

  /// Indices into [MediaMetadata.extraFanartUrls]. Null means "the first
  /// [defaultExtraFanartCount]".
  final Set<int>? extraFanart;

  const ImageSelection({
    this.poster = true,
    this.fanart = true,
    this.extraFanart,
  });

  static const defaultExtraFanartCount = 5;

  /// Nothing but the poster — the minimal useful scrape.
  static const posterOnly = ImageSelection(
    poster: true,
    fanart: false,
    extraFanart: <int>{},
  );

  /// No artwork at all. The default for a folder-wide refresh: the images were
  /// downloaded on the first scrape and re-fetching hundreds of them to write
  /// identical bytes is pure cost.
  static const none = ImageSelection(
    poster: false,
    fanart: false,
    extraFanart: <int>{},
  );

  Set<int> resolveExtra(int available) =>
      extraFanart ??
      {for (var i = 0; i < available && i < defaultExtraFanartCount; i++) i};
}

/// Progress callback: [done] of [total] images finished.
typedef ImageProgress = void Function(int done, int total);

class ImageDownloader {
  final PageFetcher fetcher;

  const ImageDownloader(this.fetcher);

  /// Downloads the selected images and names them the way Jellyfin expects.
  ///
  /// The returned list is safe to hand straight to `MetadataWriter`; images
  /// that failed to download are simply absent.
  Future<List<ImageAsset>> download(
    MediaMetadata metadata, {
    required Uri referer,
    ScrapeRecipe? recipe,
    ImageSelection selection = const ImageSelection(),
    AiCancelToken? cancelToken,
    ImageProgress? onProgress,
  }) async {
    final jobs = <(String, String)>[]; // (relative path stem, url)

    if (selection.poster && metadata.posterUrl != null) {
      jobs.add(('poster', metadata.posterUrl!));
    }
    if (selection.fanart && metadata.fanartUrl != null) {
      jobs.add(('fanart', metadata.fanartUrl!));
    }
    final wanted = selection.resolveExtra(metadata.extraFanartUrls.length);
    var n = 0;
    for (var i = 0; i < metadata.extraFanartUrls.length; i++) {
      if (!wanted.contains(i)) continue;
      n++;
      jobs.add(('extrafanart/backdrop-$n', metadata.extraFanartUrls[i]));
    }

    final assets = <ImageAsset>[];
    var done = 0;
    for (final (stem, url) in jobs) {
      cancelToken?.throwIfCancelled();
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme) {
        final bytes = await fetcher.fetchBytes(
          uri,
          referer: referer,
          recipe: recipe,
          cancelToken: cancelToken,
        );
        if (bytes != null) {
          assets.add(
            ImageAsset(
              relativePath: '$stem.${extensionFor(bytes)}',
              bytes: bytes,
            ),
          );
        }
      }
      onProgress?.call(++done, jobs.length);
    }
    return assets;
  }

  /// Picks the file extension from the bytes' magic number rather than from
  /// the URL: plenty of CDNs serve a PNG from a `.jpg` path, and Jellyfin
  /// matches artwork by name, so writing `poster.jpg` containing PNG data is a
  /// real (if quiet) bug.
  static String extensionFor(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    return 'jpg';
  }
}
