import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// A pill-style segmented toggle that fits the liquid-glass design system.
///
/// Generic over [T] so callers can use int indices, enums, or any value type.
/// Items may optionally carry an [IconData].
class GlassSegmented<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final List<GlassSegmentedItem<T>> items;

  const GlassSegmented({
    super.key,
    required this.value,
    required this.onChanged,
    required this.items,
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
        borderRadius: BorderRadius.circular(AppRadii.icon),
        border: Border.all(color: t.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            Semantics(
              selected: item.value == value,
              button: true,
              label: item.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.tiny),
                onTap: () => onChanged(item.value),
                child: AnimatedContainer(
                  duration: AppMotion.respecting(context, AppMotion.hover),
                  curve: AppMotion.standard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md12,
                    vertical: AppSpacing.xxs,
                  ),
                  // 未选中态用的是**同色的 alpha 0**，不是 `Colors.transparent`
                  // ——「透明」在 Flutter 里是透明的黑，而 `Color.lerp` 不做预乘，
                  // 逐通道补间会从中灰穿过去：切换分段时先闪一下深灰。
                  decoration: BoxDecoration(
                    color: item.value == value
                        ? t.selectionFill
                        : t.selectionFill.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(AppRadii.tiny),
                    border: Border.all(
                      color: item.value == value
                          ? t.selectionStroke
                          : t.selectionStroke.withValues(alpha: 0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.icon != null) ...[
                        Icon(
                          item.icon,
                          size: 13,
                          color: item.value == value
                              ? t.textTitle
                              : t.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Text(
                        item.label,
                        style: AppTypeScale.caption.copyWith(
                          fontWeight: item.value == value
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: item.value == value
                              ? t.textTitle
                              : t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class GlassSegmentedItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const GlassSegmentedItem({
    required this.value,
    required this.label,
    this.icon,
  });
}
