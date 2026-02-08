import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';

class SubtitleDialog extends StatefulWidget {
  final List<File> videoFiles;
  final String initialLang;
  final bool initialDefault;

  const SubtitleDialog({
    super.key,
    required this.videoFiles,
    required this.initialLang,
    required this.initialDefault,
  });

  @override
  State<SubtitleDialog> createState() => _SubtitleDialogState();
}

class _SubtitleDialogState extends State<SubtitleDialog> {
  late File _selectedVideo;
  late String _selectedLang;
  late bool _isDefault;
  final List<String> _langCodes = ['chi', 'cht', 'jpn', 'eng'];

  @override
  void initState() {
    super.initState();
    _selectedVideo = widget.videoFiles.first;
    _selectedLang = widget.initialLang;
    _isDefault = widget.initialDefault;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.jellyfinSubtitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<File>(
            initialValue: _selectedVideo,
            decoration: InputDecoration(labelText: l10n.video),
            items: widget.videoFiles.map((v) {
              return DropdownMenuItem(
                value: v,
                child: Text(p.basename(v.path), overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedVideo = val);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedLang,
            decoration: InputDecoration(labelText: l10n.languageLabel),
            items: _langCodes.map((code) {
              return DropdownMenuItem(value: code, child: Text(code));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedLang = val);
            },
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: Text(l10n.isDefault),
            value: _isDefault,
            onChanged: (val) {
              if (val != null) setState(() => _isDefault = val);
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
            final videoName = p.basenameWithoutExtension(_selectedVideo.path);
            final defaultPart = _isDefault ? '.default' : '';
            Navigator.pop(context, {
              'result': '$videoName.$_selectedLang$defaultPart',
              'lang': _selectedLang,
              'isDefault': _isDefault,
            });
          },
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}
