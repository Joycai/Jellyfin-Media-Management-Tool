import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/font_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import 'accent_picker.dart';
import 'settings_controls.dart';
import 'settings_font_section.dart';

/// 6.2 · 外观（设计稿画板 08）。
///
/// 三张主题卡 → 玻璃强度 / 强调色两列 → 行为开关。字体那一组是设计稿没有的：
/// 可下载中文界面字体是本应用独有的能力，按同一套版式挂在最后。
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();

    return SettingsPage(
      children: [
        SettingsSectionTitle(l10n.theme),
        // IntrinsicHeight：三张卡要等高，而 stretch 需要一个有界的交叉轴约束 ——
        // 直接放进 ListView 的话 Row 拿到的是无限高，布局会直接抛出来（页面整个
        // 空掉，控制台还不一定看得见）。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顺序照设计稿（浅 / 深 / 跟随），不是 ThemeMode 的枚举顺序。
              for (final mode in const [
                ThemeMode.light,
                ThemeMode.dark,
                ThemeMode.system,
              ]) ...[
                Expanded(
                  child: _ThemeCard(
                    mode: mode,
                    selected: settings.themeMode == mode,
                    onTap: () => settings.setThemeMode(mode),
                  ),
                ),
                if (mode != ThemeMode.system)
                  const SizedBox(width: AppSpacing.md12),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsColumns(
          leftFlex: 100,
          left: const _GlassCard(),
          right: const _AccentCard(),
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSectionTitle(l10n.behavior),
        SettingsRowsCard(
          children: [
            SettingsToggleRow(
              label: l10n.behaviorVideoThumbnails,
              value: settings.showVideoThumbnails,
              onChanged: settings.setShowVideoThumbnails,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSectionTitle(l10n.fontSection),
        SettingsCard(
          // IntrinsicHeight + stretch：系统那一项没有下载状态副行，不这样三张卡
          // 会各自高一截。
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final choice in AppFontChoice.values) ...[
                  Expanded(child: FontOption(choice: choice)),
                  if (choice != AppFontChoice.values.last)
                    const SizedBox(width: AppSpacing.md12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 主题卡 ──────────────────────────────────────────────────────────────────

/// `padding 14` · r14；预览图 h90 · r10；14 圆单选 + 12.5px 标签。
/// 选中卡 `accent 8%` + `1.5px accent` + accent 15% 投影。
class _ThemeCard extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  /// 6.2：预览图高 90。
  static const double previewHeight = 90;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;

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
        child: AnimatedContainer(
          duration: AppMotion.respecting(context, AppMotion.hover),
          padding: const EdgeInsets.all(AppSpacing.md12),
          decoration: BoxDecoration(
            color: selected ? t.accent.withValues(alpha: 0.08) : t.cardFill,
            borderRadius: BorderRadius.circular(AppRadii.panel),
            border: Border.all(
              color: selected ? t.accent : t.stroke,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected ? t.elevation.card : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: previewHeight,
                child: _ThemePreview(mode: mode),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  _Radio(selected: selected),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: AppTypeScale.control.copyWith(
                      color: t.textTitle,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

/// 14 圆单选：选中是「强调色实底 + 3px 白内环 + 2px 强调色外环」，不是打勾。
class _Radio extends StatelessWidget {
  final bool selected;

  const _Radio({required this.selected});

  static const double size = 14;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedContainer(
      duration: AppMotion.respecting(context, AppMotion.hover),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : Colors.transparent,
        border: Border.all(
          color: selected ? Colors.white : t.strokeStrong,
          width: selected ? 3 : 2,
        ),
        boxShadow: selected
            ? [BoxShadow(color: t.accent, spreadRadius: 2, blurRadius: 0)]
            : const [],
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
    // 缩略图画的就是这两套主题本身，所以取的必须是它们真正的窗口底与强调色，
    // 不是一组「看起来像」的颜色 —— 换了强调色之后这张卡还得说真话。
    final t = context.tokens;
    final bg = isDark ? AppPalette.darkBase : AppPalette.perfTopBarLight;
    final card = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppPalette.ink.withValues(alpha: 0.05);
    final bar1 = t.accent.withValues(alpha: isDark ? 0.7 : 0.35);
    final bar2 = AppPalette.ai.withValues(alpha: isDark ? 0.6 : 0.3);

    if (mode == ThemeMode.system) {
      // 135° 硬分割：左上浅、右下深，取两套主题各自的窗口底色而不是纯黑白 ——
      // 这张卡是「这两个主题长什么样」的缩略图，用不属于任何一边的颜色画它，
      // 缩略图就不再是缩略图了。
      //
      // 用「两段式渐变」而不是裁一个三角形：裁三角是从角到角的斜边，在 3:1 的
      // 扁盒子里那条线几乎躺平；渐变的硬分界永远垂直于对角轴、且过中心，看上去
      // 才是设计稿里那道 135° 的斜切。
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.field),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.5, 0.5],
            colors: [AppPalette.perfTopBarLight, AppPalette.darkBase],
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏提示条也跟着分割，否则右半边看起来像被切掉了一块。
            Container(
              height: AppSpacing.sm,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  stops: const [0.5, 0.5],
                  colors: [
                    Colors.white.withValues(alpha: 0.85),
                    Colors.white.withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.field),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppSpacing.sm,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(AppRadii.tiny),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  flex: 60,
                  child: Container(
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(AppRadii.tiny),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            height: AppSpacing.md12,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [bar1, bar2]),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 玻璃质感强度 ────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final settings = context.watch<SettingsService>();
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.glassIntensity,
                  style: AppTypeScale.controlStrong.copyWith(
                    color: t.textTitle,
                  ),
                ),
              ),
              Text(
                '${settings.glassIntensity.round()}',
                style: context.tokens.monoBody.copyWith(
                  color: t.accentText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Slider(
            value: settings.glassIntensity,
            max: 100,
            onChanged: settings.setGlassIntensity,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in [
                l10n.glassNone,
                l10n.glassSoft,
                l10n.glassStrong,
              ])
                Text(
                  label,
                  style: AppTypeScale.columnHeader.copyWith(
                    letterSpacing: 0,
                    color: t.textMuted,
                  ),
                ),
            ],
          ),
          // 这条注解替掉了从前那个独立的「性能模式」开关。它必须在这儿，因为
          // 0 这一档是整个设置页唯一影响性能的选择，而滑块本身长得完全不像一个
          // 性能控件 —— 强度 50 → 100 只差 2%，关不关差 46ms。
          //
          // 两种状态都渲染（而不是只在 0 时才出现一行），否则跨过 0 的那一刻
          // 卡片会长高一行，把并排的强调色卡一起顶动。
          SettingsFootnote(
            settings.glassIntensity <= 0 ? l10n.glassOffHint : l10n.glassOnHint,
          ),
        ],
      ),
    );
  }
}

// ── 强调色 ──────────────────────────────────────────────────────────────────

class _AccentCard extends StatefulWidget {
  const _AccentCard();

  @override
  State<_AccentCard> createState() => _AccentCardState();
}

class _AccentCardState extends State<_AccentCard> {
  final _plusKey = GlobalKey();
  bool _pickerOpen = false;

  Future<void> _openPicker() async {
    final box = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() => _pickerOpen = true);
    await showAccentPicker(context, anchor: box);
    if (mounted) setState(() => _pickerOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final settings = context.watch<SettingsService>();
    final current = settings.accentColor;
    final presets = AppTheme.accentPresets;
    final custom =
        current != null && !presets.any((c) => c.toARGB32() == current);

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.accentColor,
            style: AppTypeScale.controlStrong.copyWith(color: t.textTitle),
          ),
          const SizedBox(height: AppSpacing.md12),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in presets)
                _Swatch(
                  color: c,
                  selected:
                      (current ?? presets.first.toARGB32()) == c.toARGB32(),
                  onTap: () => settings.setAccentColor(c.toARGB32()),
                ),
              // 「＋」：没有自定义色时是虚线空格，有的时候显示当前色；浮层开着
              // 的整段时间保持 4px 光环（6.2）。
              _Swatch(
                key: _plusKey,
                color: custom ? Color(current) : null,
                selected: custom || _pickerOpen,
                onTap: _openPicker,
                child: Icon(
                  Icons.add,
                  size: 14,
                  color: custom ? Colors.white : t.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 32 见方 · r8。选中是 `0 0 0 2px 窗口底, 0 0 0 4px 本色` 的双环 —— 用窗口底而
/// 不是白色画内环，浅色主题下白环压在白卡上就消失了。
class _Swatch extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.child,
  });

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill ?? t.controlFill,
          borderRadius: BorderRadius.circular(AppRadii.button),
          border: fill == null
              ? Border.all(color: t.strokeStrong)
              : Border.all(color: t.windowBase, width: selected ? 2 : 0),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: fill ?? t.accent,
                    spreadRadius: 2,
                    blurRadius: 0,
                  ),
                ]
              : const [],
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
