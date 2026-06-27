import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Prompts the user for an optional title hint (e.g. "Dune", "Stranger Things")
/// to feed into the AI prompt before analyzing a folder. Returns:
///   - the trimmed hint string when the user confirms (may be empty),
///   - `null` when the user cancels — caller should abort the analyze flow.
Future<String?> showTitleHintDialog(
  BuildContext context, {
  required String folderName,
}) {
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.aiHintTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiHintSubtitle,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
                decoration: InputDecoration(
                  labelText: l10n.aiHintLabel,
                  hintText: l10n.aiHintPlaceholder(folderName),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: Text(l10n.aiHintSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(l10n.aiHintAnalyze),
          ),
        ],
      );
    },
  );
}
