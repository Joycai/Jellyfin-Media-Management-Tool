import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/utils/format.dart';

void main() {
  group('formatBytes', () {
    test('returns the default zero string for non-positive input', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
    });

    test('honors a custom zero placeholder', () {
      expect(formatBytes(0, zero: '—'), '—');
    });

    test('bytes show no decimal', () {
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('KB shows one decimal under 100', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
    });

    test('values above 100 in their unit lose the decimal', () {
      // 100 KB → "100 KB", not "100.0 KB"
      expect(formatBytes(100 * 1024), '100 KB');
      expect(formatBytes(500 * 1024 * 1024), '500 MB');
    });

    test('crosses unit boundaries cleanly', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('caps at TB', () {
      final tb = 1024 * 1024 * 1024 * 1024;
      expect(formatBytes(tb), '1.0 TB');
      expect(formatBytes(tb * 1000), '1000 TB');
    });
  });
}
