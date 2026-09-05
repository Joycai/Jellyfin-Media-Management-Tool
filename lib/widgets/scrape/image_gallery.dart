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
import '../glass/glass_menu.dart';

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
        const SizedBox(height: 4),
        Text(
          l10n.scrapeImageRoleHint,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 20) / 3;
            final tileHeight = tileWidth / 1.05;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final image in images)
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: _Tile(
                      image: image,
                      cache: cache,
                      selected: selected.contains(image.url),
                      role: roles[image.url] ?? ImageRole.original,
                      plannedName: plannedNames[image.url],
                      onTap: () =>
                          onToggle(image.url, !selected.contains(image.url)),
                      onDeselect: () => onToggle(image.url, false),
                      onRole: (role) => onRole(image.url, role),
                    ),
                  ),
              ],
            );
          },
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
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.scrapeImageCount(selected.length, images.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
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

/// The menu can hand back either a role or "deselect this tile", so its value
/// type carries both.
sealed class _MenuChoice {
  const _MenuChoice();
}

class _AssignRole extends _MenuChoice {
  final ImageRole role;
  const _AssignRole(this.role);
}

class _Deselect extends _MenuChoice {
  const _Deselect();
}

class _Tile extends StatelessWidget {
  final GalleryImage image;
  final ScrapeImageCache cache;
  final bool selected;
  final ImageRole role;
  final String? plannedName;
  final VoidCallback onTap;
  final VoidCallback onDeselect;
  final ValueChanged<ImageRole> onRole;

  const _Tile({
    required this.image,
    required this.cache,
    required this.selected,
    required this.role,
    required this.plannedName,
    required this.onTap,
    required this.onDeselect,
    required this.onRole,
  });

  /// The server's own file name, for the caption of an unselected tile and the
  /// "keep original name" menu entry.
  String get _serverName =>
      Uri.tryParse(image.url)?.pathSegments.lastOrNull ?? image.url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final marked = selected && role != ImageRole.original;

    return Tooltip(
      message: image.url,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
        // Long-press mirrors right-click, the way the file table's own context
        // menu does.
        onLongPress: () => _menu(context, null),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? scheme.tertiary.withValues(alpha: 0.7)
                  : glass.panelStroke,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.tertiary.withValues(alpha: 0.18),
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _preview(scheme),
              // Bottom scrim: what the tile is (role or unmarked) and the file
              // name it lands under — Jellyfin identifies artwork by name, so
              // the name is the point, not a detail.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE6111420)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_rounded
                                : Icons.circle_outlined,
                            size: 11,
                            color: selected
                                ? scheme.tertiary
                                : Colors.white.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              marked
                                  ? imageRoleLabel(l10n, role)
                                  : selected
                                  ? image.label
                                  : l10n.scrapeImageUnmarked,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? (marked
                                          ? scheme.tertiary
                                          : Colors.white.withValues(alpha: 0.9))
                                    : Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        selected ? (plannedName ?? '') : _serverName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
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
    final origin =
        at ??
        (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero);

    final picked = await showGlassMenu<_MenuChoice>(
      context,
      globalPosition: origin,
      items: [
        glassMenuHeader(context, l10n.scrapeImageRole),
        for (final option in ImageRole.values)
          if (option != ImageRole.original)
            glassMenuItem(
              context,
              value: _AssignRole(option),
              icon: imageRoleIcon(option),
              iconColor: _roleIconColor(option, Theme.of(context).colorScheme),
              label: imageRoleLabel(l10n, option),
              trailing: option.stem,
              selected: option == role,
            ),
        const PopupMenuDivider(),
        glassMenuItem(
          context,
          value: const _AssignRole(ImageRole.original),
          icon: Icons.check_rounded,
          label: l10n.scrapeRoleOriginal,
          trailing: _serverName,
          selected: role == ImageRole.original,
        ),
        if (selected)
          glassMenuItem(
            context,
            value: const _Deselect(),
            icon: Icons.remove_rounded,
            label: l10n.scrapeImageDeselect,
          ),
      ],
    );
    switch (picked) {
      case _AssignRole(:final role):
        onRole(role);
      case _Deselect():
        onDeselect();
      case null:
        break;
    }
  }

  /// The design tints the two headline roles by what they are — the poster in
  /// the accent color, the backdrop in the amber the origin badges use — and
  /// leaves the long tail muted. Null falls through to the menu's default.
  static Color? _roleIconColor(ImageRole role, ColorScheme scheme) =>
      switch (role) {
        ImageRole.poster => scheme.primary,
        ImageRole.fanart => const Color(0xFFE0852C),
        _ => null,
      };

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

/// Menu icon for a role — the design pairs each slot with a small pictogram.
/// Lives beside [imageRoleLabel] for the same reason it does: the enum stays
/// free of Flutter imports.
IconData imageRoleIcon(ImageRole role) => switch (role) {
  ImageRole.original => Icons.check_rounded,
  ImageRole.poster => Icons.image_outlined,
  ImageRole.fanart => Icons.landscape_outlined,
  ImageRole.extraFanart => Icons.burst_mode_outlined,
  ImageRole.thumb => Icons.crop_16_9_rounded,
  ImageRole.menu => Icons.menu_book_outlined,
  ImageRole.banner => Icons.view_day_outlined,
  ImageRole.logo => Icons.label_outline_rounded,
  ImageRole.clearArt => Icons.auto_awesome_outlined,
  ImageRole.disc => Icons.album_outlined,
};

/// Menu label for a role. Lives here rather than on the enum so the enum stays
/// free of `BuildContext`, like every other model in this module.
String imageRoleLabel(AppLocalizations l10n, ImageRole role) => switch (role) {
  ImageRole.original => l10n.scrapeRoleOriginal,
  ImageRole.poster => l10n.scrapeRolePoster,
  ImageRole.fanart => l10n.scrapeRoleFanart,
  ImageRole.extraFanart => l10n.scrapeRoleExtraFanart,
  ImageRole.thumb => l10n.scrapeRoleThumb,
  ImageRole.menu => l10n.scrapeRoleMenu,
  ImageRole.banner => l10n.scrapeRoleBanner,
  ImageRole.logo => l10n.scrapeRoleLogo,
  ImageRole.clearArt => l10n.scrapeRoleClearArt,
  ImageRole.disc => l10n.scrapeRoleDisc,
};
