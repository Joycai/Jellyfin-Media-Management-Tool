import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
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
    final file = widget.file as File;
    final oldName = p.basename(file.path);
    final newName = RenameService.getNewName(file, rule, extra: extra);

    if (oldName == newName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File already has this name')),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Rename'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to rename this file?'),
            const SizedBox(height: 16),
            const Text('From:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(oldName, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            const Text('To:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(newName, style: const TextStyle(color: Colors.green)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rename'),
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
            SnackBar(content: Text('Error renaming file: $e')),
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

    if (videoFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video files found in the same directory')),
      );
      return;
    }

    File selectedVideo = videoFiles.first;
    String selectedLang = _lastLangCode;
    bool isDefault = _lastIsDefault;
    final List<String> langCodes = ['chi', 'cht', 'jpn', 'eng'];

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Subtitle Naming'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<File>(
                  value: selectedVideo,
                  decoration: const InputDecoration(labelText: 'Target Video'),
                  items: videoFiles.map((v) {
                    return DropdownMenuItem(value: v, child: Text(p.basename(v.path), overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedVideo = val);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedLang,
                  decoration: const InputDecoration(labelText: 'Language Code'),
                  items: langCodes.map((code) {
                    return DropdownMenuItem(value: code, child: Text(code));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedLang = val);
                  },
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Default Subtitle'),
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
                child: const Text('Cancel'),
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
            title: const Text('TV Show Naming (SxxExx)'),
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
                child: const Text('Cancel'),
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
        title: const Text('Select Part Number'),
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
                labelText: 'Custom Part Number',
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (customPartController.text.isNotEmpty) {
                Navigator.pop(context, customPartController.text);
              }
            },
            child: const Text('Apply Custom'),
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
              const Text('Operations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      const PopupMenuItem(
                        value: RenameRule.matchFolder,
                        child: ListTile(
                          leading: Icon(Icons.folder_copy, color: Colors.blue),
                          title: Text('Match Folder Name'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: RenameRule.featurette,
                        child: ListTile(
                          leading: Icon(Icons.star, color: Colors.orange),
                          title: Text('Rename to Featurette'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: RenameRule.interview,
                        child: ListTile(
                          leading: Icon(Icons.mic, color: Colors.purple),
                          title: Text('Rename to Interview'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: RenameRule.part,
                        child: ListTile(
                          leading: Icon(Icons.segment, color: Colors.green),
                          title: Text('Rename to Part...'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: RenameRule.tvShow,
                        child: ListTile(
                          leading: Icon(Icons.tv, color: Colors.red),
                          title: Text('Rename to TV Show...'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (label == 'Subtitle')
                        const PopupMenuItem(
                          value: RenameRule.subtitle,
                          child: ListTile(
                            leading: Icon(Icons.subtitles, color: Colors.teal),
                            title: Text('Jellyfin Subtitle...'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                    child: ElevatedButton.icon(
                      onPressed: null,
                      style: buttonStyle.copyWith(
                        backgroundColor: MaterialStateProperty.all(Colors.blue.shade700),
                        foregroundColor: MaterialStateProperty.all(Colors.white),
                      ),
                      icon: const Icon(Icons.drive_file_rename_outline),
                      label: const Text('Rename File'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _openFile,
                    style: buttonStyle.copyWith(
                      backgroundColor: MaterialStateProperty.all(Colors.grey.shade800),
                      foregroundColor: MaterialStateProperty.all(Colors.white),
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(label == 'Video' ? 'Play Video' : 'Open File'),
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
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2),
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
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
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
                return Center(child: Text('Error loading file: ${snapshot.error}'));
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
              Text('No preview available for $label files', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
    }
  }
}
