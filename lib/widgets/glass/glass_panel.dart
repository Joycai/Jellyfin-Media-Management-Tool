import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A frosted translucent surface: blurs whatever is behind it, fills with a
/// theme-aware translucent tint, and draws a hairline border. The building
/// block for the app's three panes.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// Use the lighter sidebar fill instead of the default panel fill.
  final bool sidebar;
  final Color? fill;

  /// Optional tint wash drawn instead of the solid fill (e.g. the center
  /// table's blue→green diagonal). The blur and border still apply.
  final Gradient? gradient;

  /// Raise the panel with a soft drop shadow (for floating cards like the
  /// center table). Flush columns leave this off.
  final bool elevated;

  /// Whether to apply a [BackdropFilter] behind the panel. Top-level cards
  /// that float over the backdrop gradient want this (default); nested
  /// cards inside an already-blurred or already-opaque parent can disable
  /// it to skip the expensive blur pass.
  ///
  /// Asking for it is not the same as getting it: an opaque [fill] or
  /// [gradient] paints over the blurred backdrop, so the filter is dropped
  /// even here. See [_fillHidesBackdrop].
  final bool blur;

  /// The hairline border eats layout space on every side: a child that fills
  /// the panel gets the panel's width minus twice this. Anything measuring
  /// itself against the panel's outer constraints must subtract it, or its
  /// content is exactly `2 * borderWidth` too wide.
  static const borderWidth = 1.0;

  /// Whether the panel's own fill already covers everything behind it.
  ///
  /// A [BackdropFilter] blurs the backdrop and then paints its child on top,
  /// so an opaque child makes the blur invisible — the light theme's table
  /// gradient is exactly that case, its three stops all at full alpha. The
  /// blur is not cheap to throw away: it is a full-panel, multi-pass GPU
  /// filter re-run on every frame, at device resolution. So when the fill
  /// hides it, it is skipped rather than computed and painted over.
  ///
  /// Only fully opaque counts. A gradient extends its end colors past its
  /// stops, so every stop being opaque means every pixel is.
  static bool _fillHidesBackdrop(Gradient? gradient, Color fill) {
    if (gradient != null) return gradient.colors.every((c) => c.a >= 1.0);
    return fill.a >= 1.0;
  }

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 20,
    this.sidebar = false,
    this.fill,
    this.gradient,
    this.elevated = false,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    final resolvedFill =
        fill ?? (sidebar ? glass.sidebarFill : glass.panelFill);

    final fillBox = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient != null ? null : resolvedFill,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: glass.panelStroke, width: borderWidth),
      ),
      child: child,
    );

    final useBlur = blur && !_fillHidesBackdrop(gradient, resolvedFill);

    final panel = ClipRRect(
      borderRadius: borderRadius,
      child: useBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: glass.blurSigma,
                sigmaY: glass.blurSigma,
              ),
              child: fillBox,
            )
          : fillBox,
    );

    if (!elevated) return panel;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
            blurRadius: 28,
            spreadRadius: -6,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: panel,
    );
  }
}
