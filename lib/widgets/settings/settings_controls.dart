import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';

// ── 6.x 设置页共用的版式积木 ────────────────────────────────────────────────
//
// 设计稿的七个设置页是同一套骨架反复用：分组标题 → 卡片 → 卡内若干行。把它收
// 在这里而不是每页各写一遍，是因为「行高 / 分隔线 / 小按钮」这类东西一旦各页
// 各写，几天之后就会有七种略微不同的行高 —— 那正是这次重做要消灭的东西。
//
// 设计稿里 18 / 26 / 9 这类介于两级之间的取值一律吸附到 1.3 的刻度上
// （18→16、26→28、9→8）：整套界面统一到刻度上，比逐处复刻更贴近「规格统一」
// 这个要求本身。

/// 内容区容器：`padding 22 24`（6.x 骨架写的是 22 28，28 不在 1.3a 的刻度上）。
class SettingsPage extends StatelessWidget {
  final List<Widget> children;

  const SettingsPage({super.key, required this.children});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl24,
      vertical: AppSpacing.xl,
    ),
    children: children,
  );
}

/// 分组标题：10.5 / 700 / 0.06em，下留 10。
class SettingsSectionTitle extends StatelessWidget {
  final String text;

  /// 右侧的行动点（「清除记录」「全部清理」这类）。
  final Widget? trailing;

  const SettingsSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SizedBox(
        // 固定高度：带行动按钮和不带的标题必须一样高，否则并排两列的分组会错开
        // 一个按钮的高度。
        height: AppSizes.controlSm,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: AppTypeScale.columnHeader.copyWith(
                  fontWeight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 内容卡：r14 · 卡片底 · 发丝描边。
class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: t.stroke),
      ),
      child: child,
    );
  }
}

/// 行列表卡：卡内每行之间一条发丝线，最后一行不带线。
///
/// 卡的上下内距因此收到 6 —— 行自己带 8 的上下内距，两者叠满就成了 24。
class SettingsRowsCard extends StatelessWidget {
  final List<Widget> children;

  /// 卡内的分组标题（画板 21–24 把标题画在卡里，而不是卡上方）。它和行之间不划
  /// 发丝线 —— 发丝线是行与行的分隔，标题不是一行。
  final Widget? header;

  /// 行在多出来的高度上均匀铺开（设计稿短卡上的 `justify-content:
  /// space-between`）。两列共用行轨道之后，一行里矮的那张卡会被拉到和高的那张
  /// 一样高，多出来的高度总得有个去处 —— 全堆在卡底会让卡看上去空了半截。
  ///
  /// 卡没被拉高时（自然高度）这个开关什么也不做。
  final bool spread;

  /// 钉在卡底的一块：说明、合计行、动作按钮。等高的一行里两张卡不一样满，这一
  /// 块要贴着卡底，而不是跟着最后一行浮在半空。
  final Widget? footer;

  /// [footer] 上方的那条发丝线。设计稿的说明与合计行有（`border-top`），
  /// 「＋ 添加根目录」那一排按钮没有。
  final bool footerDivider;

  const SettingsRowsCard({
    super.key,
    required this.children,
    this.header,
    this.spread = false,
    this.footer,
    this.footerDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    // 发丝线跟在它上面那一行的下面，而不是单独插在两行之间：`spread` 把余量摊在
    // 子项之间，线要是自己算一个子项，就会从行上脱开、浮在两行正中。
    final hairlineAfterLast = footer != null && footerDivider;
    final blocks = <Widget>[
      ?header,
      for (final (i, child) in children.indexed)
        if (i == children.length - 1 && !hairlineAfterLast)
          child
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [child, const SettingsDivider()],
          ),
    ];
    return SettingsCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // 对齐方式在 `MainAxisSize.min` 之下仍然生效：卡被拉到一行的高度时约束
        // 是紧的，Column 只能是那个高度，余量照样摊给对齐方式。没被拉高时余量
        // 是 0，选什么都一样。
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: spread || footer != null
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          if (spread)
            ...blocks
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: blocks,
            ),
          ?footer,
        ],
      ),
    );
  }
}

/// 卡内标题行。
///
/// 与卡外的 [SettingsSectionTitle] 同一档字（10.5 / 700 / 0.06em），但不占那
/// 28 的固定高：固定高存在的理由是让并排两列的分组对齐，而卡内没有这个问题。
/// [emphasis] 换成 12.5 / 600 的卡片标题档 —— 画板 24 的「图形设备」用的是它。
class SettingsCardHeader extends StatelessWidget {
  final String text;

  /// 紧跟在标题后面的徽标。它属于标题，不属于右边那一栏 —— 画板 24 的卡头上
  /// 只有旁注带 `margin-left:auto`，徽标是标题的一部分。
  final Widget? badge;

  final Widget? trailing;
  final bool emphasis;

  const SettingsCardHeader(
    this.text, {
    super.key,
    this.badge,
    this.trailing,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      // 固定高，理由同 [SettingsSectionTitle]：带文字链的卡头和不带的必须一样
      // 高，否则并排两张卡的标题会差一个按钮的高度。
      height: AppSizes.controlXs + AppSpacing.md12,
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            text,
            style: emphasis
                ? AppTypeScale.controlStrong.copyWith(color: t.textTitle)
                : AppTypeScale.columnHeader.copyWith(
                    fontWeight: FontWeight.w700,
                    color: t.textMuted,
                  ),
          ),
          if (badge != null) ...[const SizedBox(width: AppSpacing.md), badge!],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 卡内一行：`padding 8 0` · gap 10。
class SettingsRow extends StatelessWidget {
  /// 26 见方的图标底（吸到 28）。
  final Widget? leading;
  final String title;

  /// 第二行，通常是 mono 的路径。
  final String? subtitle;
  final bool subtitleMono;

  /// 行尾：计数、状态徽标、小按钮。
  final List<Widget> trailing;

  const SettingsRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleMono = true,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.control.copyWith(color: t.textTitle),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (subtitleMono
                                ? context.tokens.monoSmall
                                : AppTypeScale.caption)
                            .copyWith(color: t.textMuted),
                  ),
                ],
              ],
            ),
          ),
          for (final w in trailing) ...[
            const SizedBox(width: AppSpacing.md),
            w,
          ],
        ],
      ),
    );
  }
}

/// 行尾的 28 高小按钮（设计稿 h26，吸到 [AppSizes.controlSm]）。
class SettingsMiniButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// 强调色变体：「＋ 添加根目录」这类新增动作。
  final bool accent;

  const SettingsMiniButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    height: AppSizes.controlSm,
    kind: accent ? AppButtonKind.primary : AppButtonKind.secondary,
  );
}

/// 26 见方的图标底（吸到 28）：语义色 14% + r8。
class SettingsRowIcon extends StatelessWidget {
  final IconData icon;
  final Color? tint;

  const SettingsRowIcon(this.icon, {super.key, this.tint});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = tint ?? t.accent;
    return Container(
      width: AppSizes.controlSm,
      height: AppSizes.controlSm,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: color),
    );
  }
}

/// 开关行：13px 文案 + 可选说明 + 右侧 34×20 开关。
class SettingsToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;

  /// null = 占位：设计稿有、应用还做不到的开关，画出来但按不动。
  final ValueChanged<bool>? onChanged;

  const SettingsToggleRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypeScale.body.copyWith(
                    color: enabled ? t.textTitle : t.textDisabled,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypeScale.caption.copyWith(color: t.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          AppToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 两列布局：左列略宽（设计稿 `1.12fr 1fr`），gap 16。
class SettingsColumns extends StatelessWidget {
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;

  /// 两列等高。设计稿的两列是 CSS grid，同一行的格子默认拉伸到等高 —— 一行里
  /// 并排的两张卡下沿不齐，看上去就像右边那张画漏了。
  ///
  /// 用 `IntrinsicHeight` 而不是 `CrossAxisAlignment.stretch`：在 `ListView`
  /// 里交叉轴是无界的，stretch 会直接抛，整页空掉而控制台一声不响。代价是列内
  /// 每个子项都得答得出固有高度（`LayoutBuilder` 答不出，见
  /// `ContextWindowSlider.height`）。
  final bool equalHeight;

  const SettingsColumns({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 112,
    this.rightFlex = 100,
    this.equalHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: equalHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        const SizedBox(width: AppSpacing.lg),
        Expanded(flex: rightFlex, child: right),
      ],
    );
    return equalHeight ? IntrinsicHeight(child: row) : row;
  }
}

/// 卡底 / 分组底的一行说明：11.5px · 次要色。
class SettingsFootnote extends StatelessWidget {
  final String text;

  const SettingsFootnote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      text,
      style: AppTypeScale.caption.copyWith(
        color: context.tokens.textMuted,
        height: AppTypeScale.leadingBody,
      ),
    ),
  );
}

/// 设计稿有、应用还做不到的模块。
///
/// 按设计稿的版式照画，但整体压暗、不可交互，并在分组标题右边挂一枚「即将推出」
/// 标签。既不假装能用，也不从界面里悄悄消失 —— 后者会让人以为这块能力根本不在
/// 计划内。清单见 `docs/spec/ui-redesign/backlog.md`。
class SettingsPlaceholder extends StatelessWidget {
  final Widget child;

  const SettingsPlaceholder({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: Opacity(opacity: 0.55, child: child));
}

/// 挂在分组标题右侧的「即将推出」标签。
class SettingsSoonTag extends StatelessWidget {
  final String label;

  const SettingsSoonTag(this.label, {super.key});

  @override
  Widget build(BuildContext context) =>
      AppTag(label: label, color: context.tokens.warning);
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.tokens.stroke);
}
