/// The artwork picker: every image the page offered, as a thumbnail you can
/// tick.
///
/// Replaces a row of URL chips. A chip told you a file existed and left you to
/// guess whether it was the cover, a logo or a banner ad — which is not a
/// choice anyone can make well. Tiles load progressively through
/// [ScrapeImageCache] so the per-host interval still holds, and the bytes they
/// load are the same ones the write uses.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/scrape/image_cache.dart';
import '../../theme/app_theme.dart';

/// One image on offer.
class GalleryImage {
  final String url;

  /// "Poster", "Backdrop", "Still 3" — what this image would become.
  final String label;

  /// Poster and backdrop are single-slot: ticking one unticks nothing, but
  /// they are shown first and at a larger size because they are the two that
  /// matter most.
  final bool primary;

  const GalleryImage({
    required this.url,
    required this.label,
    this.primary = false,
  });
}

class ImageGallery extends StatelessWidget {
  final List<GalleryImage> images;
  final Set<String> selected;
  final ScrapeImageCache cache;

  /// Null while the initial sweep is still running, so the header can say so.
  final int? loadingRemaining;

  final void Function(String url, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  const ImageGallery({
    super.key,
    required this.images,
    required this.selected,
    required this.cache,
    required this.onToggle,
    required this.onSelectAll,
    required this.onSelectNone,
    this.loadingRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (images.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.scrapeImageNone,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(l10n, scheme),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final image in images)
              _Tile(
                image: image,
                cache: cache,
                selected: selected.contains(image.url),
                onTap: () => onToggle(image.url, !selected.contains(image.url)),
              ),
          ],
        ),
      ],
    );
  }

  /// The label side is [Expanded] and every text in it can ellipsize: this
  /// header sits in a column whose width the user does not control, and a
  /// fixed-width Row here overflowed at the narrow end.
  Widget _header(AppLocalizations l10n, ColorScheme scheme) => Row(
    children: [
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: Text(
                l10n.scrapeImages,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.scrapeImageCount(selected.length, images.length),
              maxLines: 1,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if ((loadingRemaining ?? 0) > 0) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  l10n.scrapeImageLoading(loadingRemaining!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      TextButton(
        onPressed: onSelectAll,
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        child: Text(l10n.scrapeImageSelectAll),
      ),
      TextButton(
        onPressed: onSelectNone,
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        child: Text(l10n.scrapeImageSelectNone),
      ),
    ],
  );
}

class _Tile extends StatelessWidget {
  final GalleryImage image;
  final ScrapeImageCache cache;
  final bool selected;
  final VoidCallback onTap;

  const _Tile({
    required this.image,
    required this.cache,
    required this.selected,
    required this.onTap,
  });

  static const _width = 132.0;
  static const _height = 100.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    return Tooltip(
      message: image.url,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: _width,
          decoration: BoxDecoration(
            color: glass.panelFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : glass.panelStroke,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: _height,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _preview(scheme),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 15,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      image.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: image.primary
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? scheme.primary : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The tile never blocks on the network: whatever the cache has right now is
  /// what gets painted, and the parent rebuilds as bytes arrive.
  Widget _preview(ColorScheme scheme) {
    final bytes = cache.peek(image.url);
    if (bytes != null) {
      return Image.memory(
        // Already a Uint8List off the wire in practice; the copy is only a
        // fallback for an injected fake.
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        fit: BoxFit.cover,
        width: double.infinity,
        height: _height,
        // A file that downloaded but will not decode is still a dead end for
        // the user, so it looks the same as one that failed to arrive.
        errorBuilder: (_, _, _) =>
            _placeholder(scheme, Icons.broken_image_outlined),
      );
    }
    if (cache.isFailed(image.url)) {
      return _placeholder(scheme, Icons.broken_image_outlined);
    }
    // A quiet placeholder, not a spinner. The header already reports how many
    // are left; thirty tiles each animating their own indicator is noise, and
    // it means the grid never stops requesting frames.
    return _placeholder(scheme, Icons.image_outlined);
  }

  Widget _placeholder(ColorScheme scheme, IconData icon) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        icon,
        size: 20,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    ),
  );
}
