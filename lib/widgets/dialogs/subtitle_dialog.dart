import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';

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

  /// BCP-47 codes, matching the AI prompt's `<VideoBaseName>.zh-Hans.ass`
  /// convention so AI-generated and manual filenames stay consistent.
  static const _langCodes = ['zh-Hans', 'zh-Hant', 'ja', 'en'];

  @override
  void initState() {
    super.initState();
    _selectedVideo = widget.videoFiles.first;
    _selectedLang = widget.initialLang;
    _isDefault = widget.initialDefault;
  }

  String _langLabel(AppLocalizations l10n, String code) => switch (code) {
    'zh-Hans' => l10n.subtitleLangZhHans,
    'zh-Hant' => l10n.subtitleLangZhHant,
    'ja' => l10n.subtitleLangJa,
    'en' => l10n.subtitleLangEn,
    _ => code,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return GlassAlertDialog(
      maxWidth: 420,
      title: Text(l10n.jellyfinSubtitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // isExpanded: the button sizes itself to its widest item otherwise,
          // and 'Traditional Chinese . zh-Hant' is wider than a 420px dialog
          // minus its padding -- the row overflowed by 150px on the right.
          DropdownButtonFormField<File>(
            // The theme's canvas is transparent for the glass backdrop; the
            // menu needs the same opaque fill as every other popup.
            dropdownColor: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.field),
            initialValue: _selectedVideo,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.video),
            items: widget.videoFiles.map((v) {
              return DropdownMenuItem(
                value: v,
                child: Text(
                  p.basename(v.path),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedVideo = val);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            // The theme's canvas is transparent for the glass backdrop; the
            // menu needs the same opaque fill as every other popup.
            dropdownColor: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.field),
            initialValue: _selectedLang,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.languageLabel),
            items: _langCodes.map((code) {
              return DropdownMenuItem(
                value: code,
                child: Text('${_langLabel(l10n, code)} · $code'),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedLang = val);
            },
          ),
          const SizedBox(height: 16),
          // A ListTile paints its background and its ink on the nearest
          // Material, and the glass dialog surface is a DecoratedBox with a
          // fill of its own -- so without a Material in between the splash is
          // invisible and the framework says so with an assertion the moment
          // the dialog opens.
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              title: Text(l10n.isDefault),
              value: _isDefault,
              onChanged: (val) {
                if (val != null) setState(() => _isDefault = val);
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
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
