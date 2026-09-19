/// Several frames of one video, for frame recognition — the thumbnailers
/// the file table uses, asked for more than one position and a larger edge.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../ai/ai_cancel_token.dart';
import '../ai/chat.dart' show ImagePart;
import 'windows_thumbnailer.dart';

/// Where frames come from; a fake in tests.
abstract interface class FrameSource {
  /// JPEG frames of the video at [path], possibly none. Stops between
  /// frames once [cancelToken] is cancelled.
  Future<List<ImagePart>> framesOf(String path, {AiCancelToken? cancelToken});
}

/// Frames through the platform thumbnailers the file table already uses.
///
/// Titles sit near the start (a title card, an opening caption) and credits
/// near the end, but the duration is unknown without a media probe, so the
/// frames are taken at fixed offsets from the start; offsets past the end of
/// a short clip simply produce nothing. Windows' Shell thumbnailer takes no
/// timestamp, so there it is one frame.
class VideoFrameExtractor implements FrameSource {
  VideoFrameExtractor({FcNativeVideoThumbnail? plugin})
    : _plugin = plugin ?? FcNativeVideoThumbnail();

  final FcNativeVideoThumbnail _plugin;

  /// Seconds into the video.
  static const offsets = [20, 90, 300, 900];

  /// Longest edge: large enough for on-screen text to stay legible, small
  /// enough that four frames stay a modest request.
  static const edge = 768;
  static const quality = 80;

  /// A decoder that hangs on a corrupt or remote file must not hold the
  /// analysis: each frame gets this long.
  static const frameTimeout = Duration(seconds: 20);

  /// Latched once the runner turns out to predate the thumbnail channel, as
  /// [ThumbnailService] does.
  static bool _nativeChannel = Platform.isWindows;

  @override
  Future<List<ImagePart>> framesOf(
    String path, {
    AiCancelToken? cancelToken,
  }) async {
    if (!await File(path).exists()) return const [];
    cancelToken?.throwIfCancelled();
    if (_nativeChannel) {
      try {
        final bytes = await WindowsThumbnailer.extract(
          path: path,
          edge: edge,
          quality: quality,
        );
        return bytes == null || bytes.isEmpty
            ? const []
            : [ImagePart(bytes: bytes, mimeType: 'image/jpeg')];
      } on MissingPluginException {
        // An older runner: fall through to the plugin, from now on.
        _nativeChannel = false;
      }
    }
    final frames = <ImagePart>[];
    final seen = <int>{};
    for (final seconds in offsets) {
      cancelToken?.throwIfCancelled();
      Uint8List? bytes;
      try {
        bytes = await _plugin
            .saveThumbnailToBytes(
              srcFile: path,
              width: edge,
              height: edge,
              quality: quality,
              at: FcVideoThumbnailTime(
                seconds,
                FcVideoThumbnailTimeUnit.seconds,
              ),
            )
            .timeout(frameTimeout, onTimeout: () => null);
      } catch (_) {
        // Past the end of the clip, or undecodable: no frame here.
        continue;
      }
      if (bytes == null || bytes.isEmpty) continue;
      // A backend that ignores the timestamp returns the same frame each
      // time; one copy is enough.
      if (!seen.add(Object.hashAll(bytes))) continue;
      frames.add(ImagePart(bytes: bytes, mimeType: 'image/jpeg'));
    }
    return frames;
  }
}
