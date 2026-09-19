import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/frame_vision.dart';
import 'package:jellyfin_media_management_tool/services/thumbnails/video_frames.dart';

import '../../helpers/ai.dart';

class _Frames implements FrameSource {
  final int count;
  const _Frames(this.count);

  @override
  Future<List<ImagePart>> framesOf(
    String path, {
    AiCancelToken? cancelToken,
  }) async => [
    for (var i = 0; i < count; i++)
      ImagePart(bytes: Uint8List.fromList([i, 1, 2])),
  ];
}

void main() {
  test('frames go to the vision model with the instruction', () async {
    final provider = ScriptedChatProvider([
      (_) => const ChatResult(text: ' Title card: "Summer Trip" '),
    ]);

    final seen = await FrameVision(
      provider: provider,
      frames: const _Frames(3),
    ).identify('/videos/a.mp4');

    expect(seen, 'Title card: "Summer Trip"');
    final message = provider.seen.single.single as UserMessage;
    expect(message.images, hasLength(3));
    expect(message.content, contains('on screen'));
  });

  test('no frames means no request', () async {
    final provider = ScriptedChatProvider([(_) => const ChatResult()]);
    final seen = await FrameVision(
      provider: provider,
      frames: const _Frames(0),
    ).identify('/videos/a.mp4');
    expect(provider.calls, 0);
    expect(seen, contains('No frames'));
  });
}
