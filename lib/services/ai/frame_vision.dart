/// Frame recognition: a few frames of a video, shown to a vision model, for
/// the videos whose file names say nothing (`VID_20230812.mp4`, a disc rip,
/// an episode with no number).
///
/// The model only describes what it reads on screen — a title card, an
/// episode caption, credits. What that makes the group is still the organize
/// model's decision, every path is still built by the app, and a group
/// decided after looking at frames is always flagged for review.
///
/// Frames leave this computer, so the feature is off until the user allows
/// it, and only a model allowed image input is ever sent one.
library;

import '../thumbnails/video_frames.dart';
import 'ai_cancel_token.dart';
import 'ai_provider.dart';

/// A frame lookup that produced nothing to read. Thrown rather than returned
/// so the caller cannot mistake it for on-screen text: only a real reading
/// flags later decisions for review.
class FramesUnavailable extends AiException {
  const FramesUnavailable(super.message);
}

/// Asks the vision model what a video's frames show.
class FrameVision {
  final AiProvider provider;
  final FrameSource frames;

  const FrameVision({required this.provider, required this.frames});

  static const prompt =
      'These are frames from one video file, in order. Report only what is '
      'written or shown on screen that identifies it: a title card, an '
      'episode title or number, a season, a year, channel or studio logos, '
      'credits. Quote on-screen text exactly as written, in its own language '
      'and script. Do not guess a title from the look of the scenes; if '
      'nothing on screen names it, say "nothing identifying on screen".';

  /// What the model reads off the frames of [path]. Throws
  /// [FramesUnavailable] when there is nothing to read.
  Future<String> identify(String path, {AiCancelToken? cancelToken}) async {
    final images = await frames.framesOf(path, cancelToken: cancelToken);
    if (images.isEmpty) {
      throw const FramesUnavailable(
        'No frames could be taken from this video.',
      );
    }
    final reply = await provider.chat(
      messages: [UserMessage(prompt, images: images)],
      tools: const [],
      cancelToken: cancelToken,
    );
    final text = reply.text.trim();
    if (text.isEmpty) {
      throw const FramesUnavailable('The vision model returned nothing.');
    }
    return text;
  }
}
