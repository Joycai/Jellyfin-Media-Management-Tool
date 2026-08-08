/// Recovers a product / catalogue code from a file or folder name.
///
/// Only a hint: the scrape dialog uses it to pre-fill the search buttons so the
/// user does not retype `SPSF-43` by hand. Nothing downstream depends on it
/// being right, which is why a miss returns null rather than guessing harder.
library;

/// Letters then digits, optionally separated. Anchored on non-alphanumerics so
/// `SPSF-43` matches inside `[GIGA]SPSF-43 (2026).mkv` but the `264` of `x264`
/// cannot pick up the preceding word.
final _codePattern = RegExp(
  r'(?<![A-Za-z0-9])([A-Za-z]{2,6})[-_ ]?(\d{2,5})(?![A-Za-z0-9])',
);

/// Release-tag noise that happens to fit the shape above. Matching one of these
/// is far more likely than a real code that collides with it.
const _notCodes = {
  'x264',
  'x265',
  'h264',
  'h265',
  'avc1',
  'hevc',
  'aac2',
  'ac3',
  'dts',
  'mp4',
  'mkv',
  'avi',
  'wmv',
  'flac',
  'ma5',
  'ddp5',
  'dd5',
};

/// The first plausible code in [name], normalized to `LETTERS-DIGITS`, or null.
///
/// The extension is stripped first so `.mp4` cannot be read as a code, and
/// leading zeros are kept — `ABP-00123` and `ABP-123` are different catalogue
/// numbers on some labels.
String? detectMediaCode(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;

  for (final match in _codePattern.allMatches(stem)) {
    final letters = match.group(1)!.toUpperCase();
    final digits = match.group(2)!;
    if (_notCodes.contains('$letters$digits'.toLowerCase())) continue;
    if (_notCodes.contains(letters.toLowerCase())) continue;
    return '$letters-$digits';
  }
  return null;
}
