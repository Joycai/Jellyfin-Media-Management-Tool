import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/scrape/media_code.dart';

void main() {
  group('detectMediaCode', () {
    test('reads a hyphenated code out of a decorated file name', () {
      expect(detectMediaCode('[GIGA]SPSF-43 (2026) 1080p.mkv'), 'SPSF-43');
    });

    test('normalizes separators and case', () {
      expect(detectMediaCode('spsf_43.mp4'), 'SPSF-43');
      expect(detectMediaCode('spsf 43.mp4'), 'SPSF-43');
      expect(detectMediaCode('abp00123.mkv'), 'ABP-00123');
    });

    test('keeps leading zeros — they are part of the catalogue number', () {
      expect(detectMediaCode('ABP-00123.mkv'), 'ABP-00123');
      expect(detectMediaCode('ABP-123.mkv'), 'ABP-123');
    });

    test('ignores the extension so .mp4 is never read as a code', () {
      expect(detectMediaCode('The.Movie.2019.mp4'), isNull);
    });

    test('is not fooled by codec and resolution tags', () {
      expect(detectMediaCode('Some.Film.1080p.x264-GROUP.mkv'), isNull);
      expect(detectMediaCode('Some.Film.2160p.HEVC.DDP5.1.mkv'), isNull);
    });

    test('returns null when there is nothing code-shaped', () {
      expect(detectMediaCode('holiday video.mov'), isNull);
      expect(detectMediaCode(''), isNull);
    });

    test('works on a folder name, which has no extension to strip', () {
      expect(detectMediaCode('SPSF-43'), 'SPSF-43');
    });
  });
}
