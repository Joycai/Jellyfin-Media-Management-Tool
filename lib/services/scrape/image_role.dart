/// What a scraped image should become on disk.
///
/// Jellyfin recognises artwork by **file name**, not by anything in the NFO, so
/// naming a file `folder.jpg` is what makes it the poster. That is the whole
/// mechanism, and it is why marking an image with a role is a real operation
/// rather than a label: the role *is* the file name.
///
/// Each role is one Jellyfin image *type* (Primary, Backdrop, Thumb, …), and
/// [ImageRole.stem] is the one file name this app writes for it. Jellyfin
/// accepts several names per type — `poster`/`folder`/`cover` are all Primary,
/// `backdrop`/`fanart`/`background` all Backdrop — and the stems here are the
/// ones verified against a live server. Two roles must never share a type:
/// a `thumb.jpg` next to a `landscape.jpg` is two files for one slot, and
/// Jellyfin silently picks one.
///
/// [ImageRole.original] is the default for anything the scrape did not already
/// identify. An image the user just wants to keep should land under the name it
/// had on the server, not be forced into a slot it does not fill.
library;

import '../../models/media_metadata.dart';

enum ImageRole {
  /// Keep the file name the server used.
  original,

  /// Primary — the vertical cover. Written as `folder`.
  poster,

  /// Backdrop — the wide background. Written as `backdrop`; the NFO's `<art>`
  /// block still calls the element `<fanart>`, which is a Kodi element name
  /// and not a file name.
  fanart,

  /// Additional backdrops, numbered inside `extrafanart/` — the one role that
  /// can hold more than one image.
  extraFanart,

  /// Thumb — the 16:9 thumbnail. Written as `landscape`.
  thumb,

  /// Menu artwork. Written as `menu`.
  menu,

  banner,
  logo,
  clearArt,
  disc;

  /// True for roles that name exactly one file. Assigning one of these to a
  /// second image has to clear it from the first, or both would be written to
  /// the same path and the later would silently win.
  bool get isSingleSlot =>
      this != ImageRole.original && this != ImageRole.extraFanart;

  /// The name stem Jellyfin looks for, or null when the file keeps its own.
  ///
  /// `NfoOptions` defaults its `<art>` file names to the poster and fanart
  /// stems here; a test pins the two together.
  String? get stem => switch (this) {
    ImageRole.original => null,
    ImageRole.poster => 'folder',
    ImageRole.fanart => 'backdrop',
    ImageRole.extraFanart => 'extrafanart/backdrop',
    ImageRole.thumb => 'landscape',
    ImageRole.menu => 'menu',
    ImageRole.banner => 'banner',
    ImageRole.logo => 'logo',
    ImageRole.clearArt => 'clearart',
    ImageRole.disc => 'disc',
  };
}

/// Works out the file each selected image should be written to.
///
/// Pure, and separate from the widget that offers the menu, so the naming rules
/// can be asserted without a UI.
class ImageNaming {
  /// Builds `url -> relative file name` for [selected], in [order].
  ///
  /// [extensionOf] supplies the extension from the bytes' magic number rather
  /// than the URL — plenty of CDNs serve a PNG from a `.jpg` path, and since
  /// Jellyfin matches on name, writing `poster.jpg` full of PNG data is a real
  /// if quiet bug.
  ///
  /// Collisions are resolved rather than allowed to overwrite: two images whose
  /// server names match get ` (2)` appended, the way a file manager would.
  static Map<String, String> plan({
    required List<String> order,
    required Set<String> selected,
    required Map<String, ImageRole> roles,
    required String Function(String url) extensionOf,
  }) {
    final out = <String, String>{};
    final used = <String>{};
    var extra = 0;

    for (final url in order) {
      if (!selected.contains(url)) continue;
      final role = roles[url] ?? ImageRole.original;
      final extension = extensionOf(url);

      String name;
      if (role == ImageRole.extraFanart) {
        name = 'extrafanart/backdrop-${++extra}.$extension';
      } else if (role.stem != null) {
        name = '${role.stem}.$extension';
      } else {
        name = '${originalStem(url)}.$extension';
      }

      out[url] = _deduplicate(name, used);
    }
    return out;
  }

  /// The server's own file name, stripped of its extension and of anything
  /// that could steer the write out of the target folder.
  ///
  /// `MetadataWriter` validates with `PathSafety` regardless, but a name that
  /// fails there is a failed image rather than a saved one — better to produce
  /// a usable name here than to rely on the backstop.
  static String originalStem(String url) {
    var last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final dot = last.lastIndexOf('.');
    if (dot > 0) last = last.substring(0, dot);
    var cleaned = last.replaceAll(RegExp(r'[^\w.\- ]'), '_').trim();
    // Strip leading dots, spaces and the underscores a separator turned into:
    // `..%2f..%2fevil.jpg` decodes to `../../evil`, and neutralising only the
    // slashes would leave `.._.._evil` — a hidden file rather than an escape,
    // but still not the name anyone asked for.
    cleaned = cleaned.replaceAll(RegExp(r'^[._\s]+'), '').trim();
    return cleaned.isEmpty ? 'image' : cleaned;
  }

  static String _deduplicate(String name, Set<String> used) {
    if (used.add(name)) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    for (var n = 2; ; n++) {
      final candidate = '$stem ($n)$extension';
      if (used.add(candidate)) return candidate;
    }
  }

  /// The role each image starts with: whatever the scrape already worked out,
  /// and [ImageRole.original] for everything it did not.
  static Map<String, ImageRole> defaultsFor(MediaMetadata metadata) => {
    if (metadata.posterUrl != null) metadata.posterUrl!: ImageRole.poster,
    if (metadata.fanartUrl != null && metadata.fanartUrl != metadata.posterUrl)
      metadata.fanartUrl!: ImageRole.fanart,
  };
}
