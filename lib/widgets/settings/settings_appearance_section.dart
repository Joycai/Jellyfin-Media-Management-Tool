import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/font_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import 'settings_controls.dart';
import 'settings_font_section.dart';

// ── Appearance section ──────────────────────────────────────────────────────

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        SettingsSectionTitle(l10n.theme),
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
              child: SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.glassIntensity,
                          style: const TextStyle(
                            fontSize: AppTypeScale.sizeBody,
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
                            fontSize: AppTypeScale.sizeCaption,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          l10n.glassSoft,
                          style: TextStyle(
                            fontSize: AppTypeScale.sizeCaption,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          l10n.glassStrong,
                          style: TextStyle(
                            fontSize: AppTypeScale.sizeCaption,
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
              child: SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.accentColor,
                      style: const TextStyle(
                        fontSize: AppTypeScale.sizeBody,
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
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          onTap: () {},
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadii.button,
                              ),
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
        const SizedBox(height: 16),
        // Sits under the glass slider because it overrides it: the slider
        // scales the blur, this removes it.
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: _ToggleRow(
            label: l10n.performanceMode,
            subtitle: l10n.performanceModeDesc,
            value: settings.performanceMode,
            onChanged: settings.setPerformanceMode,
          ),
        ),
        const SizedBox(height: 26),
        SettingsSectionTitle(l10n.fontSection),
        SettingsCard(
          // IntrinsicHeight + stretch: the system option has no status
          // subtitle, so without this the three cards render at different
          // heights.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final choice in AppFontChoice.values) ...[
                  Expanded(child: FontOption(choice: choice)),
                  if (choice != AppFontChoice.values.last)
                    const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        SettingsSectionTitle(l10n.behavior),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
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
    final glass = context.tokens;

    final label = switch (mode) {
      ThemeMode.light => l10n.light,
      ThemeMode.dark => l10n.dark,
      ThemeMode.system => l10n.system,
    };

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.panel),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: glass.cardFill,
            borderRadius: BorderRadius.circular(AppRadii.panel),
            border: Border.all(
              color: selected ? scheme.primary : glass.stroke,
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
                    duration: AppMotion.overlayIn,
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
                      fontSize: AppTypeScale.sizeTitle,
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
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(AppRadii.chip),
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
                    borderRadius: BorderRadius.circular(AppRadii.tiny),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(AppRadii.tiny),
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
              borderRadius: BorderRadius.circular(AppRadii.tiny),
            ),
          ),
        ],
      ),
    );

    if (mode == ThemeMode.system) {
      // 135° 硬分割：左上浅、右下深，取两套主题各自的窗口底色而不是纯黑白 ——
      // 这张卡是「这两个主题长什么样」的缩略图，用不属于任何一边的颜色画它，
      // 缩略图就不再是缩略图了。
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: AppPalette.perfTopBarLight),
            ),
            ClipPath(
              clipper: _DiagonalClipper(),
              child: const ColoredBox(
                color: AppPalette.darkBase,
                child: SizedBox.expand(),
              ),
            ),
            // 顶栏提示条也跟着分割，否则右半边看起来像被切掉了一块。
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    stops: [0.5, 0.5],
                    colors: [Color(0xCCFFFFFF), Color(0x26FFFFFF)],
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
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
      borderRadius: BorderRadius.circular(AppRadii.button),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.button),
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

  /// Optional second line, for a toggle whose label cannot carry the whole
  /// trade-off on its own.
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: AppTypeScale.sizeBody),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: AppTypeScale.sizeCaption,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
