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
import '../../services/scrape/image_role.dart';
import '../../theme/app_theme.dart';

/// One image on offer.
class GalleryImage {
  final String url;

  /// Where the page offered it — "Poster", "Still 3". Describes the source,
  /// not the destination; the destination is the role.
  final String label;

  const GalleryImage({required this.url, required this.label});
}

class ImageGallery extends StatelessWidget {
  final List<GalleryImage> images;
  final Set<String> selected;
  final ScrapeImageCache cache;

  /// url -> what the file will be called. Right-click assigns it.
  final Map<String, ImageRole> roles;

  /// url -> the exact file name that would be written, for the tile caption.
  final Map<String, String> plannedNames;

  /// Null while the initial sweep is still running, so the header can say so.
  final int? loadingRemaining;

  final void Function(String url, bool selected) onToggle;
  final void Function(String url, ImageRole role) onRole;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  /// Null while a save is running, which disables the button.
  final VoidCallback? onSave;

  const ImageGallery({
    super.key,
    required this.images,
    required this.selected,
    required this.cache,
    required this.roles,
    required this.plannedNames,
    required this.onToggle,
    required this.onRole,
    required this.onSelectAll,
    required this.onSelectNone,
    this.onSave,
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
                role: roles[image.url] ?? ImageRole.original,
                plannedName: plannedNames[image.url],
                onTap: () => onToggle(image.url, !selected.contains(image.url)),
                onRole: (role) => onRole(image.url, role),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _saveRow(l10n, scheme),
      ],
    );
  }

  /// Saving is its own operation, deliberately not folded into Write.
  ///
  /// Writing the NFO and putting pictures in a folder are different jobs with
  /// different risks — one rewrites a metadata file, the other only adds image
  /// files — and wanting the second without the first is an ordinary thing to
  /// want.
  Widget _saveRow(AppLocalizations l10n, ColorScheme scheme) => Row(
    children: [
      FilledButton.tonalIcon(
        onPressed: selected.isEmpty ? null : onSave,
        icon: const Icon(Icons.download_rounded, size: 17),
        label: Text(l10n.scrapeSaveImages(selected.length)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          l10n.scrapeSaveImagesHint,
          style: TextStyle(
            fontSize: 11,
            height: 1.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

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
  final ImageRole role;
  final String? plannedName;
  final VoidCallback onTap;
  final ValueChanged<ImageRole> onRole;

  const _Tile({
    required this.image,
    required this.cache,
    required this.selected,
    required this.role,
    required this.plannedName,
    required this.onTap,
    required this.onRole,
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
        onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
        // Long-press mirrors right-click, the way the file table's own context
        // menu does.
        onLongPress: () => _menu(context, null),
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
                        fontWeight: role == ImageRole.original
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: selected ? scheme.primary : null,
                      ),
                    ),
                  ),
                ],
              ),
              // The name it will be written under. This is the whole point of
              // a role — Jellyfin identifies artwork by file name — so it is
              // shown rather than left to be inferred from a menu tick.
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    plannedName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: role == ImageRole.original
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Right-click: assign the Jellyfin name this image should take.
  Future<void> _menu(BuildContext context, Offset? at) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin =
        at ??
        (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero);

    final picked = await showMenu<ImageRole>(
      context: context,
      position: RelativeRect.fromRect(
        origin & Size.zero,
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 210),
      items: [
        PopupMenuItem<ImageRole>(
          enabled: false,
          height: 32,
          child: Text(
            l10n.scrapeImageRole,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
        for (final option in ImageRole.values)
          PopupMenuItem<ImageRole>(
            value: option,
            height: 38,
            child: Row(
              children: [
                Icon(
                  option == role
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 15,
                ),
                const SizedBox(width: 10),
                Text(
                  imageRoleLabel(l10n, option),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
    if (picked != null) onRole(picked);
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

/// Menu label for a role. Lives here rather than on the enum so the enum stays
/// free of `BuildContext`, like every other model in this module.
String imageRoleLabel(AppLocalizations l10n, ImageRole role) => switch (role) {
  ImageRole.original => l10n.scrapeRoleOriginal,
  ImageRole.poster => l10n.scrapeRolePoster,
  ImageRole.fanart => l10n.scrapeRoleFanart,
  ImageRole.extraFanart => l10n.scrapeRoleExtraFanart,
  ImageRole.landscape => l10n.scrapeRoleLandscape,
  ImageRole.thumb => l10n.scrapeRoleThumb,
  ImageRole.banner => l10n.scrapeRoleBanner,
  ImageRole.logo => l10n.scrapeRoleLogo,
  ImageRole.clearArt => l10n.scrapeRoleClearArt,
  ImageRole.disc => l10n.scrapeRoleDisc,
};
