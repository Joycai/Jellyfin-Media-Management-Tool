import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The app's modal surface: the same liquid-glass language as `GlassPanel`,
/// tuned for a dialog floating over busy content.
///
/// Material's own `Dialog` paints `surfaceContainerHigh` washed with the seed
/// color's surface tint — a flat, tinted slab that matches nothing else in the
/// app. This surface instead blurs whatever is behind the dialog and lays a
/// **near-opaque** wash of the theme surface over it, with the glass hairline
/// stroke and a deep drop shadow. Near-opaque rather than `GlassPanel`'s
/// translucency because a dialog's job is to be read, and full glass over a
/// busy file table makes text swim; the ~8% that remains transparent is what
/// lets the backdrop's color breathe through and keeps it feeling like glass.
/// Drop-in replacement for [AlertDialog] on the glass surface.
///
/// Mirrors the [AlertDialog] parameters the app actually uses — [icon],
/// [title], [content], [actions] — so a migration is a class-name swap. The
/// layout follows the design language of the larger panels instead of
/// Material's: icon and title share a header row, and the whole card sits on
/// [GlassDialogSurface] rather than the tinted Material slab.
class GlassAlertDialog extends StatelessWidget {
  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// Outer cap on the card. Content narrower than this sizes the card down,
  /// same as [AlertDialog].
  final double maxWidth;

  const GlassAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.maxWidth = 560,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GlassDialogSurface(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null || icon != null) ...[
                  Row(
                    children: [
                      if (icon != null) ...[icon!, const SizedBox(width: 12)],
                      if (title != null)
                        Expanded(
                          // merge, not replace: a plain DefaultTextStyle here
                          // would drop the ambient fontFamily (the user's UI
                          // font) along with everything else it doesn't set.
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                            child: title!,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (content != null)
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                      child: content!,
                    ),
                  ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassDialogSurface extends StatelessWidget {
  final Widget child;
  final double radius;

  const GlassDialogSurface({super.key, required this.child, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
            blurRadius: 60,
            spreadRadius: -12,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glass.blurSigma,
            sigmaY: glass.blurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: isDark ? 0.92 : 0.97),
              borderRadius: borderRadius,
              border: Border.all(color: glass.panelStroke),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 全应用模态对话框的唯一入口,与 [showGlassMenu] 对称:统一入场动画
/// (fade + 0.96→1 缩放),调用点不再各自决定转场。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
