import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/file_label_service.dart';
import '../services/rename_service.dart';
import 'dialogs/subtitle_dialog.dart';
import 'dialogs/tv_show_dialog.dart';
import 'dialogs/part_dialog.dart';

class FilePreview extends StatefulWidget {
  final FileSystemEntity? file;
  final Function(FileSystemEntity)? onRenamed;

  const FilePreview({super.key, this.file, this.onRenamed});

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  Player? _player;
  Size? _imageSize;
  String _fileSize = '';
  Duration? _videoDuration;
  Size? _videoResolution;

  // State for TV Show renaming
  int _lastSeason = 1;
  int _lastEpisode = 1;

  // State for Subtitle renaming
  String _lastLangCode = 'chi';
  bool _lastIsDefault = false;

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
        _loadVideoMetadata(file.path);
      } else if (label == 'Image') {
        _loadImageMetadata(file);
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadVideoMetadata(String path) async {
    try {
      await _player!.open(Media(path), play: false);
      // Wait for metadata to be available
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _videoDuration = _player!.state.duration;
          _videoResolution = Size(
            _player!.state.width?.toDouble() ?? 0,
            _player!.state.height?.toDouble() ?? 0,
          );
        });
      }
    } catch (e) {
      debugPrint('Error getting video metadata: $e');
    }
  }

  Future<void> _loadImageMetadata(File file) async {
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
    final size = await completer.future;
    if (mounted) {
      setState(() {
        _imageSize = size;
      });
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

  Future<void> _handleRename(RenameRule rule, {String? extra}) async {
    if (widget.file is! File) return;
    final l10n = AppLocalizations.of(context)!;
    final file = widget.file as File;
    final oldName = p.basename(file.path);
    final newName = RenameService.getNewName(file, rule, extra: extra);

    if (oldName == newName) {
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmRename),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.areYouSure),
            const SizedBox(height: 16),
            Text(l10n.renameFrom, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(oldName, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Text(l10n.renameTo, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(newName, style: const TextStyle(color: Colors.green)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.rename),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final newFile = await RenameService.rename(file, newName);
        widget.onRenamed?.call(newFile);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorRenaming(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _showSubtitleDialog() async {
    if (widget.file is! File) return;
    final file = widget.file as File;
    final parentDir = file.parent;
    final List<File> videoFiles = parentDir
        .listSync()
        .whereType<File>()
        .where((f) => FileLabelService.getLabel(p.extension(f.path)) == 'Video')
        .toList();

    if (videoFiles.isEmpty) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SubtitleDialog(
        videoFiles: videoFiles,
        initialLang: _lastLangCode,
        initialDefault: _lastIsDefault,
      ),
    );

    if (result != null) {
      setState(() {
        _lastLangCode = result['lang'];
        _lastIsDefault = result['isDefault'];
      });
      _handleRename(RenameRule.subtitle, extra: result['result']);
    }
  }

  Future<void> _showTVShowDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => TVShowDialog(
        initialSeason: _lastSeason,
        initialEpisode: _lastEpisode,
      ),
    );

    if (result != null) {
      setState(() {
        _lastSeason = result['season'];
        _lastEpisode = result['episode'];
      });
      _handleRename(RenameRule.tvShow, extra: result['result']);
    }
  }

  Future<void> _showPartDialog() async {
    final selectedPart = await showDialog<String>(
      context: context,
      builder: (context) => const PartDialog(),
    );

    if (selectedPart != null) {
      _handleRename(RenameRule.part, extra: selectedPart);
    }
  }

  Widget _buildMetadataInfo(AppLocalizations l10n) {
    List<Widget> info = [
      Text(l10n.sizeLabel(_fileSize)),
    ];

    if (_videoDuration != null && _videoDuration != Duration.zero) {
      info.add(Text(l10n.durationLabel(_videoDuration.toString().split('.').first)));
      if (_videoResolution != null && _videoResolution!.width > 0) {
        info.add(Text(l10n.resolutionLabel('${_videoResolution!.width.toInt()}x${_videoResolution!.height.toInt()}')));
      }
    } else if (_imageSize != null) {
      info.add(Text(l10n.resolutionLabel('${_imageSize!.width.toInt()}x${_imageSize!.height.toInt()}')));
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
    final l10n = AppLocalizations.of(context)!;
    if (widget.file == null) {
      return Center(child: Text(l10n.selectFileToPreview));
    }

    if (widget.file is Directory) {
      return Center(child: Text(l10n.directoriesCannotBePreviewed));
    }

    final f = widget.file as File;
    final extension = p.extension(f.path);
    final label = FileLabelService.getLabel(extension);

    return Column(
      children: [
        Expanded(
          child: _buildPreview(label, f),
        ),
        _buildMetadataInfo(l10n),
        const Divider(),
        _buildOperations(l10n, label),
      ],
    );
  }

  Widget _buildOperations(AppLocalizations l10n, String label) {
    final buttonStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(l10n.operations, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PopupMenuButton<RenameRule>(
                onSelected: (rule) {
                  if (rule == RenameRule.part) {
                    _showPartDialog();
                  } else if (rule == RenameRule.tvShow) {
                    _showTVShowDialog();
                  } else if (rule == RenameRule.subtitle) {
                    _showSubtitleDialog();
                  } else {
                    _handleRename(rule);
                  }
                },
                offset: const Offset(0, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                itemBuilder: (context) => [
                  _buildPopupItem(RenameRule.matchFolder, Icons.folder_copy, Colors.blue, l10n.matchFolderName),
                  _buildPopupItem(RenameRule.featurette, Icons.star, Colors.orange, l10n.renameToFeaturette),
                  _buildPopupItem(RenameRule.interview, Icons.mic, Colors.purple, l10n.renameToInterview),
                  _buildPopupItem(RenameRule.part, Icons.segment, Colors.green, l10n.renameToPart),
                  _buildPopupItem(RenameRule.tvShow, Icons.tv, Colors.red, l10n.renameToTVShow),
                  if (label == 'Subtitle')
                    _buildPopupItem(RenameRule.subtitle, Icons.subtitles, Colors.teal, l10n.jellyfinSubtitle),
                ],
                child: ElevatedButton.icon(
                  onPressed: null,
                  style: buttonStyle.copyWith(
                    backgroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.primary),
                    foregroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.onPrimary),
                  ),
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: Text(l10n.renameFile),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _openFile,
                style: buttonStyle.copyWith(
                  backgroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.secondaryContainer),
                  foregroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.onSecondaryContainer),
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  label == 'Video' ? l10n.playVideo : l10n.openFile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<RenameRule> _buildPopupItem(RenameRule rule, IconData icon, Color color, String label) {
    return PopupMenuItem(
      value: rule,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildPreview(String label, File f) {
    final l10n = AppLocalizations.of(context)!;
    switch (label) {
      case 'Video':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_library, size: 120, color: Colors.blue),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  p.basename(f.path),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      case 'Image':
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            minScale: 0.1,
            maxScale: 5.0,
            child: Image.file(f, fit: BoxFit.contain),
          ),
        );
      case 'Subtitle':
      case 'Metadata':
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
          ),
          child: FutureBuilder<String>(
            future: f.readAsString(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    snapshot.data!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                );
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        );
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file, size: 100, color: Colors.grey),
              const SizedBox(height: 20),
              Text(l10n.noPreviewAvailable, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
    }
  }
}
