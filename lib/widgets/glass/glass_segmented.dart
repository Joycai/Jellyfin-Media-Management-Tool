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
                  decoration: BoxDecoration(
                    color: item.value == value
                        ? t.selectionFill
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.tiny),
                    border: Border.all(
                      color: item.value == value
                          ? t.selectionStroke
                          : Colors.transparent,
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
