import 'dart:async';
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
class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  /// Home plus whatever the mount scan has found so far.
  ///
  /// Home comes out of the environment, which is already in memory, so it is
  /// there on the first frame. The volumes need a directory scan, and that is
  /// the part that used to happen inside `build`: on the UI isolate, and again
  /// on *every* sidebar rebuild -- which is every file-list reload and every
  /// selection change, because the sidebar watches both services. On macOS
  /// `/Volumes` holds an entry per mounted volume and a NAS that has gone to
  /// sleep can take seconds to answer for one of them, which was a stalled
  /// frame each time.
  List<_Location> _locations = _initialLocations();

  static List<_Location> _initialLocations() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return const [];
    return [_Location(Icons.home_rounded, 'Home', home)];
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadVolumes());
  }

  /// Appends the mounted volumes once the scan finishes.
  ///
  /// Returns before any `await` on platforms with no mount root to scan, so
  /// `setState` is never reached during `initState` -- calling it there is a
  /// framework error, not a no-op.
  Future<void> _loadVolumes() async {
    final String? root;
    if (Platform.isMacOS) {
      root = '/Volumes';
    } else if (Platform.isLinux) {
      root = '/mnt';
    } else {
      root = null;
    }
    if (root == null) return;

    final volumes = <_Location>[];
    try {
      final dir = Directory(root);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory) {
            volumes.add(
              _Location(
                Icons.storage_rounded,
                p.basename(entity.path),
                entity.path,
              ),
            );
          }
        }
      }
    } catch (_) {
      // An unreadable mount root means fewer shortcuts, not a broken sidebar;
      // there is nothing the user could do about it from here.
    }

    if (!mounted || volumes.isEmpty) return;
    setState(() => _locations = [..._locations, ...volumes]);
  }

  void _open(String path) {
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
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
          ),
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
                  ...settings.favorites.map(
                    (path) => _NavTile(
                      icon: Icons.star_rounded,
                      label: p.basename(path).isEmpty ? path : p.basename(path),
                      selected: path == current,
                      onTap: () => _open(path),
                    ),
                  ),
                const SizedBox(height: 20),
                _SectionHeader(l10n.recent),
                if (settings.recent.isEmpty)
                  _EmptyHint(l10n.noRecent)
                else
                  ...settings.recent.map(
                    (path) => _NavTile(
                      icon: Icons.history_rounded,
                      label: p.basename(path).isEmpty ? path : p.basename(path),
                      selected: path == current,
                      onTap: () => _open(path),
                    ),
                  ),
                const SizedBox(height: 20),
                _SectionHeader(l10n.locations),
                ..._locations.map(
                  (loc) => _NavTile(
                    icon: loc.icon,
                    label: loc.label,
                    selected: loc.path == current,
                    onTap: () => _open(loc.path),
                  ),
                ),
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
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
        color: selected
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
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
      ConnectionStatus.unknown =>
        ai.isConfigured
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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (ai.isConfigured) ...[
            const SizedBox(height: 6),
            Text(
              ai.config.model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.itemsProcessed(ai.itemsProcessed),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
