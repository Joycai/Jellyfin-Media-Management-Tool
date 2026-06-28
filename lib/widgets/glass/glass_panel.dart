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
  final bool blur;

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

    final fillBox = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient != null ? null : (fill ?? (sidebar ? glass.sidebarFill : glass.panelFill)),
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: glass.panelStroke),
      ),
      child: child,
    );

    final panel = ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: glass.blurSigma, sigmaY: glass.blurSigma),
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
