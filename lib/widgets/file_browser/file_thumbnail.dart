import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/file_entry.dart';
import '../../services/file_label_service.dart';
import '../../services/thumbnail_service.dart';

/// The leading tile of a file row: the type icon, upgraded to a video poster
/// frame once [ThumbnailService] has one.
///
/// Occupies a fixed [size] square in both states so a thumbnail arriving late
/// never reflows the row.
class FileThumbnail extends StatefulWidget {
  final FileEntry entry;

  /// Result of [FileLabelService.getLabel] for [entry], passed in because the
  /// caller has already computed it.
  final String label;
  final Color iconColor;
  final double size;

  /// Whether video thumbnails are switched on in Settings. When false this is
  /// just the icon tile.
  final bool enabled;

  const FileThumbnail({
    super.key,
    required this.entry,
    required this.label,
    required this.iconColor,
    required this.enabled,
    this.size = 34,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Uint8List? _bytes;

  /// Guards against a stale decode landing on a recycled row. `ListView`
  /// reuses [State] objects, so by the time a `Future` completes this widget
  /// may already be showing a different file.
  Object? _request;

  bool get _wantsThumbnail =>
      widget.enabled &&
      ThumbnailService.canThumbnail(widget.entry, widget.label);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.entry.modified != widget.entry.modified ||
        oldWidget.label != widget.label ||
        oldWidget.enabled != widget.enabled) {
      _resolve();
    }
  }

  /// Both call sites are immediately followed by a build, so the synchronous
  /// paths assign [_bytes] directly; only the async completion needs setState.
  void _resolve() {
    final request = Object();
    _request = request;

    if (!_wantsThumbnail) {
      _bytes = null;
      return;
    }

    // Synchronous hit keeps a scroll-back from flashing the icon for a frame.
    _bytes = ThumbnailService.instance.peek(widget.entry);
    if (_bytes != null) return;

    ThumbnailService.instance.thumbnailFor(widget.entry).then((bytes) {
      if (!mounted || _request != request || bytes == null) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: bytes == null ? _icon() : _poster(context, bytes),
      ),
    );
  }

  Widget _icon() {
    final isDir = widget.entry.isDirectory;
    return DecoratedBox(
      key: const ValueKey('icon'),
      decoration: BoxDecoration(
        color: widget.iconColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(
        child: Icon(
          FileLabelService.getIcon(widget.label, isDir),
          size: 18,
          color: widget.iconColor,
        ),
      ),
    );
  }

  Widget _poster(BuildContext context, Uint8List bytes) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      key: const ValueKey('poster'),
      borderRadius: BorderRadius.circular(9),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: widget.size,
        height: widget.size,
        // Decode at display resolution rather than the cached 320px source —
        // a folder of 500 videos would otherwise hold 500 full-size bitmaps.
        cacheWidth: (widget.size * ratio).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _icon(),
      ),
    );
  }
}
