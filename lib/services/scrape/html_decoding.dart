/// Turning response bytes into a `String`.
///
/// This exists because `http.Response.body` gets it wrong for the pages we
/// care about: when a response carries no `charset`, the `http` package falls
/// back to **latin1**, which renders any Japanese page as mojibake. Product
/// pages routinely omit the header charset and declare it in a `<meta>` tag
/// instead, so the bytes have to be sniffed.
///
/// Kept separate from [PageFetcher] so the (fiddly, easy-to-regress) detection
/// can be unit-tested without a socket.
library;

import 'dart:convert';

/// Decodes bytes in an encoding the Dart core libraries do not ship.
typedef HtmlCodec = String Function(List<int> bytes);

/// A decoded page plus how it was decoded.
class DecodedHtml {
  final String html;

  /// Lower-case charset name that was actually applied.
  final String charset;

  /// True when the declared charset had no available codec and the bytes were
  /// force-decoded, so the text may contain replacement characters. Surfaced
  /// to the user rather than silently swallowed.
  final bool degraded;

  const DecodedHtml({
    required this.html,
    required this.charset,
    this.degraded = false,
  });
}

class HtmlDecoding {
  /// Extra codecs, keyed by lower-case charset name.
  ///
  /// Empty by default: every site supported so far serves UTF-8, and pulling
  /// in a multi-byte codec package for a hypothetical is not worth the
  /// dependency. To support a Shift_JIS or EUC-JP site, add `charset` to
  /// `pubspec.yaml` and register it here at startup — note that
  /// `enough_convert`, the package usually suggested for this, does **not**
  /// include the Japanese encodings.
  ///
  /// ```dart
  /// HtmlDecoding.codecs['shift_jis'] = (b) => ShiftJISCodec().decode(b);
  /// ```
  static final Map<String, HtmlCodec> codecs = {};

  /// How far into the body to look for a `<meta>` charset declaration. The
  /// HTML spec requires it inside the first 1024 bytes; real pages sometimes
  /// push it a little further, so this is deliberately generous.
  static const _sniffLimit = 4096;

  static final _headerCharset = RegExp(
    r'charset\s*=\s*"?([\w\-]+)"?',
    caseSensitive: false,
  );
  static final _metaCharset = RegExp(
    r'''<meta[^>]+charset\s*=\s*["']?\s*([\w\-]+)''',
    caseSensitive: false,
  );

  /// Decodes [bytes], preferring the charset from [contentType], then a
  /// `<meta>` declaration, then a BOM, then UTF-8.
  static DecodedHtml decode(List<int> bytes, {String? contentType}) {
    final bom = _charsetFromBom(bytes);
    final declared =
        charsetFromContentType(contentType) ?? charsetFromMeta(bytes) ?? bom;
    final charset = (declared ?? 'utf-8').toLowerCase();
    final body = _stripBom(bytes, charset);

    switch (charset) {
      case 'utf-8':
      case 'utf8':
      case 'us-ascii':
      case 'ascii':
        return DecodedHtml(
          html: const Utf8Decoder(allowMalformed: true).convert(body),
          charset: 'utf-8',
        );
      case 'iso-8859-1':
      case 'latin1':
      case 'latin-1':
      case 'windows-1252':
        return DecodedHtml(html: latin1.decode(body), charset: charset);
    }

    final extra = codecs[charset];
    if (extra != null) {
      return DecodedHtml(html: extra(body), charset: charset);
    }
    // Unknown multi-byte encoding and no codec registered. UTF-8 with
    // replacement characters at least keeps the ASCII markup intact so
    // selectors still match; `degraded` tells the UI to warn.
    return DecodedHtml(
      html: const Utf8Decoder(allowMalformed: true).convert(body),
      charset: charset,
      degraded: true,
    );
  }

  /// `text/html; charset=UTF-8` -> `utf-8`.
  static String? charsetFromContentType(String? contentType) {
    if (contentType == null) return null;
    final m = _headerCharset.firstMatch(contentType);
    return m?[1]?.toLowerCase();
  }

  /// Sniffs `<meta charset>` / `<meta http-equiv="Content-Type">` out of the
  /// head of the document. Reads the prefix as latin1 so every byte maps to a
  /// character and the ASCII markup is guaranteed readable whatever the real
  /// encoding turns out to be.
  static String? charsetFromMeta(List<int> bytes) {
    final head = bytes.length > _sniffLimit
        ? bytes.sublist(0, _sniffLimit)
        : bytes;
    final text = latin1.decode(head, allowInvalid: true);
    final m = _metaCharset.firstMatch(text);
    return m?[1]?.toLowerCase();
  }

  static String? _charsetFromBom(List<int> b) {
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return 'utf-8';
    }
    return null;
  }

  static List<int> _stripBom(List<int> b, String charset) {
    if ((charset == 'utf-8' || charset == 'utf8') &&
        b.length >= 3 &&
        b[0] == 0xEF &&
        b[1] == 0xBB &&
        b[2] == 0xBF) {
      return b.sublist(3);
    }
    return b;
  }
}
