import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../services/gpu_info.dart';
import '../../services/history_service.dart';
import '../../services/settings_service.dart';
import '../../services/thumbnail_service.dart';
import '../../shortcuts/app_shortcuts.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'ai_services_screen.dart';
import 'settings_appearance_section.dart';
import 'settings_controls.dart';
import 'settings_language_section.dart';
import 'settings_scraping_section.dart';

enum _Section {
  appearance,
  language,
  paths,
  aiServices,
  scraping,
  privacy,
  shortcuts,
  about,
}

/// Full settings shell: sectioned sidebar on the left, scrollable detail pane
/// on the right. Matches the design mockup's structure 1:1.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const SettingsScreen(),
    ),
  );

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section _section = _Section.appearance;

  static const String _appVersion = '0.21.1';

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: glass.backdrop),
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 244,
                      child: _Sidebar(
                        section: _section,
                        onChange: (s) => setState(() => _section = s),
                      ),
                    ),
                    Expanded(child: _detail()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 24, 14),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Text(
            l10n.settings,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          Text(
            _breadcrumb(l10n),
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            'v $_appVersion · ${l10n.versionUpToDate}',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _breadcrumb(AppLocalizations l10n) => switch (_section) {
    _Section.appearance => l10n.secAppearance,
    _Section.language => l10n.secLanguage,
    _Section.paths => l10n.secPaths,
    _Section.aiServices => l10n.secAiServices,
    _Section.scraping => l10n.secScraping,
    _Section.privacy => l10n.secPrivacy,
    _Section.shortcuts => l10n.secShortcuts,
    _Section.about => l10n.secAbout,
  };

  Widget _detail() => switch (_section) {
    _Section.appearance => const AppearanceSection(),
    _Section.language => const LanguageSection(),
    _Section.paths => const _PathsSection(),
    _Section.aiServices => const _AiServicesSection(),
    _Section.scraping => const ScrapingSection(),
    _Section.privacy => const _PrivacySection(),
    _Section.shortcuts => const _ShortcutsSection(),
    _Section.about => _AboutSection(version: _appVersion),
  };
}

// ── Sidebar ─────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final _Section section;
  final ValueChanged<_Section> onChange;

  const _Sidebar({required this.section, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    Widget tile(_Section s, IconData icon, String label) {
      final on = s == section;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: on
              ? scheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChange(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: on ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: glass.panelStroke)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          tile(_Section.appearance, Icons.palette_outlined, l10n.secAppearance),
          tile(_Section.language, Icons.public, l10n.secLanguage),
          tile(_Section.paths, Icons.folder_special_outlined, l10n.secPaths),
          tile(
            _Section.aiServices,
            Icons.bubble_chart_outlined,
            l10n.secAiServices,
          ),
          tile(
            _Section.scraping,
            Icons.travel_explore_outlined,
            l10n.secScraping,
          ),
          tile(_Section.privacy, Icons.lock_outline_rounded, l10n.secPrivacy),
          tile(_Section.shortcuts, Icons.keyboard_outlined, l10n.secShortcuts),
          tile(_Section.about, Icons.info_outline, l10n.secAbout),
        ],
      ),
    );
  }
}

// ── Paths section ───────────────────────────────────────────────────────────

class _PathsSection extends StatelessWidget {
  const _PathsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        SettingsSectionTitle(l10n.recent),
        SettingsCard(
          child: settings.recent.isEmpty
              ? Text(
                  l10n.noRecent,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in settings.recent)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          r,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        SettingsSectionTitle(l10n.favorites),
        SettingsCard(
          child: settings.favorites.isEmpty
              ? Text(
                  l10n.noFavorites,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in settings.favorites)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          f,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── AI services section (embeds the existing manager) ───────────────────────

class _AiServicesSection extends StatefulWidget {
  const _AiServicesSection();

  @override
  State<_AiServicesSection> createState() => _AiServicesSectionState();
}

class _AiServicesSectionState extends State<_AiServicesSection> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profiles = context.read<AiProfilesService>();
      context.read<AiService>().updateConfig(profiles.aiConfig);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AiProfilesService>();
    return const AiServicesView();
  }
}

// ── Privacy section ─────────────────────────────────────────────────────────

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    final history = context.watch<HistoryService>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        SettingsSectionTitle(l10n.privacyStorage),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.privacyConfigBody,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: settings.openConfigFolder,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(l10n.openConfigFolder),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: history.entries.isEmpty
                        ? null
                        : () async {
                            for (final e in history.entries) {
                              await history.undo(e);
                            }
                          },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: Text(
                      l10n.privacyClearHistory(history.entries.length),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const _ClearThumbnailCacheButton(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reports how much disk the video-thumbnail cache is using and empties it.
/// Stateful because the size has to be measured off-disk and re-measured after
/// a clear — [SettingsService] doesn't own the cache.
class _ClearThumbnailCacheButton extends StatefulWidget {
  const _ClearThumbnailCacheButton();

  @override
  State<_ClearThumbnailCacheButton> createState() =>
      _ClearThumbnailCacheButtonState();
}

class _ClearThumbnailCacheButtonState
    extends State<_ClearThumbnailCacheButton> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final size = await ThumbnailService.instance.cacheSizeOnDisk();
    if (!mounted) return;
    setState(() => _bytes = size);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bytes = _bytes;
    return OutlinedButton.icon(
      onPressed: bytes == null || bytes == 0
          ? null
          : () async {
              await ThumbnailService.instance.clearCache();
              await _measure();
            },
      icon: const Icon(Icons.image_not_supported_outlined, size: 16),
      label: Text(l10n.privacyClearThumbnails(formatBytes(bytes ?? 0))),
    );
  }
}

/// Rendered entirely from [appShortcuts] so this page can never disagree with
/// what is actually bound. Adding a shortcut there adds a row here.
// ── Shortcuts section ───────────────────────────────────────────────────────

class _ShortcutsSection extends StatelessWidget {
  const _ShortcutsSection();

  String _groupLabel(AppLocalizations l10n, AppShortcutGroup group) =>
      switch (group) {
        AppShortcutGroup.navigation => l10n.shortcutGroupNavigation,
        AppShortcutGroup.selection => l10n.shortcutGroupSelection,
        AppShortcutGroup.files => l10n.shortcutGroupFiles,
        AppShortcutGroup.app => l10n.shortcutGroupApp,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final all = appShortcuts();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        SettingsSectionTitle(l10n.secShortcuts),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.shortcutsHint,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        for (final group in AppShortcutGroup.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
            child: Text(
              _groupLabel(l10n, group),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                for (final (i, shortcut)
                    in all.where((s) => s.group == group).indexed) ...[
                  if (i != 0) SettingsDivider(),
                  _ShortcutRow(shortcut: shortcut),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final AppShortcut shortcut;
  const _ShortcutRow({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          // Every accepted alias is shown, not just the primary — an alias the
          // user can't discover may as well not exist.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final activator in shortcut.activators)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    formatActivator(activator),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              shortcut.describe(l10n),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── About section ───────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  final String version;
  const _AboutSection({required this.version});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Null off Windows, or when the DXGI query failed — the row is then simply
    // absent rather than showing an apology.
    final gpu = GpuInfo.current();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'J',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.appBrand,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'v $version',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.aboutTagline,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              if (gpu != null) ...[
                const SizedBox(height: 14),
                Tooltip(
                  message: l10n.aboutGpuHint,
                  child: Row(
                    children: [
                      Icon(
                        Icons.memory_outlined,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.aboutGpu}: ',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          gpu.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://jellyfin.org/docs/general/server/media/naming/',
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined, size: 16),
                    label: Text(l10n.aboutJellyfinNaming),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
