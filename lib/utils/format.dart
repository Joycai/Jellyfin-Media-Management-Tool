/// Formats a byte count as a short human string ("4.2 MB", "1 GB").
///
/// - Returns [zero] for non-positive inputs. The default `'0 B'` suits most
///   call sites; the preview dialog passes `'—'` when there's nothing yet to
///   report.
/// - Whole-byte values keep zero decimals; KB and above show one decimal,
///   except past 100 in the same unit where the integer is precise enough.
String formatBytes(int bytes, {String zero = '0 B'}) {
  if (bytes <= 0) return zero;
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int i = 0;
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 || i == 0 ? 0 : 1)} ${suffixes[i]}';
}
