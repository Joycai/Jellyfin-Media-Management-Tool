import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';

class WebSearchDialog extends StatefulWidget {
  final String initialKeyword;

  const WebSearchDialog({super.key, required this.initialKeyword});

  @override
  State<WebSearchDialog> createState() => _WebSearchDialogState();
}

class _WebSearchDialogState extends State<WebSearchDialog> {
  late TextEditingController _keywordController;
  late SearchSite _selectedSite;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.initialKeyword);
    final settings = context.read<SettingsService>();
    int selectedIndex = settings.lastSearchSiteIndex;
    if (selectedIndex >= settings.searchSites.length) {
      selectedIndex = 0;
    }
    _selectedSite = settings.searchSites[selectedIndex];
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();

    return AlertDialog(
      title: Text(l10n.searchFromWeb),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keywordController,
            decoration: InputDecoration(labelText: l10n.searchKeyword),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SearchSite>(
            initialValue: _selectedSite,
            decoration: InputDecoration(labelText: l10n.searchSite),
            items: settings.searchSites.map((site) {
              return DropdownMenuItem(value: site, child: Text(site.name));
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedSite = val);
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
            final settings = context.read<SettingsService>();
            final newIndex = settings.searchSites.indexOf(_selectedSite);
            if (newIndex != -1) {
              settings.setLastSearchSiteIndex(newIndex);
            }
            Navigator.pop(context, {
              'keyword': _keywordController.text,
              'site': _selectedSite,
            });
          },
          child: Text(l10n.search),
        ),
      ],
    );
  }
}
