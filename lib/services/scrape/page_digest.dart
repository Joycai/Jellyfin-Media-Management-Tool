/// Reduces a page to what a model needs in order to *read* it.
///
/// The sibling of `HtmlCleaner`, and deliberately its opposite. `HtmlCleaner`
/// throws away text and keeps structure, because tier 3 asks for selectors.
/// This throws away structure and keeps text, because direct extraction asks
/// for values. Feeding the selector skeleton to a model that has been asked
/// "what is the title" would hand it a page with every string truncated to 80
/// characters.
///
/// Image URLs are collected separately and offered as a numbered list. A model
/// asked to invent a poster URL from prose will cheerfully produce one that
/// 404s; a model asked to *choose* from URLs that actually appear on the page
/// cannot.
library;

import 'package:html/dom.dart';

class PageDigest {
  /// Visible text, whitespace collapsed.
  final String text;

  /// Absolute image URLs found on the page, in document order.
  final List<String> images;

  const PageDigest({required this.text, required this.images});

  bool get isEmpty => text.isEmpty && images.isEmpty;

  /// Text budget. Generous next to the selector skeleton's 60 KB because prose
  /// is the payload here, but still bounded: a page that needs more than this
  /// is a listing, not a product page.
  static const defaultMaxChars = 40000;

  /// Enough to cover a poster plus a gallery of stills without letting a
  /// sprite-heavy page fill the prompt with interface chrome.
  static const defaultMaxImages = 60;

  /// Anything smaller than this in either dimension is an icon, a spacer or a
  /// tracking pixel — never artwork worth offering.
  static const _minDimension = 100;

  static const _dropTags = {
    'script',
    'style',
    'noscript',
    'svg',
    'template',
    'head',
    'iframe',
    'form',
    'select',
    'textarea',
    'button',
  };

  static final _imageExtension = RegExp(
    r'\.(jpe?g|png|webp|avif|gif|bmp)(\?|#|$)',
    caseSensitive: false,
  );

  /// Builds a digest of [document] with links resolved against [pageUrl].
  ///
  /// Works on a copy, so the caller's tree — which the recipe tiers may still
  /// be using — is never mutated.
  static PageDigest of(
    Document document,
    Uri pageUrl, {
    int maxChars = defaultMaxChars,
    int maxImages = defaultMaxImages,
  }) {
    final root = document.documentElement;
    if (root == null) return const PageDigest(text: '', images: []);

    final copy = root.clone(true);
    final images = _images(copy, pageUrl, maxImages);
    for (final element in copy.querySelectorAll(_dropTags.join(','))) {
      element.remove();
    }

    var text = _collapse(copy.text);
    if (text.length > maxChars) text = text.substring(0, maxChars);
    return PageDigest(text: text, images: images);
  }

  /// Collected before the strip pass, so an image inside a dropped container
  /// is still found — galleries live in all sorts of wrappers.
  static List<String> _images(Element root, Uri pageUrl, int limit) {
    final seen = <String>{};
    final out = <String>[];

    void add(String? raw) {
      if (out.length >= limit) return;
      final value = raw?.trim();
      if (value == null || value.isEmpty) return;
      if (value.startsWith('data:')) return;
      final resolved = pageUrl.resolve(value).toString();
      if (!_imageExtension.hasMatch(resolved)) return;
      if (seen.add(resolved)) out.add(resolved);
    }

    for (final img in root.querySelectorAll('img')) {
      if (_isTooSmall(img)) continue;
      add(img.attributes['src']);
      add(img.attributes['data-src']);
    }
    // Thumbnails routinely link to the full-size copy, which is the one worth
    // downloading, so anchors pointing at an image count too.
    for (final a in root.querySelectorAll('a')) {
      add(a.attributes['href']);
    }
    return out;
  }

  /// Only judges an image when it declares its own size — an absent attribute
  /// means unknown, not small.
  static bool _isTooSmall(Element img) {
    for (final name in const ['width', 'height']) {
      final value = int.tryParse(img.attributes[name] ?? '');
      if (value != null && value < _minDimension) return true;
    }
    return false;
  }

  static String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
