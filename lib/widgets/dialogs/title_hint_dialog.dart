import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What the user tells us this folder contains. The model treats `movie` /
/// `series` as a hard hint and skips its own media-type guess. `auto` means
/// "decide for me from the filenames" — the previous default.
enum MediaKindHint { auto, movie, series }

/// Outcome of [showTitleHintDialog]. `kind` is always set; `title` may be empty
/// when the user picked **Skip** or didn't type anything. Callers should treat
/// `kind == auto && title.isEmpty` as "no hint at all".
class TitleHintResult {
  final MediaKindHint kind;
  final String title;
  const TitleHintResult({required this.kind, required this.title});
}

/// Prompts for an optional media-type + title hint before AI analysis. Returns
/// the result on confirm, or `null` when the user cancels — the caller should
/// then abort the analyze flow.
Future<TitleHintResult?> showTitleHintDialog(
  BuildContext context, {
  required String folderName,
}) {
  return showDialog<TitleHintResult>(
    context: context,
    builder: (_) => _TitleHintDialog(folderName: folderName),
  );
}

class _TitleHintDialog extends StatefulWidget {
  final String folderName;
  const _TitleHintDialog({required this.folderName});

  @override
  State<_TitleHintDialog> createState() => _TitleHintDialogState();
}

class _TitleHintDialogState extends State<_TitleHintDialog> {
  final _controller = TextEditingController();
  MediaKindHint _kind = MediaKindHint.auto;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit({bool skip = false}) {
    Navigator.pop(
      context,
      TitleHintResult(
        kind: _kind,
        title: skip ? '' : _controller.text.trim(),
      ),
    );
  }

  String _labelFor(AppLocalizations l10n) => switch (_kind) {
        MediaKindHint.movie => l10n.aiHintLabelMovie,
        MediaKindHint.series => l10n.aiHintLabelSeries,
        MediaKindHint.auto => l10n.aiHintLabel,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n.aiHintTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiHintSubtitle,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.aiHintKindLabel,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _KindChip(
                  label: l10n.aiHintKindAuto,
                  icon: Icons.auto_awesome,
                  selected: _kind == MediaKindHint.auto,
                  onTap: () => setState(() => _kind = MediaKindHint.auto),
                ),
                _KindChip(
                  label: l10n.aiHintKindMovie,
                  icon: Icons.movie_outlined,
                  selected: _kind == MediaKindHint.movie,
                  onTap: () => setState(() => _kind = MediaKindHint.movie),
                ),
                _KindChip(
                  label: l10n.aiHintKindSeries,
                  icon: Icons.live_tv_outlined,
                  selected: _kind == MediaKindHint.series,
                  onTap: () => setState(() => _kind = MediaKindHint.series),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _labelFor(l10n),
                hintText: l10n.aiHintPlaceholder(widget.folderName),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => _submit(skip: true),
          child: Text(l10n.aiHintSkip),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.aiHintAnalyze),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _KindChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      showCheckmark: false,
    );
  }
}
