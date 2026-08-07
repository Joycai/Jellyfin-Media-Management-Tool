import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';
import '../../l10n/app_localizations_zh.dart';
import '../../models/scrape_recipe.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../services/font_service.dart';
import '../../services/history_service.dart';
import '../../services/scrape/cookie_store.dart';
import '../../services/scrape/recipe_store.dart';
import '../../services/scrape/scrape_service.dart';
import '../../services/settings_service.dart';
import '../../services/thumbnail_service.dart';
import '../../shortcuts/app_shortcuts.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'ai_services_screen.dart';

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

  static const String _appVersion = '0.13.0';

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

  String _breadcrumb(AppLocalizations l10n) =>
      '${l10n.secAppearance} / ${l10n.secLanguage} / ${l10n.breadcrumbPaths}';

  Widget _detail() => switch (_section) {
    _Section.appearance => const _AppearanceSection(),
    _Section.language => const _LanguageSection(),
    _Section.paths => const _PathsSection(),
    _Section.aiServices => const _AiServicesSection(),
    _Section.scraping => const _ScrapingSection(),
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

// ── Shared section building blocks ──────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glass.panelStroke),
      ),
      child: child,
    );
  }
}

// ── Appearance section ──────────────────────────────────────────────────────

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        _SectionTitle(l10n.theme),
        Row(
          children: [
            // Order matches the design mockup (not ThemeMode.values' enum order).
            for (final mode in const [
              ThemeMode.light,
              ThemeMode.dark,
              ThemeMode.system,
            ])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: mode == ThemeMode.system ? 0 : 14,
                  ),
                  child: _ThemeCard(
                    mode: mode,
                    selected: settings.themeMode == mode,
                    onTap: () => settings.setThemeMode(mode),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.glassIntensity,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${settings.glassIntensity.round()}',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        overlayShape: SliderComponentShape.noOverlay,
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                      ),
                      child: Slider(
                        value: settings.glassIntensity,
                        max: 100,
                        onChanged: (v) => settings.setGlassIntensity(v),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.glassNone,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          l10n.glassSoft,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          l10n.glassStrong,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.accentColor,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final c in AppTheme.accentPresets) ...[
                          _AccentSwatch(
                            color: c,
                            selected:
                                (settings.accentColor ??
                                    AppTheme.accentPresets.first.toARGB32()) ==
                                c.toARGB32(),
                            onTap: () => settings.setAccentColor(c.toARGB32()),
                          ),
                          const SizedBox(width: 10),
                        ],
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {},
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.4,
                                ),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _SectionTitle(l10n.fontSection),
        _Card(
          // IntrinsicHeight + stretch: the system option has no status
          // subtitle, so without this the three cards render at different
          // heights.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final choice in AppFontChoice.values) ...[
                  Expanded(child: _FontOption(choice: choice)),
                  if (choice != AppFontChoice.values.last)
                    const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        _SectionTitle(l10n.behavior),
        _Card(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
              _ToggleRow(
                label: l10n.behaviorAutoConnect,
                value: settings.autoConnectAi,
                onChanged: settings.setAutoConnectAi,
              ),
              _Divider(),
              _ToggleRow(
                label: l10n.behaviorAlwaysPreview,
                value: settings.alwaysShowPreview,
                onChanged: settings.setAlwaysShowPreview,
              ),
              _Divider(),
              _ToggleRow(
                label: l10n.behaviorLowConfSuggest,
                value: settings.lowConfidenceSuggestOnly,
                onChanged: settings.setLowConfidenceSuggestOnly,
              ),
              _Divider(),
              _ToggleRow(
                label: l10n.behaviorVideoThumbnails,
                value: settings.showVideoThumbnails,
                onChanged: settings.setShowVideoThumbnails,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    final label = switch (mode) {
      ThemeMode.light => l10n.light,
      ThemeMode.dark => l10n.dark,
      ThemeMode.system => l10n.system,
    };

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: glass.panelFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary : glass.panelStroke,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 124, child: _ThemePreview(mode: mode)),
              const SizedBox(height: 14),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        width: 2,
                      ),
                      color: selected ? scheme.primary : Colors.transparent,
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  final ThemeMode mode;
  const _ThemePreview({required this.mode});

  @override
  Widget build(BuildContext context) {
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final bg = isDark ? const Color(0xFF1A1A38) : Colors.white;
    final card = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF0F2F6);
    final bar1 = isDark ? const Color(0xFF6B7AFF) : const Color(0xFFC9CFEE);
    final bar2 = isDark ? const Color(0xFF7B5BFF) : const Color(0xFFE6D5F5);

    final preview = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [bar1, bar2]),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );

    if (mode == ThemeMode.system) {
      // Half white / half dark, split diagonally — mirrors the mockup.
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.white)),
            ClipPath(
              clipper: _DiagonalClipper(),
              child: Container(color: const Color(0xFF111126)),
            ),
            // Subtle line on top to hint at structure.
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return preview;
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _AccentSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: glass.panelStroke),
    );
  }
}

// ── Language section ────────────────────────────────────────────────────────

/// One row in the language list. Only languages whose ARB exists are listed —
/// no "coming soon" rows for translations we don't actually have.
class _Lang {
  final String code;
  final String flag;
  final String name;
  final String tag;
  const _Lang(this.code, this.flag, this.name, this.tag);
}

const _languages = <_Lang>[
  _Lang('zh', '🇨🇳', '简体中文', 'zh-Hans'),
  _Lang('en', '🇺🇸', 'English', 'en-US'),
];

class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trilingual title + subtitle (mirrors the mockup's section header).
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              children: [
                TextSpan(
                  text: '语言',
                  style: TextStyle(color: scheme.onSurface),
                ),
                TextSpan(
                  text: ' · ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: 'Language',
                  style: TextStyle(color: scheme.onSurface),
                ),
                TextSpan(
                  text: ' · ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: '言語',
                  style: TextStyle(color: scheme.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.langHeaderSubtitle,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 4, child: _LanguageList()),
                const SizedBox(width: 18),
                Expanded(flex: 7, child: _LanguagePreview()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final scheme = Theme.of(context).colorScheme;
    final current =
        settings.locale?.languageCode ??
        Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _languages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final lang = _languages[i];
              final on = lang.code == current;
              return _LanguageCard(
                lang: lang,
                selected: on,
                onTap: () => settings.setLocale(Locale(lang.code)),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        // Dashed "import .arb" placeholder.
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.langImportSoon))),
          child: DottedBorderBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      l10n.langImportArb,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final _Lang lang;
  final bool selected;
  final VoidCallback onTap;
  const _LanguageCard({
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.16)
          : glass.panelFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.6)
                  : glass.panelStroke,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(lang.flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected ? '${lang.tag} · ${l10n.langCurrent}' : lang.tag,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguagePreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Show the two locales we actually have translations for; the picked
    // language drives the live app, the preview always compares zh ↔ en.
    final zh = AppLocalizationsZh();
    final en = AppLocalizationsEn();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.langPreviewTitle,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PreviewPanel(
                  flag: '🇨🇳',
                  name: zh.appBrand.contains('Jellyfin') ? '简体中文' : '简体中文',
                  loc: zh,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _PreviewPanel(flag: '🇺🇸', name: 'English', loc: en),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PreviewHintBanner(),
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final String flag;
  final String name;
  final AppLocalizations loc;
  const _PreviewPanel({
    required this.flag,
    required this.name,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _previewItem(
            context,
            title: loc.organizeWithAi,
            body: loc.previewOrganizeSubtitle,
            emphasised: true,
          ),
          const SizedBox(height: 10),
          _previewItem(
            context,
            title: loc.previewConfidenceLabel,
            body: '96% · ${loc.previewConfidenceHigh}',
            bodyColor: const Color(0xFF34C759),
          ),
          const SizedBox(height: 10),
          _previewItem(
            context,
            title: loc.previewTargetLabel,
            body: loc.previewTargetValue,
            bodyMono: true,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _previewItem(
    BuildContext context, {
    required String title,
    required String body,
    bool emphasised = false,
    bool bodyMono = false,
    Color? bodyColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasised ? 15 : 12.5,
              fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
              color: emphasised ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: bodyColor ?? scheme.onSurface,
              fontFamily: bodyMono ? 'monospace' : null,
              fontWeight: emphasised
                  ? FontWeight.w400
                  : (bodyColor != null ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewHintBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.langPreviewHint,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => launchUrl(
              Uri.parse(
                'https://jellyfin.org/docs/general/server/media/naming/',
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              side: BorderSide(color: glass.panelStroke),
            ),
            child: Text(l10n.langLearnMore),
          ),
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
        _SectionTitle(l10n.recent),
        _Card(
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
        _SectionTitle(l10n.favorites),
        _Card(
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

class _AiServicesSection extends StatelessWidget {
  const _AiServicesSection();

  @override
  Widget build(BuildContext context) {
    // Re-sync AiService with the active profile whenever this section rebuilds
    // (cheap and idempotent; `updateConfig` no-ops when nothing changes).
    final profiles = context.watch<AiProfilesService>();
    context.read<AiService>().updateConfig(profiles.aiConfig);
    return const AiServicesView();
  }
}

// ── Scraping section ────────────────────────────────────────────────────────

/// Cookie management and the recipe list.
///
/// Stateful because `CookieStore` is a plain in-memory object rather than a
/// `ChangeNotifier` — deliberately, so no listener can leak a session cookie
/// into a rebuild somewhere else. This screen owns the only view of it and
/// refreshes itself after each mutation.
class _ScrapingSection extends StatefulWidget {
  const _ScrapingSection();

  @override
  State<_ScrapingSection> createState() => _ScrapingSectionState();
}

class _ScrapingSectionState extends State<_ScrapingSection> {
  CookieStore get _cookies => context.read<ScrapeService>().fetcher.cookies;

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final store = _cookies;

    final picked = await FilePicker.pickFiles(
      dialogTitle: l10n.settingsScrapeImportCookies,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    List<NetscapeCookie> parsed;
    try {
      parsed = CookieStore.parseNetscape(await File(path).readAsString());
    } catch (_) {
      parsed = const [];
    }
    if (parsed.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsScrapeCookieImportFailed)),
      );
      return;
    }
    store.importAll(parsed);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsScrapeCookieImported(parsed.length))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final store = _cookies;

    // Grouped by host: one row per site is what the user reasons about, not
    // one row per cookie.
    final byDomain = <String, List<NetscapeCookie>>{};
    for (final c in store.cookies) {
      byDomain.putIfAbsent(c.domain, () => []).add(c);
    }
    final domains = byDomain.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        _SectionTitle(l10n.settingsScrapeCookies),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.settingsScrapeCookieWarning,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _import,
                    icon: const Icon(Icons.upload_file_outlined, size: 17),
                    label: Text(l10n.settingsScrapeImportCookies),
                  ),
                  const SizedBox(width: 10),
                  if (domains.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(store.clear),
                      child: Text(l10n.settingsScrapeClearCookies),
                    ),
                ],
              ),
              if (domains.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.settingsScrapeCookieEmpty,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              for (final domain in domains) ...[
                _Divider(),
                _CookieDomainRow(
                  domain: domain,
                  cookies: byDomain[domain]!,
                  onClear: () => setState(() => store.clearDomain(domain)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 26),
        _SectionTitle(l10n.settingsScrapeRecipes),
        const _RecipeList(),
      ],
    );
  }
}

/// One host's cookies. Names only — a value is the credential, and there is no
/// reason to ever put one on screen.
class _CookieDomainRow extends StatelessWidget {
  final String domain;
  final List<NetscapeCookie> cookies;
  final VoidCallback onClear;

  const _CookieDomainRow({
    required this.domain,
    required this.cookies,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                domain,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              l10n.settingsScrapeCookieCount(cookies.length),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onClear,
              child: Text(l10n.settingsScrapeClearDomain),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final c in cookies)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${c.name}=••••',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Read-only view of every recipe, learned ones first. Built-ins cannot be
/// deleted — they ship in code, so "deleting" one would only last until the
/// next launch.
class _RecipeList extends StatelessWidget {
  const _RecipeList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<RecipeStore>();
    final recipes = store.all;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < recipes.length; i++) ...[
            if (i > 0) _Divider(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipes[i].domain,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recipes[i].pathPattern.isEmpty
                            ? l10n.settingsScrapeRecipeAnyPath
                            : recipes[i].pathPattern,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  l10n.settingsScrapeRecipeHealth(
                    recipes[i].successCount,
                    recipes[i].failCount,
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                _RecipeBadge(recipe: recipes[i]),
                if (recipes[i].origin != RecipeOrigin.builtin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: l10n.settingsScrapeRecipeDelete,
                    onPressed: () => store.remove(recipes[i]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecipeBadge extends StatelessWidget {
  final ScrapeRecipe recipe;
  const _RecipeBadge({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Retirement is the interesting state, so it wins over the origin label.
    final (label, color) = recipe.isRetired
        ? (l10n.settingsScrapeRecipeRetired, scheme.error)
        : switch (recipe.origin) {
            RecipeOrigin.builtin => (
              l10n.settingsScrapeRecipeBuiltin,
              scheme.onSurfaceVariant,
            ),
            RecipeOrigin.llm => (
              l10n.settingsScrapeRecipeLearned,
              const Color(0xFFE0852C),
            ),
            RecipeOrigin.user => (
              l10n.settingsScrapeRecipeUser,
              scheme.primary,
            ),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
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
        _SectionTitle(l10n.privacyStorage),
        _Card(
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

// ── Shortcuts section ───────────────────────────────────────────────────────

/// Rendered entirely from [appShortcuts] so this page can never disagree with
/// what is actually bound. Adding a shortcut there adds a row here.
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
        _SectionTitle(l10n.secShortcuts),
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
          _Card(
            child: Column(
              children: [
                for (final (i, shortcut)
                    in all.where((s) => s.group == group).indexed) ...[
                  if (i != 0) _Divider(),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        _Card(
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

// ── Font picker ─────────────────────────────────────────────────────────────

class _FontOption extends StatelessWidget {
  final AppFontChoice choice;
  const _FontOption({required this.choice});

  String _label(AppLocalizations l10n) => switch (choice) {
    AppFontChoice.system => l10n.fontSystem,
    AppFontChoice.harmony => 'HarmonyOS Sans',
    AppFontChoice.misans => 'MiSans',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final fonts = context.watch<FontService>();
    final scheme = Theme.of(context).colorScheme;
    final selected = settings.fontChoice == choice.id;
    final downloaded = fonts.isDownloadedSync(choice);

    final String? status = choice == AppFontChoice.system
        ? null
        : (downloaded
              ? l10n.fontStatusDownloaded
              : l10n.fontStatusNotDownloaded);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _select(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.onSurfaceVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                // min + Row's default center alignment keeps the text block
                // vertically centered when the card is stretched taller than
                // its content (see IntrinsicHeight in the appearance section).
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: downloaded
                              ? const Color(0xFF34C759)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _select(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    final fonts = context.read<FontService>();

    if (choice == AppFontChoice.system || fonts.isLoaded(choice)) {
      await settings.setFontChoice(choice.id);
      return;
    }
    // Downloaded on a previous run but not registered yet (it wasn't the
    // active font at startup) — register and switch, no download needed.
    if (fonts.isDownloadedSync(choice)) {
      await fonts.loadIfDownloaded(choice);
      await settings.setFontChoice(choice.id);
      return;
    }

    final name = _label(l10n);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fontDownloadTitle),
        content: Text(l10n.fontDownloadConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.downloadAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FontDownloadDialog(choice: choice, name: name),
    );
    if (ok == true) {
      await settings.setFontChoice(choice.id);
    }
  }
}

/// Modal progress dialog that runs the download and pops `true` on success,
/// `false` on failure (after surfacing the error via a snackbar).
class _FontDownloadDialog extends StatefulWidget {
  final AppFontChoice choice;
  final String name;
  const _FontDownloadDialog({required this.choice, required this.name});

  @override
  State<_FontDownloadDialog> createState() => _FontDownloadDialogState();
}

class _FontDownloadDialogState extends State<_FontDownloadDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final fonts = context.read<FontService>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    try {
      await fonts.downloadAndLoad(widget.choice);
      if (mounted) navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.fontDownloadFailed(e.toString()))),
      );
      if (mounted) navigator.pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fonts = context.watch<FontService>();
    final scheme = Theme.of(context).colorScheme;
    final received = fonts.receivedBytes;
    final total = fonts.totalBytes;

    return AlertDialog(
      title: Text(l10n.fontDownloading(widget.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (fonts.progress ?? 0) > 0 ? fonts.progress : null,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            total > 0
                ? '${formatBytes(received)} / ${formatBytes(total)}'
                : formatBytes(received),
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
