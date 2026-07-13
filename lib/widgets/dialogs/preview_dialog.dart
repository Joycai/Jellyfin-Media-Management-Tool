import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../services/file_label_service.dart';
import '../../utils/format.dart';

/// Quick-look style preview for image and video files, opened by
/// double-clicking a row in the file table. Esc / the close button dismiss it.
///
/// Images render with [Image.file] inside an [InteractiveViewer] (pinch/scroll
/// zoom); videos play inline through media_kit's libmpv backend.
class PreviewDialog extends StatefulWidget {
  final FileEntry entry;

  const PreviewDialog({super.key, required this.entry});

  /// Whether [entry] is a file type this dialog can render.
  static bool canPreview(FileEntry entry) {
    if (entry.isDirectory) return false;
    final label = FileLabelService.getLabel(entry.extension);
    return label == 'Image' || label == 'Video';
  }

  static Future<void> show(BuildContext context, FileEntry entry) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => PreviewDialog(entry: entry),
    );
  }

  @override
  State<PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<PreviewDialog> {
  Player? _player;
  VideoController? _videoController;

  bool get _isVideo =>
      FileLabelService.getLabel(widget.entry.extension) == 'Video';

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      final player = Player();
      _player = player;
      _videoController = VideoController(player);
      player.open(Media(widget.entry.path));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width * 0.8,
          maxHeight: size.height * 0.85,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: const Color(0xFF17181C),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleBar(entry: widget.entry),
                Flexible(child: _isVideo ? _video() : _image(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _video() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Video(controller: _videoController!),
    );
  }

  Widget _image(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InteractiveViewer(
      maxScale: 8,
      child: Image.file(
        File(widget.entry.path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Colors.white38,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.noPreviewAvailable,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  final FileEntry entry;
  const _TitleBar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final label = FileLabelService.getLabel(entry.extension);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: Colors.white.withValues(alpha: 0.04),
      child: Row(
        children: [
          Icon(
            FileLabelService.getIcon(label, false),
            size: 18,
            color: Colors.white70,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatBytes(entry.size),
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
