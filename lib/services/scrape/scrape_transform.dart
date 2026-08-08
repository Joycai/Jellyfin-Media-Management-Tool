/// The tiny transform language recipes use to turn page text into typed values.
///
/// Deliberately small and total: every transform either produces a value or
/// returns null, and an unknown/ malformed spec is a no-op rather than an
/// error. Recipes are user- and LLM-authored data, so a bad transform must
/// degrade to "field not extracted", never to a crash.
///
/// Grammar (the part after `transform:` in a recipe):
///
/// | spec                | result                                              |
/// |---------------------|-----------------------------------------------------|
/// | `text` / absent     | the string unchanged                                |
/// | `int`               | `int`, or null                                      |
/// | `double`            | `double`, or null                                   |
/// | `date`              | ISO `yyyy-MM-dd` from the first Y/M/D triple        |
/// | `regex:<pattern>`   | first capture group as `String`                     |
/// | `regexInt:<pattern>`| first capture group as `int`                        |
///
/// `date` is pattern-free on purpose: one implementation handles `2026/08/14`,
/// `2026-08-14` and `2026年8月14日` alike, which is strictly more robust than
/// asking an LLM to name the right format string.
library;

class ScrapeTransform {
  /// Any run of non-digits between the three date components. Anchored to a
  /// 4-digit year so a product code like `SPSF-43` can never be read as a date.
  static final _date = RegExp(r'(\d{4})\D{1,3}(\d{1,2})\D{1,3}(\d{1,2})');

  /// Digits with an optional decimal part, used by `int` / `double`.
  static final _number = RegExp(r'-?\d+(?:\.\d+)?');

  /// Applies [spec] to [raw]. Returns null when the transform cannot produce a
  /// value, which the caller treats as "field not extracted".
  static Object? apply(String raw, String? spec) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (spec == null || spec.isEmpty || spec == 'text') return value;

    final colon = spec.indexOf(':');
    final name = colon == -1 ? spec : spec.substring(0, colon);
    final arg = colon == -1 ? null : spec.substring(colon + 1);

    switch (name) {
      case 'int':
        return _asInt(value);
      case 'double':
        return _asDouble(value);
      case 'date':
        return _asIsoDate(value);
      case 'regex':
        return _capture(value, arg);
      case 'regexInt':
        final c = _capture(value, arg);
        return c == null ? null : _asInt(c);
      default:
        // Unknown transform: pass the raw text through rather than dropping
        // the field. A typo in a recipe should degrade, not delete.
        return value;
    }
  }

  static int? _asInt(String value) {
    final m = _number.firstMatch(value);
    if (m == null) return null;
    return int.tryParse(m[0]!) ?? double.tryParse(m[0]!)?.round();
  }

  static double? _asDouble(String value) {
    final m = _number.firstMatch(value);
    return m == null ? null : double.tryParse(m[0]!);
  }

  /// Normalizes the first plausible date in [value] to ISO `yyyy-MM-dd`.
  /// Rejects impossible month/day values so a run of digits cannot masquerade
  /// as a date.
  static String? _asIsoDate(String value) {
    final m = _date.firstMatch(value);
    if (m == null) return null;
    final month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return '${m[1]}-${_two(month)}-${_two(day)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// First capture group of [pattern] (or the whole match when the pattern has
  /// no groups). An invalid pattern yields null instead of throwing.
  static String? _capture(String value, String? pattern) {
    if (pattern == null || pattern.isEmpty) return null;
    RegExp re;
    try {
      re = RegExp(pattern);
    } on FormatException {
      return null;
    }
    final m = re.firstMatch(value);
    if (m == null) return null;
    final g = m.groupCount >= 1 ? m[1] : m[0];
    final t = g?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
