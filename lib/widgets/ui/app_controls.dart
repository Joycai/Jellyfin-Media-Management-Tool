import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/design_tokens.dart';

/// 设计稿 1.4 的基础控件。
///
/// 每一个都只从 [AppTokens] / [AppSizes] / [AppRadii] 取值 —— 这些类之外**没有
/// 任何一个数字**出现在业务 widget 里，换主题、换强调色、开性能模式都只改令牌。
///
/// 状态过渡统一 80–120ms ease-out，**只动底色与描边，不动尺寸与位移**：设计稿
/// 1.4f 明确排除缩放与弹性曲线，桌面端一屏几十个可悬停元素，任何位移都会让列表
/// 看起来在呼吸。

// ---------------------------------------------------------------------------
// 1.4a 按钮
// ---------------------------------------------------------------------------

enum AppButtonKind {
  /// 主 · 强调色实底 + 投影。
  primary,

  /// 次级 · white 6% + 描边 10%。
  secondary,

  /// 幽灵 · 无底，悬停才出底。
  ghost,

  /// 危险 · 语义底 + 描边；只在确认弹层内用实色。
  danger,

  /// 危险 · 实色。仅限确认弹层的主操作。
  dangerSolid,

  /// 成功 · 实色。刮削确认这类「写入」终态操作。
  successSolid,
}

/// 高 32、圆角 8、左右内距 14、图标与文字间距 7。
class AppButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonKind kind;

  /// 一个刻意的紧凑变体（设计稿里的 h24 / h28 行内按钮）。
  final double height;

  /// 撑满可用宽度。
  final bool expand;
  final String? tooltip;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = AppButtonKind.secondary,
    this.height = AppSizes.control,
    this.expand = false,
    this.tooltip,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = AppSizes.control,
    this.expand = false,
    this.tooltip,
  }) : kind = AppButtonKind.primary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = AppSizes.control,
    this.expand = false,
    this.tooltip,
  }) : kind = AppButtonKind.ghost;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onPressed != null;
    final (fill, border, fg, shadow) = _style(t, enabled);

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 14, color: fg),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypeScale.controlStrong.copyWith(
              color: fg,
              fontWeight:
                  widget.kind == AppButtonKind.primary ||
                      widget.kind == AppButtonKind.danger ||
                      widget.kind == AppButtonKind.dangerSolid ||
                      widget.kind == AppButtonKind.successSolid
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ],
    );

    content = AnimatedContainer(
      duration: AppMotion.respecting(context, AppMotion.hover),
      curve: AppMotion.standard,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.button),
        border: border == null ? null : Border.all(color: border),
        boxShadow: shadow,
      ),
      alignment: Alignment.center,
      child: content,
    );

    content = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: content,
      ),
    );

    if (widget.tooltip != null) {
      content = Tooltip(message: widget.tooltip!, child: content);
    }
    return widget.expand
        ? SizedBox(width: double.infinity, child: content)
        : content;
  }

  (Color, Color?, Color, List<BoxShadow>) _style(AppTokens t, bool enabled) {
    switch (widget.kind) {
      case AppButtonKind.primary:
        if (!enabled) {
          return (
            t.accentDisabled,
            null,
            t.badgeText.withValues(alpha: 0.55),
            const <BoxShadow>[],
          );
        }
        if (_pressed) return (t.accentPressed, null, t.badgeText, const []);
        if (_hover) {
          return (t.accentHover, null, t.badgeText, t.accentShadowHover);
        }
        return (t.accent, null, t.badgeText, t.accentShadow);
      case AppButtonKind.secondary:
        if (!enabled) {
          return (t.controlFill, t.stroke, t.textDisabled, const <BoxShadow>[]);
        }
        return (
          _pressed || _hover ? t.controlFillHover : t.controlFill,
          t.strokeStrong,
          t.textBody,
          const <BoxShadow>[],
        );
      case AppButtonKind.ghost:
        if (!enabled) {
          return (
            Colors.transparent,
            null,
            t.textDisabled,
            const <BoxShadow>[],
          );
        }
        return (
          _hover || _pressed ? t.controlFill : Colors.transparent,
          null,
          t.textSecondary,
          const <BoxShadow>[],
        );
      case AppButtonKind.danger:
        final on = _hover || _pressed;
        return (
          t.danger.withValues(alpha: on ? 0.26 : 0.18),
          t.danger.withValues(alpha: 0.34),
          enabled ? t.dangerText : t.textDisabled,
          const <BoxShadow>[],
        );
      case AppButtonKind.dangerSolid:
        final base = t.danger;
        return (
          _pressed
              ? _shift(base, -0.10)
              : _hover
              ? _shift(base, 0.08)
              : base,
          null,
          Colors.white,
          const <BoxShadow>[],
        );
      case AppButtonKind.successSolid:
        final base = t.success;
        return (
          _pressed
              ? _shift(base, -0.10)
              : _hover
              ? _shift(base, 0.08)
              : base,
          null,
          AppPalette.onSuccessSolid,
          const <BoxShadow>[],
        );
    }
  }

  static Color _shift(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}

/// 图标按钮 32×32 · r9。默认 white 5% / 悬停 white 10% / 激活 accent 22% + 描边 40%。
class AppIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// 浮层打开中等「保持按下」的状态。
  final bool active;

  /// 8px 语义圆点角标，外描 2px 窗口底色挖空。null = 不显示。
  final Color? badgeDot;

  /// 无历史 / 窗口失焦：灰度 + 50% 不透明。
  final bool dimmed;

  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.active = false,
    this.badgeDot,
    this.dimmed = false,
    this.size = AppSizes.control,
  });

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onPressed != null && !widget.dimmed;

    Widget button = AnimatedContainer(
      duration: AppMotion.respecting(context, AppMotion.hover),
      curve: AppMotion.standard,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.active
            ? t.iconButtonActiveFill
            : _hover
            ? t.controlFillHover
            : t.controlFill,
        borderRadius: BorderRadius.circular(AppRadii.icon),
        border: widget.active
            ? Border.all(color: t.iconButtonActiveStroke)
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        widget.icon,
        size: 15,
        color: widget.active ? t.textTitle : t.textSecondary,
      ),
    );

    if (widget.badgeDot != null) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.badgeDot,
                shape: BoxShape.circle,
                // 2px 描边挖空，用窗口底色而不是面板色 —— 顶栏是半透明的，
                // 描边要挡住的是它背后的窗口底。
                border: Border.all(color: t.windowBase, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.dimmed) {
      button = Opacity(
        opacity: 0.5,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(_greyscale),
          child: button,
        ),
      );
    }

    button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: button,
      ),
    );

    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }

  static const List<double> _greyscale = [
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

// ---------------------------------------------------------------------------
// 1.4b 输入
// ---------------------------------------------------------------------------

/// 高 32、圆角 10、内距 12 的输入框。
///
/// 尺寸与描边**全部**来自 `AppTheme.inputDecorationTheme`；这里只补内容
/// （图标、提示、快捷键胶囊），这正是设计稿约定的分工：`InputDecoration`
/// 只承载内容。
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final IconData? icon;

  /// 右侧的快捷键提示胶囊，例如 `Ctrl K`。
  final String? shortcut;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final String? errorText;
  final bool mono;
  final bool obscure;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.icon,
    this.shortcut,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.errorText,
    this.mono = false,
    this.obscure = false,
    this.maxLines = 1,
    this.textInputAction,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      cursorColor: t.accent,
      cursorWidth: 1.5,
      style: (mono ? AppTypeScale.monoBody : AppTypeScale.control).copyWith(
        color: enabled ? t.textBody : t.textDisabled,
      ),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: AppSpacing.md12),
                child: Icon(icon, size: 14, color: t.textMuted),
              ),
        suffixIcon: shortcut == null
            ? null
            // 12 而不是 8：`suffixIcon` 在 contentPadding 之外，所以这一段要自己
            // 补上输入框的左右内距，胶囊才和左边的图标一样离边 12（1.4b）。
            : Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md12),
                child: ShortcutPill(shortcut!),
              ),
      ),
    );
  }
}

/// 快捷键胶囊：10px mono · r4 · `padding 2 6` · 控件底（1.4b / 2.2）。
class ShortcutPill extends StatelessWidget {
  final String label;
  const ShortcutPill(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 胶囊必须**贴着自己的内容**，不能被外面的约束撑开。它最常见的位置是输入框
    // 的 `suffixIcon`，而主题给那里的最小高度是控件的 32 —— 那个约束会原样传到
    // 这个 Container 上，一个没写死高度的 Container 就长到 32，胶囊变成一块和
    // 搜索框一样高的方砖。`Align` 给子节点的是宽松约束，于是它退回自己的尺寸。
    return Align(
      alignment: Alignment.center,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: t.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : AppPalette.ink.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Text(
          label,
          style: AppTypeScale.monoTiny.copyWith(color: t.textMuted),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 标签 · 徽标 · 分组标题
// ---------------------------------------------------------------------------

/// 语义标签胶囊。`padding 3 8` · r5 · 9.5–11px。
class AppTag extends StatelessWidget {
  final String label;
  final Color color;

  /// 实底还是「语义色底 + 语义色字」。
  final bool solid;
  final bool bordered;
  final bool mono;
  final IconData? icon;

  const AppTag({
    super.key,
    required this.label,
    required this.color,
    this.solid = false,
    this.bordered = true,
    this.mono = false,
    this.icon,
  });

  /// 中性标签，用控件底而不是语义色。
  factory AppTag.neutral(String label, {bool mono = false}) =>
      AppTag(label: label, color: _neutral, bordered: false, mono: mono);

  /// 「用控件底、不用语义色」的哨兵值。
  static const Color _neutral = Colors.transparent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isNeutral = color == _neutral;
    final fill = isNeutral
        ? t.controlFill
        : solid
        ? color
        : color.withValues(alpha: t.isDark ? 0.18 : 0.16);
    final fg = isNeutral
        ? t.textSecondary
        : solid
        ? Colors.white
        : _inkFor(color, t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: bordered && !isNeutral && !solid
            ? Border.all(color: color.withValues(alpha: 0.30))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            label,
            style:
                (mono
                        ? AppTypeScale.monoTiny
                        : const TextStyle(
                            fontSize: AppTypeScale.sizeLabel,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.05 * 10,
                            height: 1.3,
                          ))
                    .copyWith(color: fg),
          ),
        ],
      ),
    );
  }

  static Color _inkFor(Color c, AppTokens t) {
    if (c == t.success) return t.successText;
    if (c == t.warning) return t.warningText;
    if (c == t.danger) return t.dangerText;
    if (c == t.ai) return t.aiText;
    return t.accentText;
  }
}

/// 任务徽标：16 圆 · 9.5 mono · 强调色实底。
///
/// 全稿唯一「强调色实底 + 白字」的组合，所以文字色走 [AppTokens.badgeText]，
/// 它在 accent 亮度 > 0.72 时自动改用墨色 —— 用户把强调色换成亮黄也不会读不出来。
class AppCountBadge extends StatelessWidget {
  final int count;

  /// 失焦时保留强调色但降到 55%（它代表后台仍在运行）。
  final bool dimmed;

  const AppCountBadge(this.count, {super.key, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: AppSizes.taskBadge,
      height: AppSizes.taskBadge,
      decoration: BoxDecoration(
        color: dimmed
            ? t.badgeFill.withValues(alpha: AppTokens.unfocusedBadgeOpacity)
            : t.badgeFill,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontFamily: AppTypeScale.mono,
          fontSize: AppTypeScale.sizeLabel,
          fontWeight: FontWeight.w700,
          height: 1,
          color: t.badgeText,
        ),
      ),
    );
  }
}

/// 分组标题 GROUP LABEL：10px · 600 · 0.08em。
class AppGroupLabel extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;

  const AppGroupLabel(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.xs,
    ),
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      label,
      style: AppTypeScale.groupLabel.copyWith(color: context.tokens.textMuted),
    ),
  );
}

/// 1×20 的组间分隔线（2.2）。
class AppVerticalDivider extends StatelessWidget {
  final double height;
  final double margin;

  const AppVerticalDivider({
    super.key,
    this.height = AppSizes.dividerHeight,
    this.margin = AppSizes.dividerMargin,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    margin: EdgeInsets.symmetric(horizontal: margin),
    color: context.tokens.strokeStrong,
  );
}

// ---------------------------------------------------------------------------
// 段控 · 开关
// ---------------------------------------------------------------------------

/// 段控。外框 `padding 2–3` · r7–9，段 r5–6。
class AppSegmented<T> extends StatelessWidget {
  final List<(T value, String label)> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  /// 选中段用强调色渐变（设计稿在「替换」这类肯定语义上用它），
  /// 否则用中性 white 10%。
  final bool accentSelection;

  const AppSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 20,
    this.accentSelection = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : AppPalette.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadii.tiny + 1),
        border: Border.all(color: t.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in segments)
            _Segment(
              label: label,
              selected: v == value,
              accent: accentSelection,
              height: height,
              onTap: () => onChanged(v),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final bool accent;
  final double height;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.accent,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.respecting(context, AppMotion.hover),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
          decoration: BoxDecoration(
            color: !selected
                ? Colors.transparent
                : accent
                ? t.accent
                : t.controlFillHover,
            borderRadius: BorderRadius.circular(AppRadii.chip),
            boxShadow: selected && accent
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.30),
                      offset: const Offset(0, 1),
                      blurRadius: 0,
                      spreadRadius: -0.5,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTypeScale.sizeLabel,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: !selected
                  ? t.textMuted
                  : accent
                  ? t.badgeText
                  : t.textTitle,
            ),
          ),
        ),
      ),
    );
  }
}

/// 开关 34×20 / 38×22（设计稿两处都出现过）· r11。
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  const AppToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 34,
    this.height = 20,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final knob = height - 4;
    return MouseRegion(
      cursor: onChanged == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: AppMotion.respecting(context, AppMotion.hover),
          curve: AppMotion.standard,
          width: width,
          height: height,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? t.accent : t.strokeStrong,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: knob,
            height: knob,
            decoration: BoxDecoration(
              color: value ? Colors.white : Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1.4c 列表行
// ---------------------------------------------------------------------------

enum AppRowState { normal, hovered, selected, checked, running, failed, muted }

/// 单行 34 / 双行 44、圆角 9、行间距 2。整行可点，右侧操作只在悬停时出现。
///
/// 不用斑马纹；靠悬停与选中区分行 —— 斑马纹在可多选的列表里会和选中态打架。
class AppListRow extends StatefulWidget {
  final Widget child;

  /// 悬停才出现的行尾操作。
  final Widget? trailingOnHover;
  final bool selected;
  final bool checked;
  final bool failed;
  final bool muted;

  /// 0–1；> 0 时行底画一条 2px 强调色进度条。
  final double? progress;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final double height;
  final EdgeInsetsGeometry padding;

  const AppListRow({
    super.key,
    required this.child,
    this.trailingOnHover,
    this.selected = false,
    this.checked = false,
    this.failed = false,
    this.muted = false,
    this.progress,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.height = AppSizes.row,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
  });

  @override
  State<AppListRow> createState() => _AppListRowState();
}

class _AppListRowState extends State<AppListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final (fill, border) = switch (true) {
      _ when widget.failed => (t.dangerSurface, null),
      _ when widget.selected => (t.selectionFill, t.selectionStroke),
      _ when widget.checked => (t.accent.withValues(alpha: 0.10), null),
      _ when widget.progress != null => (
        t.isDark
            ? Colors.white.withValues(alpha: 0.04)
            : AppPalette.ink.withValues(alpha: 0.03),
        null,
      ),
      _ when _hover => (t.controlFill, null),
      _ => (Colors.transparent, null),
    };

    Widget row = AnimatedContainer(
      duration: AppMotion.respecting(context, AppMotion.hover),
      curve: AppMotion.standard,
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.icon),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(child: widget.child),
          if (widget.trailingOnHover != null && _hover) ...[
            const SizedBox(width: AppSpacing.md12),
            widget.trailingOnHover!,
          ],
        ],
      ),
    );

    if (widget.progress != null) {
      row = Stack(
        children: [
          row,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppRadii.icon),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widget.progress!.clamp(0.0, 1.0),
                  child: Container(height: 2, color: t.accent),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.muted) {
      row = Opacity(opacity: AppTokens.disabledRowOpacity, child: row);
    }

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (d) => widget.onSecondaryTap!(d.globalPosition),
        child: row,
      ),
    );
  }
}

/// 表头：10.5px / 600 / 0.06em，底部 1px 描边，随内容滚动吸顶。
class AppColumnHeader extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const AppColumnHeader({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md12,
      AppSpacing.md12,
      AppSpacing.md12,
      AppSpacing.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.stroke)),
      ),
      child: DefaultTextStyle(
        style: AppTypeScale.columnHeader.copyWith(color: t.textMuted),
        child: Row(children: children),
      ),
    );
  }
}
