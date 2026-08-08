/// Request cookies for scraping, from two sources:
///
/// 1. the static string in a recipe (an age-gate flag like `old_check=yes`) —
///    this covers most sites and needs no user action;
/// 2. a `cookies.txt` the user exported from their browser — the fallback for
///    sites that insist on a real session.
///
/// Pure and in-memory on purpose. Cookies exported from a browser can include
/// session identifiers that are equivalent to being logged in, so persisting
/// them is a decision for the owning service to make explicitly (and to guard
/// like `ai_profiles.json`), not something this layer does behind your back.
library;

/// One line of a Netscape `cookies.txt`.
class NetscapeCookie {
  /// Host, without any leading dot.
  final String domain;

  /// The leading-dot / `TRUE` flag: send to sub-domains too.
  final bool includeSubdomains;
  final String path;
  final bool secureOnly;

  /// Unix seconds; `0` means a session cookie (no expiry).
  final int expiresAt;
  final String name;
  final String value;

  const NetscapeCookie({
    required this.domain,
    required this.includeSubdomains,
    required this.path,
    required this.secureOnly,
    required this.expiresAt,
    required this.name,
    required this.value,
  });

  bool isExpired(DateTime now) =>
      expiresAt != 0 && expiresAt * 1000 <= now.millisecondsSinceEpoch;

  /// Whether this cookie should be sent with a request to [url].
  bool matches(Uri url, {required DateTime now}) {
    if (isExpired(now)) return false;
    if (secureOnly && url.scheme != 'https') return false;

    final host = url.host.toLowerCase();
    if (includeSubdomains) {
      if (host != domain && !host.endsWith('.$domain')) return false;
    } else if (host != domain) {
      return false;
    }

    final requestPath = url.path.isEmpty ? '/' : url.path;
    if (path == '/' || path.isEmpty) return true;
    return requestPath == path || requestPath.startsWith('$path/');
  }

  @override
  String toString() => '$name=$value';
}

class CookieStore {
  final List<NetscapeCookie> _cookies;

  CookieStore([List<NetscapeCookie>? cookies])
    : _cookies = List.of(cookies ?? const []);

  List<NetscapeCookie> get cookies => List.unmodifiable(_cookies);

  bool get isEmpty => _cookies.isEmpty;

  /// Replaces everything stored for the hosts present in [cookies].
  /// Re-importing a fresh export therefore supersedes the stale one instead of
  /// piling a second copy of every cookie on top.
  void importAll(List<NetscapeCookie> cookies) {
    final domains = cookies.map((c) => c.domain).toSet();
    _cookies.removeWhere((c) => domains.contains(c.domain));
    _cookies.addAll(cookies);
  }

  void clearDomain(String domain) {
    final bare = _bare(domain);
    _cookies.removeWhere((c) => c.domain == bare);
  }

  void clear() => _cookies.clear();

  /// The `Cookie:` header value for [url].
  ///
  /// Three sources, applied in increasing order of precedence:
  ///
  /// 1. [staticCookies] — the recipe's own string, the same for every user;
  /// 2. [sessionCookies] — what the server handed *this run* in response to a
  ///    recipe's `sessionUrl`, which is fresher than any constant;
  /// 3. the browser-exported cookies held here, which win outright: if the
  ///    user went to the trouble of importing a signed-in session, an
  ///    anonymous one we minted ourselves must not displace it.
  ///
  /// Returns an empty string when there is nothing to send, so callers can
  /// skip the header entirely.
  String headerFor(
    Uri url, {
    String? staticCookies,
    Map<String, String>? sessionCookies,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final merged = <String, String>{};

    for (final pair in (staticCookies ?? '').split(';')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      if (name.isEmpty) continue;
      merged[name] = pair.substring(eq + 1).trim();
    }
    if (sessionCookies != null) merged.addAll(sessionCookies);
    for (final c in _cookies) {
      if (c.matches(url, now: at)) merged[c.name] = c.value;
    }

    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Parses the `name=value` out of one `Set-Cookie` header.
  ///
  /// Attributes after the first `;` are deliberately dropped: these cookies are
  /// held per host for the length of a run, so `Path`, `Expires` and `Domain`
  /// have nothing to scope. A `Max-Age=0` deletion is honoured by returning an
  /// empty value, which callers treat as a removal.
  static MapEntry<String, String>? parseSetCookie(String header) {
    final parts = header.split(';');
    final eq = parts.first.indexOf('=');
    if (eq <= 0) return null;
    final name = parts.first.substring(0, eq).trim();
    if (name.isEmpty) return null;
    return MapEntry(name, parts.first.substring(eq + 1).trim());
  }

  /// Parses a Netscape/curl `cookies.txt`.
  ///
  /// Tolerant by design — this file is hand-exported by the user, so a stray
  /// blank line or a short row is skipped rather than raised. Lines prefixed
  /// `#HttpOnly_` are real cookies wearing a comment marker; everything else
  /// starting with `#` is a comment.
  static List<NetscapeCookie> parseNetscape(String text) {
    const httpOnly = '#HttpOnly_';
    final out = <NetscapeCookie>[];

    for (var line in text.split(RegExp(r'\r?\n'))) {
      line = line.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.startsWith(httpOnly)) {
        line = line.substring(httpOnly.length);
      } else if (line.startsWith('#')) {
        continue;
      }

      final parts = line.split('\t');
      // 7 fields; a trailing empty value is legal, a missing one is not.
      if (parts.length < 7) continue;
      final name = parts[5].trim();
      if (name.isEmpty) continue;

      out.add(
        NetscapeCookie(
          domain: _bare(parts[0]),
          includeSubdomains:
              parts[0].startsWith('.') ||
              parts[1].trim().toUpperCase() == 'TRUE',
          path: parts[2].trim().isEmpty ? '/' : parts[2].trim(),
          secureOnly: parts[3].trim().toUpperCase() == 'TRUE',
          expiresAt: int.tryParse(parts[4].trim()) ?? 0,
          name: name,
          // Values can legitimately contain '=' and spaces; take the rest of
          // the line verbatim rather than re-splitting it.
          value: parts.sublist(6).join('\t'),
        ),
      );
    }
    return out;
  }

  /// Serializes back to `cookies.txt`, so an import can be round-tripped and
  /// inspected. Session cookies keep their `0` expiry.
  static String toNetscape(List<NetscapeCookie> cookies) {
    final b = StringBuffer()
      ..writeln('# Netscape HTTP Cookie File')
      ..writeln('# Written by Jellyfin Media Management Tool');
    for (final c in cookies) {
      b.writeln(
        [
          c.includeSubdomains ? '.${c.domain}' : c.domain,
          c.includeSubdomains ? 'TRUE' : 'FALSE',
          c.path,
          c.secureOnly ? 'TRUE' : 'FALSE',
          '${c.expiresAt}',
          c.name,
          c.value,
        ].join('\t'),
      );
    }
    return b.toString();
  }

  static String _bare(String domain) {
    var d = domain.trim().toLowerCase();
    while (d.startsWith('.')) {
      d = d.substring(1);
    }
    return d;
  }
}
