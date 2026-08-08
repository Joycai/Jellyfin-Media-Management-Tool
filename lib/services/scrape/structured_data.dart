/// Tier 1 of the scrape ladder: metadata the page already publishes for
/// machines — JSON-LD (`schema.org`) and OpenGraph. Costs no tokens and no
/// selectors, so it is always tried first for an unknown site.
///
/// **It is also the tier most likely to lie.** Plenty of sites emit one static
/// OpenGraph block for the whole domain; taking it at face value gives every
/// title in a library the same name, cover and synopsis — a failure mode far
/// worse than extracting nothing. [isSiteWideTemplate] is the guard, and it
/// runs before any value is accepted.
library;

import 'dart:convert';

import 'package:html/dom.dart';

import '../../models/media_metadata.dart';
import 'recipe_applier.dart' show normalizeWhitespace, RecipeApplier;
import 'scrape_transform.dart';

/// What the page published about itself, before validation.
class StructuredDataResult {
  /// `og:*` (and `twitter:*`) properties, keyed by their full name.
  final Map<String, String> openGraph;

  /// Every parsed `application/ld+json` object, flattened out of `@graph`.
  final List<Map<String, dynamic>> jsonLd;

  /// True when [openGraph] describes the site rather than this page.
  final bool siteWide;

  const StructuredDataResult({
    required this.openGraph,
    required this.jsonLd,
    required this.siteWide,
  });

  bool get isEmpty => openGraph.isEmpty && jsonLd.isEmpty;
}

class StructuredData {
  /// Schema.org types we know how to read as "one title".
  static const _knownTypes = {
    'Movie',
    'VideoObject',
    'TVEpisode',
    'CreativeWork',
    'Product',
  };

  /// Parses the machine-readable blocks out of [document] and decides whether
  /// they describe this page or the whole site.
  static StructuredDataResult inspect(Document document, Uri pageUrl) {
    final root = document.documentElement;
    if (root == null) {
      return const StructuredDataResult(
        openGraph: {},
        jsonLd: [],
        siteWide: false,
      );
    }

    // Read <meta> by attribute rather than by an attribute selector: the
    // property name lives in `property` on OpenGraph and in `name` on
    // Twitter cards, and doing it in Dart avoids depending on how much of
    // CSS attribute-selector syntax the parser supports.
    final og = <String, String>{};
    for (final meta in root.querySelectorAll('meta')) {
      final key = (meta.attributes['property'] ?? meta.attributes['name'])
          ?.trim()
          .toLowerCase();
      final content = meta.attributes['content'];
      if (key == null || content == null) continue;
      if (!key.startsWith('og:') && !key.startsWith('twitter:')) continue;
      final value = normalizeWhitespace(content);
      if (value.isNotEmpty) og.putIfAbsent(key, () => value);
    }

    final ld = <Map<String, dynamic>>[];
    for (final script in root.querySelectorAll('script')) {
      final type = script.attributes['type']?.trim().toLowerCase();
      if (type != 'application/ld+json') continue;
      final body = script.text;
      if (body.trim().isEmpty) continue;
      try {
        _flattenJsonLd(jsonDecode(body), ld);
      } on FormatException {
        // A malformed JSON-LD block is common and never fatal.
        continue;
      }
    }

    return StructuredDataResult(
      openGraph: og,
      jsonLd: ld,
      siteWide: isSiteWideTemplate(og, pageUrl),
    );
  }

  /// True when the OpenGraph block looks like a site-wide template rather than
  /// a description of [pageUrl].
  ///
  /// Two independent signals, either of which is enough:
  ///
  /// * `og:url` points somewhere other than this page — the single most
  ///   reliable tell, since a per-page block always self-references.
  /// * `og:title` is literally the site name.
  static bool isSiteWideTemplate(Map<String, String> og, Uri pageUrl) {
    final declared = og['og:url'];
    if (declared != null && declared.isNotEmpty) {
      try {
        final resolved = pageUrl.resolve(declared);
        if (resolved.path != pageUrl.path || resolved.query != pageUrl.query) {
          return true;
        }
      } on FormatException {
        return true; // unparseable og:url — do not trust the rest either
      }
    }
    final title = og['og:title'];
    final site = og['og:site_name'];
    if (title != null && site != null && title == site) return true;
    return false;
  }

  /// Builds metadata from [result], or returns null when there is nothing
  /// trustworthy to build from.
  ///
  /// JSON-LD wins over OpenGraph where both are present: it is typed, so
  /// `datePublished` really is a date, whereas `og:description` may be a
  /// marketing blurb.
  static MediaMetadata? toMetadata(
    StructuredDataResult result,
    Uri pageUrl, {
    bool allowSiteWide = false,
  }) {
    if (result.isEmpty) return null;
    final out = MediaMetadata(sourceUrl: pageUrl.toString());

    if (!result.siteWide || allowSiteWide) {
      _fromOpenGraph(result.openGraph, out, pageUrl);
    }
    for (final node in result.jsonLd) {
      _fromJsonLd(node, out, pageUrl);
    }
    return out.isEmpty ? null : out;
  }

  static void _fromOpenGraph(
    Map<String, String> og,
    MediaMetadata out,
    Uri pageUrl,
  ) {
    const origin = FieldOrigin.structuredData;
    out.set(MetadataField.title, og['og:title'], origin);
    out.set(MetadataField.plot, og['og:description'], origin);
    final image = og['og:image'] ?? og['twitter:image'];
    if (image != null) {
      out.set(
        MetadataField.poster,
        RecipeApplier.resolveUrl(pageUrl, image),
        origin,
      );
    }
    final released = og['og:video:release_date'] ?? og['video:release_date'];
    if (released != null) {
      out.set(
        MetadataField.premiered,
        ScrapeTransform.apply(released, 'date'),
        origin,
      );
    }
  }

  static void _fromJsonLd(
    Map<String, dynamic> node,
    MediaMetadata out,
    Uri pageUrl,
  ) {
    final types = _typesOf(node);
    if (types.isNotEmpty && !types.any(_knownTypes.contains)) return;
    const origin = FieldOrigin.structuredData;

    out.set(MetadataField.title, node['name'], origin);
    out.set(MetadataField.plot, node['description'], origin);
    out.set(
      MetadataField.premiered,
      ScrapeTransform.apply(
        (node['datePublished'] ?? node['dateCreated'] ?? '').toString(),
        'date',
      ),
      origin,
    );
    out.set(MetadataField.genres, node['genre'], origin);
    out.set(MetadataField.actors, _names(node['actor']), origin);
    final directors = _names(node['director']);
    if (directors.isNotEmpty) {
      out.set(MetadataField.director, directors.first, origin);
    }

    final image = node['image'];
    final imageUrl = image is List
        ? (image.isEmpty ? null : image.first)
        : image is Map
        ? image['url']
        : image;
    if (imageUrl != null) {
      out.set(
        MetadataField.poster,
        RecipeApplier.resolveUrl(pageUrl, imageUrl.toString()),
        origin,
      );
    }

    final rating = node['aggregateRating'];
    if (rating is Map) {
      out.set(MetadataField.rating, rating['ratingValue'], origin);
    }

    final publisher = node['publisher'] ?? node['productionCompany'];
    final publisherNames = _names(publisher);
    if (publisherNames.isNotEmpty) {
      out.set(MetadataField.studio, publisherNames.first, origin);
    }
  }

  /// `@type` can be a string or a list.
  static List<String> _typesOf(Map<String, dynamic> node) {
    final t = node['@type'];
    if (t is String) return [t];
    if (t is List) return t.map((e) => e.toString()).toList();
    return const [];
  }

  /// schema.org person-ish values come as a string, an object with `name`, or
  /// a list of either.
  static List<String> _names(Object? value) {
    if (value == null) return const [];
    if (value is String) {
      return value.trim().isEmpty ? const [] : [value.trim()];
    }
    if (value is Map) {
      final n = value['name'];
      return n == null ? const [] : _names(n);
    }
    if (value is List) {
      return [for (final e in value) ..._names(e)];
    }
    return const [];
  }

  /// JSON-LD may be a single object, a list, or a `@graph` wrapper.
  static void _flattenJsonLd(Object? decoded, List<Map<String, dynamic>> out) {
    if (decoded is List) {
      for (final e in decoded) {
        _flattenJsonLd(e, out);
      }
      return;
    }
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);
    final graph = map['@graph'];
    if (graph != null) {
      _flattenJsonLd(graph, out);
      return;
    }
    out.add(map);
  }
}
