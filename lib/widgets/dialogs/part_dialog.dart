import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class PartDialog extends StatefulWidget {
  const PartDialog({super.key});

  @override
  State<PartDialog> createState() => _PartDialogState();
}

class _PartDialogState extends State<PartDialog> {
  final TextEditingController _customPartController = TextEditingController();
  final List<String> _commonParts = ['1', '2', '3', '4'];

  @override
  void dispose() {
    _customPartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.selectPart),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: _commonParts.map((part) {
              return ElevatedButton(
                onPressed: () => Navigator.pop(context, part),
                child: Text('Part $part'),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customPartController,
            decoration: InputDecoration(
              labelText: l10n.customPart,
              hintText: 'e.g. 5',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                Navigator.pop(context, value);
              }
            },
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
            if (_customPartController.text.isNotEmpty) {
              Navigator.pop(context, _customPartController.text);
            }
          },
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}
