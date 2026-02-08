import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/file_browser_service.dart';

class BrowserToolbar extends StatelessWidget {
  final String? currentDirectory;
  final SortOption currentSort;
  final bool isAscending;
  final VoidCallback onPickDirectory;
  final VoidCallback onGoToParent;
  final VoidCallback onCreateFolder;
  final VoidCallback onRefresh;
  final VoidCallback onSearchWeb;
  final Function(dynamic) onSortChanged;

  const BrowserToolbar({
    super.key,
    required this.currentDirectory,
    required this.currentSort,
    required this.isAscending,
    required this.onPickDirectory,
    required this.onGoToParent,
    required this.onCreateFolder,
    required this.onRefresh,
    required this.onSearchWeb,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              onPressed: currentDirectory != null ? onGoToParent : null,
              tooltip: l10n.parentFolder,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: onPickDirectory,
              tooltip: l10n.openDirectory,
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              onPressed: currentDirectory != null ? onCreateFolder : null,
              tooltip: l10n.createNewFolder,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: currentDirectory != null ? onRefresh : null,
              tooltip: l10n.refresh,
            ),
            IconButton(
              icon: const Icon(Icons.public),
              onPressed: onSearchWeb,
              tooltip: l10n.searchFromWeb,
            ),
            PopupMenuButton<dynamic>(
              icon: const Icon(Icons.sort),
              tooltip: l10n.sortBy,
              onSelected: onSortChanged,
              itemBuilder: (context) => [
                _buildSortItem(context, SortOption.name, l10n.sortByName),
                _buildSortItem(context, SortOption.type, l10n.sortByType),
                _buildSortItem(context, SortOption.date, l10n.sortByDate),
                _buildSortItem(context, SortOption.size, l10n.sortBySize),
                const PopupMenuDivider(),
                _buildOrderItem(context, true, l10n.ascending),
                _buildOrderItem(context, false, l10n.descending),
              ],
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                currentDirectory ?? l10n.noDirectorySelected,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem _buildSortItem(BuildContext context, SortOption value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(currentSort == value ? Icons.check : null, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  PopupMenuItem _buildOrderItem(BuildContext context, bool value, String label) {
    final active = isAscending == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
