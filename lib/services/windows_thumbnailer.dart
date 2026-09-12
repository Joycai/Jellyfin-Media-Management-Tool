import 'dart:async';

import 'package:flutter/services.dart';

/// Windows poster-frame extraction over the runner's own channel.
///
/// `fc_native_video_thumbnail` does the work synchronously on the platform
/// thread on Windows, which is the thread pumping the window's message loop —
/// so a single video on a NAS stalls the whole window while it is read over
/// SMB (measured: 21ms to 46.6ms per frame on entering such a folder). The
/// runner answers this channel from a small worker pool instead; see
/// `windows/runner/thumbnail_channel.h`.
///
/// Only Windows has this. macOS and Linux keep the plugin, whose backends
/// already thread.
abstract final class WindowsThumbnailer {
  static const _channel = MethodChannel('jellyfin/thumbnail');

  /// A hung SMB read can occupy a worker indefinitely and there is no way to
  /// cancel a blocking Shell call. This does not free the worker — it frees
  /// the *row*, which falls back to its type icon instead of showing a
  /// placeholder forever.
  static const _timeout = Duration(seconds: 20);

  /// JPEG bytes for [path], or null when no thumbnail could be produced.
  ///
  /// Throws [MissingPluginException] when the running binary's runner predates
  /// this channel, which is the caller's signal to fall back to the plugin.
  static Future<Uint8List?> extract({
    required String path,
    required int edge,
    required int quality,
  }) {
    return _channel
        .invokeMethod<Uint8List>('extract', {
          'path': path,
          'edge': edge,
          'quality': quality,
        })
        .timeout(_timeout, onTimeout: () => null);
  }
}
