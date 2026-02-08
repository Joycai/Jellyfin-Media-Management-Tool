import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class TVShowDialog extends StatefulWidget {
  final int initialSeason;
  final int initialEpisode;

  const TVShowDialog({
    super.key,
    required this.initialSeason,
    required this.initialEpisode,
  });

  @override
  State<TVShowDialog> createState() => _TVShowDialogState();
}

class _TVShowDialogState extends State<TVShowDialog> {
  late int _season;
  late int _episode;

  @override
  void initState() {
    super.initState();
    _season = widget.initialSeason;
    _episode = widget.initialEpisode;
  }

  String _formatNum(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: const Text('TV Show (SxxExx)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('${l10n.season}: '),
              const Spacer(),
              DropdownButton<int>(
                value: _season,
                items: List.generate(11, (i) => i).map((i) {
                  return DropdownMenuItem(value: i, child: Text(_formatNum(i)));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _season = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('${l10n.episode}: '),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _episode > 0 ? () => setState(() => _episode--) : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  _formatNum(_episode),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _episode++),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'result': 'S${_formatNum(_season)}E${_formatNum(_episode)}',
            'season': _season,
            'episode': _episode,
          }),
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}
