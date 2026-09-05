/// Reads an existing `.nfo` back into [MediaMetadata] so the preview can show
/// a real three-way comparison (what is on disk / what was scraped / what will
/// be written) instead of blindly overwriting.
///
/// Everything it produces is tagged [FieldOrigin.existingNfo], which is what
/// makes the merge defaults in `NfoMerge` possible.
library;

import 'package:xml/xml.dart';

import '../../models/media_metadata.dart';

class NfoReader {
  /// The root element of [xmlText] (`movie`, `tvshow`, …), or null when there
  /// is no parseable document. Lets a refresh keep the flavour a file already
  /// has instead of assuming every NFO is a movie.
  static String? rootElementName(String? xmlText) {
    if (xmlText == null || xmlText.trim().isEmpty) return null;
    try {
      return XmlDocument.parse(xmlText).rootElement.name.local;
    } on XmlException {
      return null;
    }
  }

  /// Parses [xmlText]. Returns null when the document is not usable XML —
  /// callers treat that as "no existing metadata" and keep the file for backup
  /// rather than trying to repair it.
  static MediaMetadata? read(String xmlText) {
    if (xmlText.trim().isEmpty) return null;
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException {
      return null;
    }

    final root = doc.rootElement;
    final m = MediaMetadata();
    const origin = FieldOrigin.existingNfo;

    m.set(MetadataField.title, _text(root, 'title'), origin);
    m.set(MetadataField.originalTitle, _text(root, 'originaltitle'), origin);
    m.set(MetadataField.sortTitle, _text(root, 'sorttitle'), origin);
    m.set(MetadataField.plot, _text(root, 'plot'), origin);
    m.set(MetadataField.outline, _text(root, 'outline'), origin);
    m.set(MetadataField.tagline, _text(root, 'tagline'), origin);
    m.set(
      MetadataField.premiered,
      _text(root, 'premiered') ?? _text(root, 'releasedate'),
      origin,
    );
    m.set(MetadataField.runtimeMinutes, _text(root, 'runtime'), origin);
    m.set(MetadataField.rating, _text(root, 'rating'), origin);
    m.set(MetadataField.studio, _text(root, 'studio'), origin);
    m.set(MetadataField.director, _text(root, 'director'), origin);

    final set = root.getElement('set');
    m.set(
      MetadataField.series,
      set == null ? null : (_text(set, 'name') ?? _trimmed(set.innerText)),
      origin,
    );

    m.set(MetadataField.genres, _texts(root, 'genre'), origin);
    m.set(MetadataField.tags, _texts(root, 'tag'), origin);

    final actors = <MetadataActor>[];
    for (final el in root.findElements('actor')) {
      final name = _text(el, 'name');
      if (name == null) continue;
      actors.add(
        MetadataActor(
          name: name,
          role: _text(el, 'role'),
          thumbUrl: _text(el, 'thumb'),
        ),
      );
    }
    m.set(MetadataField.actors, actors, origin);

    // <uniqueid> is the code's home; fall back to <sorttitle> for NFOs written
    // by tools that only had that.
    for (final el in root.findElements('uniqueid')) {
      final value = _trimmed(el.innerText);
      if (value == null) continue;
      m.set(MetadataField.code, value, origin);
      if (el.getAttribute('default') == 'true') break;
    }
    if (m.code == null) m.set(MetadataField.code, m.sortTitle, origin);

    // <art> is deliberately NOT read back.
    //
    // It holds the local file names our own writer put there (`poster.jpg`),
    // not source URLs, so comparing it against a freshly scraped URL would
    // produce a meaningless "conflict" and — because the default for a
    // conflict is to keep the existing value — would leave the merged
    // metadata pointing at a file name that `ImageDownloader` cannot fetch.
    // Artwork selection belongs to the preview, not to the field merge.

    m.sourceUrl = _sourceUrl(root);

    return m;
  }

  /// Recovers the `<!-- scraped from … -->` comment `NfoWriter` leaves behind.
  ///
  /// That comment exists so a later re-scrape can find the page again; reading
  /// it back is what makes a folder-wide refresh possible without asking for
  /// every URL a second time. A comment rather than an element because it is
  /// our provenance, not something Jellyfin should ever try to interpret.
  static String? _sourceUrl(XmlElement root) {
    for (final node in root.children.whereType<XmlComment>()) {
      final text = node.value.trim();
      if (!text.startsWith(_sourceMarker)) continue;
      final url = text.substring(_sourceMarker.length).trim();
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  /// Must match what `NfoWriter` emits.
  static const _sourceMarker = 'scraped from ';

  static String? _text(XmlElement parent, String name) {
    final el = parent.getElement(name);
    return el == null ? null : _trimmed(el.innerText);
  }

  static List<String> _texts(XmlElement parent, String name) {
    final out = <String>[];
    for (final el in parent.findElements(name)) {
      final t = _trimmed(el.innerText);
      if (t != null && !out.contains(t)) out.add(t);
    }
    return out;
  }

  static String? _trimmed(String? raw) {
    final t = raw?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
