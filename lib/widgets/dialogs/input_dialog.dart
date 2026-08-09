import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../glass/glass_dialog.dart';

class InputDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String initialValue;
  final String actionLabel;

  /// Above 1 the field grows into a text area and Enter inserts a newline
  /// instead of confirming — a synopsis is several paragraphs long.
  final int maxLines;

  const InputDialog({
    super.key,
    required this.title,
    required this.labelText,
    this.initialValue = '',
    required this.actionLabel,
    this.maxLines = 1,
  });

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return GlassAlertDialog(
      maxWidth: 568,
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: widget.maxLines > 1 ? 3 : null,
          maxLines: widget.maxLines,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.maxLines > 1
              ? null
              : (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
