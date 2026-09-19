import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/thumbnails/video_frames.dart';

void main() {
  test('a missing file gives no frames and never reaches a decoder', () async {
    expect(
      await VideoFrameExtractor().framesOf('/definitely/not/here.mp4'),
      isEmpty,
    );
  });

  test('frames are taken past the opening, at a legible size', () {
    expect(VideoFrameExtractor.offsets.first, greaterThan(0));
    expect(VideoFrameExtractor.edge, greaterThanOrEqualTo(512));
  });
}
