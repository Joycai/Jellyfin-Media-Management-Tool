import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_service.dart';
import '../../services/file_browser_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_panel.dart';

/// Left navigation: Favorites (user-pinned folders), Recent (auto-tracked) and
/// Locations (home + drives/volumes), with the AI status card pinned to the
/// bottom.
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  void _open(BuildContext context, String path) {
    context.read<FileBrowserService>().setCurrentDirectory(path);
    context.read<SettingsService>().pushRecent(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final browser = context.watch<FileBrowserService>();
    final current = browser.currentDirectory;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    return Container(
      decoration: BoxDecoration(
        color: glass.sidebarFill,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
              children: [
                _SectionHeader(l10n.favorites),
                if (settings.favorites.isEmpty)
                  _EmptyHint(l10n.noFavorites)
                else
                  ...settings.favorites.map((path) => _NavTile(
                        icon: Icons.star_rounded,
                        label: p.basename(path).isEmpty ? path : p.basename(path),
                        selected: path == current,
                        onTap: () => _open(context, path),
                      )),
                const SizedBox(height: 20),
                _SectionHeader(l10n.recent),
                if (settings.recent.isEmpty)
                  _EmptyHint(l10n.noRecent)
                else
                  ...settings.recent.map((path) => _NavTile(
                        icon: Icons.history_rounded,
                        label: p.basename(path).isEmpty ? path : p.basename(path),
                        selected: path == current,
                        onTap: () => _open(context, path),
                      )),
                const SizedBox(height: 20),
                _SectionHeader(l10n.locations),
                ..._locations().map((loc) => _NavTile(
                      icon: loc.icon,
                      label: loc.label,
                      selected: loc.path == current,
                      onTap: () => _open(context, loc.path),
                    )),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _AiStatusCard(),
          ),
        ],
      ),
    );
  }

  List<_Location> _locations() {
    final locations = <_Location>[];
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      locations.add(_Location(Icons.home_rounded, 'Home', home));
    }
    try {
      if (Platform.isMacOS && Directory('/Volumes').existsSync()) {
        for (final v in Directory('/Volumes').listSync().whereType<Directory>()) {
          locations.add(_Location(Icons.storage_rounded, p.basename(v.path), v.path));
        }
      } else if (Platform.isLinux && Directory('/mnt').existsSync()) {
        for (final v in Directory('/mnt').listSync().whereType<Directory>()) {
          locations.add(_Location(Icons.storage_rounded, p.basename(v.path), v.path));
        }
      }
    } catch (_) {}
    return locations;
  }
}

class _Location {
  final IconData icon;
  final String label;
  final String path;
  const _Location(this.icon, this.label, this.path);
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiStatusCard extends StatelessWidget {
  const _AiStatusCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ai = context.watch<AiService>();
    final scheme = Theme.of(context).colorScheme;

    final (Color dot, String title) = switch (ai.status) {
      ConnectionStatus.connected => (const Color(0xFF34C759), l10n.aiConnected),
      ConnectionStatus.error => (scheme.error, l10n.aiConnectionError),
      ConnectionStatus.testing => (const Color(0xFFFFB020), l10n.aiTesting),
      ConnectionStatus.unknown => ai.isConfigured
          ? (scheme.onSurfaceVariant, l10n.aiReady)
          : (scheme.onSurfaceVariant, l10n.aiNotConfigured),
    };

    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.all(14),
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          if (ai.isConfigured) ...[
            const SizedBox(height: 6),
            Text(ai.config.model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(l10n.itemsProcessed(ai.itemsProcessed),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
        ],
      ),
    );
  }
}
