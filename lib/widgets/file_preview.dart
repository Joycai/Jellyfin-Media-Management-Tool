import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import '../services/file_label_service.dart';

class FilePreview extends StatefulWidget {
  final FileSystemEntity? file;

  const FilePreview({super.key, this.file});

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  Player? _player;
  Size? _imageSize;
  String _fileSize = '';
  Duration? _videoDuration;
  Size? _videoResolution;

  @override
  void didUpdateWidget(FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file != oldWidget.file) {
      _loadMetadata();
    }
  }

  @override
  void initState() {
    super.initState();
    _player = Player();
    _loadMetadata();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    _imageSize = null;
    _fileSize = '';
    _videoDuration = null;
    _videoResolution = null;

    if (widget.file is File) {
      final file = widget.file as File;
      final stat = await file.stat();
      _fileSize = _formatBytes(stat.size);

      final extension = p.extension(file.path);
      final label = FileLabelService.getLabel(extension);

      if (label == 'Video') {
        try {
          await _player!.open(Media(file.path), play: false);
          // Wait a bit for metadata to be loaded
          await Future.delayed(const Duration(milliseconds: 500));
          _videoDuration = _player!.state.duration;
          _videoResolution = Size(
            _player!.state.width?.toDouble() ?? 0,
            _player!.state.height?.toDouble() ?? 0,
          );
        } catch (e) {
          debugPrint('Error getting video metadata: $e');
        }
      } else if (label == 'Image') {
        final Completer<Size> completer = Completer();
        final Image image = Image.file(file);
        image.image.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((ImageInfo info, bool _) {
            if (!completer.isCompleted) {
              completer.complete(Size(
                info.image.width.toDouble(),
                info.image.height.toDouble(),
              ));
            }
          }),
        );
        _imageSize = await completer.future;
      }
      if (mounted) setState(() {});
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < suffixes.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return "${size.toStringAsFixed(2)} ${suffixes[unitIndex]}";
  }

  Future<void> _openFile() async {
    if (widget.file != null) {
      final Uri uri = Uri.file(widget.file!.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Widget _buildMetadataInfo() {
    List<Widget> info = [
      Text('Size: $_fileSize'),
    ];

    if (_videoDuration != null && _videoDuration != Duration.zero) {
      info.add(Text('Duration: ${_videoDuration.toString().split('.').first}'));
      if (_videoResolution != null && _videoResolution!.width > 0) {
        info.add(Text('Resolution: ${_videoResolution!.width.toInt()}x${_videoResolution!.height.toInt()}'));
      }
    } else if (_imageSize != null) {
      info.add(Text('Resolution: ${_imageSize!.width.toInt()}x${_imageSize!.height.toInt()}'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: info,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file == null) {
      return const Center(child: Text('Select a file to preview'));
    }

    if (widget.file is Directory) {
      return const Center(child: Text('Directories cannot be previewed'));
    }

    final f = widget.file as File;
    final extension = p.extension(f.path);
    final label = FileLabelService.getLabel(extension);

    switch (label) {
      case 'Video':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_library, size: 100, color: Colors.blue),
              const SizedBox(height: 20),
              Text(p.basename(f.path), style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              _buildMetadataInfo(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Open in System Player'),
              ),
            ],
          ),
        );
      case 'Image':
        return Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.1,
                maxScale: 5.0,
                child: Image.file(f),
              ),
            ),
            _buildMetadataInfo(),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in System Viewer'),
              ),
            ),
          ],
        );
      case 'Subtitle':
      case 'Metadata':
        return Column(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: f.readAsString(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(snapshot.data!),
                    );
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error loading file: ${snapshot.error}'));
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
            _buildMetadataInfo(),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.edit),
                label: const Text('Open in System Editor'),
              ),
            ),
          ],
        );
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file, size: 100, color: Colors.grey),
              const SizedBox(height: 20),
              Text('No preview available for $label files'),
              _buildMetadataInfo(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open with System App'),
              ),
            ],
          ),
        );
    }
  }
}
