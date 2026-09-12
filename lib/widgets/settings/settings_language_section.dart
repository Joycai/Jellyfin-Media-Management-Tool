import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';
import '../../l10n/app_localizations_zh.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import 'ai_services_screen.dart';

/// One row in the language list. Only languages whose ARB exists are listed —
/// no "coming soon" rows for translations we don't actually have.
// ── Language section ────────────────────────────────────────────────────────

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

class LanguageSection extends StatelessWidget {
  const LanguageSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      // 6.x 内容区内距，与其余六页同一套骨架。
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl24,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trilingual title + subtitle (mirrors the mockup's section header).
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: AppTypeScale.sizeHeading,
                fontWeight: FontWeight.w800,
              ),
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
            style: TextStyle(
              fontSize: AppTypeScale.sizeBody,
              color: scheme.onSurfaceVariant,
            ),
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
          borderRadius: BorderRadius.circular(AppRadii.panel),
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
    final glass = context.tokens;

    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.16) : glass.cardFill,
      borderRadius: BorderRadius.circular(AppRadii.panel),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.panel),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.6)
                  : glass.stroke,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(
                lang.flag,
                style: const TextStyle(fontSize: AppTypeScale.sizeHeading),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.name,
                      style: const TextStyle(
                        fontSize: AppTypeScale.sizeTitle,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected ? '${lang.tag} · ${l10n.langCurrent}' : lang.tag,
                      style: TextStyle(
                        fontSize: AppTypeScale.sizeControl,
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
              fontSize: AppTypeScale.sizeBody,
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
    final glass = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                flag,
                style: const TextStyle(fontSize: AppTypeScale.sizeSubheading),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: const TextStyle(
                  fontSize: AppTypeScale.sizeBody,
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
            bodyColor: AppPalette.success,
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
    final glass = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadii.field),
        border: Border.all(color: glass.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasised
                  ? AppTypeScale.sizeTitle
                  : AppTypeScale.sizeControl,
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
              fontSize: AppTypeScale.sizeBody,
              color: bodyColor ?? scheme.onSurface,
              fontFamily: bodyMono ? AppTypeScale.mono : null,
              fontFamilyFallback: bodyMono ? AppTypeScale.monoFallback : null,
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
    final glass = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.langPreviewHint,
              style: TextStyle(
                fontSize: AppTypeScale.sizeControl,
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
              side: BorderSide(color: glass.stroke),
            ),
            child: Text(l10n.langLearnMore),
          ),
        ],
      ),
    );
  }
}
