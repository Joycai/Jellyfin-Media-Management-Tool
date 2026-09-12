import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// 上下文菜单（1.4e）。
///
/// 圆角 12、描边 white 10%、投影 L3；菜单项高 30、左右内距 12、图标列宽 18、
/// 快捷键 10px mono。[showGlassMenu] 负责定位与皮肤，下面的构造器给全应用的菜单
/// 同一套行结构 —— 改一处，所有菜单跟着走。
///
/// 出现 120ms 向下 4px 淡入，关闭 100ms 向上 4px 淡出（1.4e）。**不做缩放**：
/// 1.4f 明确排除缩放与弹性曲线，一个从 96% 弹出来的菜单在桌面上像手机应用。
Future<T?> showGlassMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
  double minWidth = 220,
}) {
  final t = context.tokens;
  final scheme = Theme.of(context).colorScheme;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  return showMenu<T>(
    context: context,
    popUpAnimationStyle: AnimationStyle(
      duration: AppMotion.respecting(context, AppMotion.overlayIn),
      curve: AppMotion.standard,
      reverseDuration: AppMotion.respecting(context, AppMotion.overlayOut),
    ),
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    color: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: t.strokeStrong),
    ),
    // 5px 内距 —— 设计稿的菜单面板四周留一圈，选中项的圆角块才不会贴边。
    menuPadding: const EdgeInsets.all(5),
    constraints: BoxConstraints(minWidth: minWidth),
    items: items,
  );
}

/// 分组标题，对应设计稿的「标记为 JELLYFIN 图片」一行。
PopupMenuEntry<T> glassMenuHeader<T>(BuildContext context, String text) {
  final t = context.tokens;
  return PopupMenuItem<T>(
    enabled: false,
    height: 24,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md12,
      AppSpacing.xs,
      AppSpacing.md12,
      0,
    ),
    child: Text(
      text,
      style: AppTypeScale.groupLabel.copyWith(color: t.textMuted),
    ),
  );
}

/// 一个可点的菜单行。
///
/// [selected] 标记「当前状态」的那一行（已指派的角色、当前排序……）：设计稿给它
/// 的是一块强调色药丸，不是单选圆点。[color] 覆盖整行前景色（危险项）；
/// [iconColor] 只染图标 —— 设计稿用它按「这一项动什么」编码（黄色文件夹、
/// 强调色刮削），标签本身保持可读。[trailing] 是右侧的等宽提示列（文件名、快捷键）。
PopupMenuEntry<T> glassMenuItem<T>(
  BuildContext context, {
  required T value,
  IconData? icon,
  required String label,
  String? trailing,
  bool selected = false,
  Color? color,
  Color? iconColor,
  bool enabled = true,
}) {
  final t = context.tokens;
  final labelColor = !enabled
      ? t.textDisabled
      : color ?? (selected ? t.textTitle : t.textBody);
  // 图标默认取次要色：设计稿的行是「标签优先」的，一列满亮度的字形会和文字
  // 争注意力。
  final leadColor = !enabled
      ? t.textDisabled
      : iconColor ?? color ?? (selected ? t.textTitle : t.textSecondary);

  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: AppSizes.menuItemHeight,
    padding: EdgeInsets.zero,
    child: Container(
      height: AppSizes.menuItemHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
      decoration: selected
          ? BoxDecoration(
              color: t.accent.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(AppRadii.button),
              border: Border.all(color: t.accent.withValues(alpha: 0.25)),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: AppSizes.menuIconColumn,
            child: icon == null ? null : Icon(icon, size: 13, color: leadColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.control.copyWith(
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypeScale.monoTiny.copyWith(
                  color: color?.withValues(alpha: 0.5) ?? t.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 菜单分隔线：1px，左右各留 8（1.4e）。
PopupMenuEntry<T> glassMenuDivider<T>(BuildContext context) => PopupMenuItem<T>(
  enabled: false,
  height: 11,
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
  child: Divider(height: 1, thickness: 1, color: context.tokens.strokeStrong),
);
