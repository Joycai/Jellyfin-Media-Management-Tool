import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../shell/app_shell.dart';
import '../shell/secondary_title_bar.dart';
import '../ui/glass_surface.dart';
import 'ai_services_screen.dart';
import 'settings_about_section.dart';
import 'settings_appearance_section.dart';
import 'settings_language_section.dart';
import 'settings_paths_section.dart';
import 'settings_privacy_section.dart';
import 'settings_scraping_section.dart';
import 'settings_shortcuts_section.dart';

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
    AppPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const SettingsScreen(),
    ),
  );

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section _section = _Section.appearance;

  /// `X.Y.Z+N`. sync-version 写的就是这一处；关于页把它拆成版本与构建号两行
  /// （6.4），顶栏只显示版本名。
  static const String _appVersion = '0.22.0+19';
  static String get _versionName => _appVersion.split('+').first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Scaffold(
      // 整页路由盖住了主顶栏，窗口按钮与拖拽区都跟着没了 —— 二级顶栏把它们
      // 带回来（见 SecondaryTitleBar）。
      body: AppShell(
        titleBar: SecondaryTitleBar(
          backLabel: l10n.back,
          onBack: () => Navigator.of(context).pop(),
          title: l10n.settings,
          subtitle: _breadcrumb(l10n),
          actions: [
            Text(
              'v $_versionName · ${l10n.versionUpToDate}',
              style: context.tokens.monoTiny.copyWith(color: t.textMuted),
            ),
            const SizedBox(width: AppSpacing.md12),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              // 6.x 的设置导航是 200，比主侧栏窄：它的标签都是两三个字，
              // 244 只会在右边留一条空白。
              width: 200,
              child: _Sidebar(
                section: _section,
                onChange: (s) => setState(() => _section = s),
              ),
            ),
            Expanded(child: _detail()),
          ],
        ),
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
    _Section.paths => const PathsSection(),
    _Section.aiServices => const _AiServicesSection(),
    _Section.scraping => const ScrapingSection(),
    _Section.privacy => const PrivacySection(),
    _Section.shortcuts => const ShortcutsSection(),
    _Section.about => const AboutSection(version: _appVersion),
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
    final glass = context.tokens;

    // 6.x 的导航行：padding 7/12、圆角 8、12.5px；选中 accent 14% + 描边 22%。
    Widget tile(_Section s, IconData icon, String label) {
      final on = s == section;
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md12,
          vertical: 1,
        ),
        child: Material(
          color: on ? glass.selectionFill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.button),
            onTap: () => onChange(s),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.button),
                border: on
                    ? Border.all(color: glass.selectionStroke)
                    : Border.all(color: Colors.transparent),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md12,
                vertical: 7,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: on ? glass.textTitle : glass.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: AppTypeScale.control.copyWith(
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: on ? glass.textTitle : glass.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppGlassPane(
      border: Border(right: BorderSide(color: glass.stroke)),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
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

// ── AI services section (embeds the existing manager) ───────────────────

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
