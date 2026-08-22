import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Context menus on the glass surface.
///
/// [showGlassMenu] positions and skins the menu — surface color, hairline
/// stroke, radius, shadow — so call sites never repeat that block, and the
/// entry builders below give every menu in the app the same row anatomy:
/// a 15px leading icon, a 12.5px label, an optional monospace trailing hint
/// (a file name, a shortcut), and a primary-tinted pill when the row is the
/// current state. One place to change, every menu follows.
Future<T?> showGlassMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
  double minWidth = 220,
}) {
  final glass = Theme.of(context).extension<GlassTheme>()!;
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  return showMenu<T>(
    context: context,
    popUpAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      reverseDuration: Duration(milliseconds: 120),
    ),
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    color: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 16,
    shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.25),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: glass.panelStroke),
    ),
    constraints: BoxConstraints(minWidth: minWidth),
    items: items,
  );
}

/// A small-caps section caption, per the design's "标记为 JELLYFIN 图片" row.
PopupMenuEntry<T> glassMenuHeader<T>(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  return PopupMenuItem<T>(
    enabled: false,
    height: 28,
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One actionable row.
///
/// [selected] marks the row that reflects the current state (the assigned
/// role, the active sort…): it gets the primary-tinted pill the design shows,
/// not a radio circle. [color] overrides the whole foreground for destructive
/// rows; [iconColor] tints only the icon, the design's way of coding a row by
/// what it touches (a yellow folder, a primary-colored scrape) while the
/// label stays readable. [trailing] is the monospace hint column — a file
/// name, a keyboard shortcut.
PopupMenuEntry<T> glassMenuItem<T>(
  BuildContext context, {
  required T value,
  IconData? icon,
  required String label,
  String? trailing,
  bool selected = false,
  Color? color,
  Color? iconColor,
}) {
  final scheme = Theme.of(context).colorScheme;
  final labelColor = color ?? (selected ? scheme.primary : scheme.onSurface);
  // Icons default to the muted tone: the design's rows read label-first, and
  // a column of full-brightness glyphs competes with the text.
  final leadColor =
      iconColor ??
      color ??
      (selected ? scheme.primary : scheme.onSurfaceVariant);

  return PopupMenuItem<T>(
    value: value,
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: selected
          ? BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: leadColor),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color:
                      color?.withValues(alpha: 0.8) ?? scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
