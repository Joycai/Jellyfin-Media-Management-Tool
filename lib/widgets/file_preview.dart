import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import '../l10n/app_localizations.dart';
import '../services/file_label_service.dart';
import '../services/rename_service.dart';

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
        try {
          await _player!.open(Media(file.path), play: false);
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
            const Text('Are you sure?'),
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
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _showSubtitleDialog() async {
    if (widget.file is! File) return;
    final l10n = AppLocalizations.of(context)!;
    final file = widget.file as File;
    final parentDir = file.parent;
    final List<File> videoFiles = parentDir
        .listSync()
        .whereType<File>()
        .where((f) => FileLabelService.getLabel(p.extension(f.path)) == 'Video')
        .toList();

    if (videoFiles.isEmpty) return;

    File selectedVideo = videoFiles.first;
    String selectedLang = _lastLangCode;
    bool isDefault = _lastIsDefault;
    final List<String> langCodes = ['chi', 'cht', 'jpn', 'eng'];

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(l10n.jellyfinSubtitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<File>(
                  initialValue: selectedVideo,
                  decoration: const InputDecoration(labelText: 'Video'),
                  items: videoFiles.map((v) {
                    return DropdownMenuItem(value: v, child: Text(p.basename(v.path), overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedVideo = val);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedLang,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: langCodes.map((code) {
                    return DropdownMenuItem(value: code, child: Text(code));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedLang = val);
                  },
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Default'),
                  value: isDefault,
                  onChanged: (val) {
                    if (val != null) setDialogState(() => isDefault = val);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () {
                  final videoName = p.basenameWithoutExtension(selectedVideo.path);
                  final defaultPart = isDefault ? '.default' : '';
                  Navigator.pop(context, '$videoName.$selectedLang$defaultPart');
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() {
        _lastLangCode = selectedLang;
        _lastIsDefault = isDefault;
      });
      _handleRename(RenameRule.subtitle, extra: result);
    }
  }

  Future<void> _showTVShowDialog() async {
    int tempSeason = _lastSeason;
    int tempEpisode = _lastEpisode;

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String formatNum(int n) => n.toString().padLeft(2, '0');

          return AlertDialog(
            title: const Text('TV Show (SxxExx)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Season: '),
                    const Spacer(),
                    DropdownButton<int>(
                      value: tempSeason,
                      items: List.generate(11, (i) => i).map((i) {
                        return DropdownMenuItem(value: i, child: Text(formatNum(i)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => tempSeason = val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Episode: '),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: tempEpisode > 0 ? () => setDialogState(() => tempEpisode--) : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(formatNum(tempEpisode), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => setDialogState(() => tempEpisode++),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'S${formatNum(tempSeason)}E${formatNum(tempEpisode)}'),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() {
        _lastSeason = tempSeason;
        _lastEpisode = tempEpisode;
      });
      _handleRename(RenameRule.tvShow, extra: result);
    }
  }

  Future<void> _showPartDialog() async {
    final TextEditingController customPartController = TextEditingController();
    final List<String> commonParts = ['1', '2', '3', '4'];

    final String? selectedPart = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Part'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              children: commonParts.map((part) {
                return ElevatedButton(
                  onPressed: () => Navigator.pop(context, part),
                  child: Text('Part $part'),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: customPartController,
              decoration: const InputDecoration(
                labelText: 'Custom Part',
                hintText: 'e.g. 5',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (customPartController.text.isNotEmpty) {
                Navigator.pop(context, customPartController.text);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (selectedPart != null) {
      _handleRename(RenameRule.part, extra: selectedPart);
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
    final l10n = AppLocalizations.of(context)!;
    if (widget.file == null) {
      return const Center(child: Text('Select a file to preview'));
    }

    if (widget.file is Directory) {
      return const Center(child: Text('Directories cannot be previewed'));
    }

    final f = widget.file as File;
    final extension = p.extension(f.path);
    final label = FileLabelService.getLabel(extension);

    final buttonStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );

    return Column(
      children: [
        Expanded(
          child: _buildPreview(label, f),
        ),
        _buildMetadataInfo(),
        const Divider(),
        Padding(
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
                      PopupMenuItem(
                        value: RenameRule.matchFolder,
                        child: ListTile(
                          leading: const Icon(Icons.folder_copy, color: Colors.blue),
                          title: Text(l10n.matchFolderName),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: RenameRule.featurette,
                        child: ListTile(
                          leading: const Icon(Icons.star, color: Colors.orange),
                          title: Text(l10n.renameToFeaturette),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: RenameRule.interview,
                        child: ListTile(
                          leading: const Icon(Icons.mic, color: Colors.purple),
                          title: Text(l10n.renameToInterview),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: RenameRule.part,
                        child: ListTile(
                          leading: const Icon(Icons.segment, color: Colors.green),
                          title: Text(l10n.renameToPart),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: RenameRule.tvShow,
                        child: ListTile(
                          leading: const Icon(Icons.tv, color: Colors.red),
                          title: Text(l10n.renameToTVShow),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (label == 'Subtitle')
                        PopupMenuItem(
                          value: RenameRule.subtitle,
                          child: ListTile(
                            leading: const Icon(Icons.subtitles, color: Colors.teal),
                            title: Text(l10n.jellyfinSubtitle),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
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
        ),
      ],
    );
  }

  Widget _buildPreview(String label, File f) {
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
              Text('No preview available', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
    }
  }
}
