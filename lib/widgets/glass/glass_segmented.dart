import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: glass.panelStroke),
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
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(item.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.ease,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: item.value == value
                        ? scheme.primary.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: item.value == value
                        ? Border.all(
                            color: scheme.primary.withValues(alpha: 0.35),
                          )
                        : Border.all(color: Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.icon != null) ...[
                        Icon(
                          item.icon,
                          size: 13,
                          color: item.value == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: item.value == value
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: item.value == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
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
