/// Renders [MediaMetadata] as a Kodi/Jellyfin `.nfo` document.
///
/// Two rules shape this file:
///
/// * **Never destroy what we did not write.** An existing NFO may carry
///   elements from another scraper, or hand-written corrections. Only the
///   elements in [NfoWriter.managedElements] are replaced; everything else is
///   copied through verbatim. "Scrape once with this tool and lose your data"
///   is not an acceptable outcome.
/// * **Produce text, not a file.** Writing to disk is `MetadataWriter`'s job
///   and goes through `PathSafety`; this class stays pure so it can be tested
///   without a filesystem.
library;

import 'package:xml/xml.dart';

import '../../models/media_metadata.dart';

/// Which NFO flavour to emit. Jellyfin picks the reader by file name, but the
/// root element has to agree with it.
enum NfoKind {
  movie('movie'),
  tvShow('tvshow'),
  episode('episodedetails');

  const NfoKind(this.rootElement);
  final String rootElement;
}

class NfoOptions {
  /// Prefix `<title>` with the product code (`SPSF-43 …`).
  ///
  /// On by default because a library of catalogue-numbered releases is far
  /// easier to browse and sort that way, and Jellyfin shows `<title>` verbatim.
  /// The original name is always preserved in `<originaltitle>`, so nothing is
  /// lost when this is on.
  final bool prefixTitleWithCode;

  /// Value of the `type` attribute on `<uniqueid>`.
  final String uniqueIdType;

  /// File names written into `<art>`. These are the names
  /// `MetadataWriter` saves the images under, so the two must agree.
  final String posterFileName;
  final String fanartFileName;

  const NfoOptions({
    this.prefixTitleWithCode = true,
    this.uniqueIdType = 'custom',
    this.posterFileName = 'poster.jpg',
    this.fanartFileName = 'fanart.jpg',
  });
}

class NfoWriter {
  /// Elements this writer owns. Anything else found in an existing NFO is
  /// preserved untouched.
  static const managedElements = <String>{
    'title',
    'originaltitle',
    'sorttitle',
    'plot',
    'outline',
    'tagline',
    'premiered',
    'releasedate',
    'year',
    'runtime',
    'rating',
    'studio',
    'set',
    'director',
    'genre',
    'tag',
    'actor',
    'uniqueid',
    'art',
    'thumb',
    'fanart',
    'poster',
  };

  /// Serializes [metadata]. When [existingXml] is given, its unmanaged
  /// elements are carried over; if it cannot be parsed it is ignored (an
  /// unreadable NFO is not worth failing the whole write for — the caller has
  /// already backed the original up).
  static String write(
    MediaMetadata metadata, {
    String? existingXml,
    NfoKind kind = NfoKind.movie,
    NfoOptions options = const NfoOptions(),
    bool includeArt = true,
  }) {
    final document = _build(metadata, kind, options, includeArt);

    if (existingXml != null && existingXml.trim().isNotEmpty) {
      try {
        final previous = XmlDocument.parse(existingXml);
        final root = document.rootElement;
        for (final child in previous.rootElement.children) {
          if (child is! XmlElement) continue;
          if (managedElements.contains(child.name.local.toLowerCase())) {
            continue;
          }
          root.children.add(child.copy());
        }
      } on XmlException {
        // Unparseable previous file: fall through and write ours alone.
      }
    }
    return '${document.toXmlString(pretty: true, indent: '  ')}\n';
  }

  static XmlDocument _build(
    MediaMetadata m,
    NfoKind kind,
    NfoOptions options,
    bool includeArt,
  ) {
    final b = XmlBuilder();
    b.declaration(
      version: '1.0',
      encoding: 'utf-8',
      attributes: {'standalone': 'yes'},
    );
    b.element(
      kind.rootElement,
      nest: () {
        _text(b, 'title', _displayTitle(m, options));
        _text(b, 'originaltitle', m.originalTitle ?? m.title);
        _text(b, 'sorttitle', m.sortTitle ?? m.code);
        _text(b, 'plot', m.plot);
        _text(b, 'outline', m.outline);
        _text(b, 'tagline', m.tagline);
        _text(b, 'premiered', m.premiered);
        // Kodi-era readers look for <releasedate>; Jellyfin reads <premiered>.
        // Emitting both costs one line and avoids a support question.
        _text(b, 'releasedate', m.premiered);
        _text(b, 'year', m.year?.toString());
        _text(b, 'runtime', m.runtimeMinutes?.toString());
        _text(b, 'rating', m.rating?.toString());
        _text(b, 'studio', m.studio);

        final series = m.series;
        if (series != null && series.isNotEmpty) {
          b.element('set', nest: () => _text(b, 'name', series));
        }
        _text(b, 'director', m.director);
        for (final g in m.genres) {
          _text(b, 'genre', g);
        }
        for (final t in m.tags) {
          _text(b, 'tag', t);
        }
        for (final a in m.actors) {
          b.element(
            'actor',
            nest: () {
              _text(b, 'name', a.name);
              _text(b, 'role', a.role);
              _text(b, 'thumb', a.thumbUrl);
              _text(b, 'type', 'Actor');
            },
          );
        }

        final code = m.code;
        if (code != null && code.isNotEmpty) {
          b.element(
            'uniqueid',
            attributes: {'type': options.uniqueIdType, 'default': 'true'},
            nest: code,
          );
        }

        if (includeArt && (m.posterUrl != null || m.fanartUrl != null)) {
          b.element(
            'art',
            nest: () {
              if (m.posterUrl != null) {
                _text(b, 'poster', options.posterFileName);
              }
              if (m.fanartUrl != null) {
                _text(b, 'fanart', options.fanartFileName);
              }
            },
          );
        }

        final source = m.sourceUrl;
        if (source != null && source.isNotEmpty) {
          b.comment(' scraped from $source ');
        }
      },
    );
    return b.buildDocument();
  }

  /// `SPSF-43 美少女戦士…` when a code is present and the title does not
  /// already start with it.
  static String? _displayTitle(MediaMetadata m, NfoOptions options) {
    final title = m.title;
    final code = m.code;
    if (title == null || title.isEmpty) return code;
    if (!options.prefixTitleWithCode || code == null || code.isEmpty) {
      return title;
    }
    if (title.toLowerCase().startsWith(code.toLowerCase())) return title;
    return '$code $title';
  }

  /// Writes `<name>value</name>`, skipping blanks so the NFO has no empty
  /// elements (Jellyfin treats an empty `<plot/>` as a real empty synopsis and
  /// will happily overwrite a good one with it).
  static void _text(XmlBuilder b, String name, String? value) {
    if (value == null || value.trim().isEmpty) return;
    b.element(name, nest: value.trim());
  }
}
