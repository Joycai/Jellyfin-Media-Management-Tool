import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// Carries the "liquid glass" tokens (panel fill, hairline border, accents and
/// the scaffold backdrop gradient) so every widget can theme consistently and
/// adapt to light/dark without hardcoding colors.
@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  final Gradient backdrop;
  final Color panelFill;
  final Color panelStroke;
  final Color rowSelected;
  final Color sidebarFill;
  final double blurSigma;

  const GlassTheme({
    required this.backdrop,
    required this.panelFill,
    required this.panelStroke,
    required this.rowSelected,
    required this.sidebarFill,
    required this.blurSigma,
  });

  @override
  GlassTheme copyWith({
    Gradient? backdrop,
    Color? panelFill,
    Color? panelStroke,
    Color? rowSelected,
    Color? sidebarFill,
    double? blurSigma,
  }) => GlassTheme(
    backdrop: backdrop ?? this.backdrop,
    panelFill: panelFill ?? this.panelFill,
    panelStroke: panelStroke ?? this.panelStroke,
    rowSelected: rowSelected ?? this.rowSelected,
    sidebarFill: sidebarFill ?? this.sidebarFill,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    return GlassTheme(
      backdrop: Gradient.lerp(backdrop, other.backdrop, t) ?? backdrop,
      panelFill: Color.lerp(panelFill, other.panelFill, t)!,
      panelStroke: Color.lerp(panelStroke, other.panelStroke, t)!,
      rowSelected: Color.lerp(rowSelected, other.rowSelected, t)!,
      sidebarFill: Color.lerp(sidebarFill, other.sidebarFill, t)!,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class AppTheme {
  // Default accent trio sampled from the design mockups: a vivid blue primary,
  // a violet for the brand/secondary accents, and a teal for confidence cues.
  static const Color _blue = Color(0xFF3B6FF5);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _teal = Color(0xFF22C9A9);

  /// Built-in accent presets shown in the Appearance section's color picker.
  static const List<Color> accentPresets = [
    _blue,
    Color(0xFF8B5CF6), // violet
    Color(0xFF22C9A9), // teal
    Color(0xFFEE7B3A), // orange
    Color(0xFF6F69FF), // indigo
  ];

  /// Build a theme. [accent] overrides the primary swatch; [glassIntensity]
  /// (0–100) scales the backdrop blur on `GlassTheme`; [fontFamily] overrides
  /// the default UI typeface (must already be registered via `FontLoader`).
  /// All null = defaults.
  static ThemeData light({
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
  }) => _build(
    Brightness.light,
    accent: accent,
    glassIntensity: glassIntensity,
    fontFamily: fontFamily,
  );

  static ThemeData dark({
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
  }) => _build(
    Brightness.dark,
    accent: accent,
    glassIntensity: glassIntensity,
    fontFamily: fontFamily,
  );

  static ThemeData _build(
    Brightness brightness, {
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
  }) {
    final isDark = brightness == Brightness.dark;
    final primary = accent ?? _blue;
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );

    final scheme = base.copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: _teal,
      tertiary: _violet,
      surface: isDark ? const Color(0xFF191A33) : base.surface,
      onSurface: isDark ? const Color(0xFFE8EAF5) : base.onSurface,
      onSurfaceVariant: isDark
          ? const Color(0xFFADB2D0)
          : base.onSurfaceVariant,
    );

    final glass = isDark ? _darkGlass : _lightGlass;
    final scaledGlass = glassIntensity == null
        ? glass
        // 70 (default mockup value) maps to the original 24 sigma; cap at 48.
        : glass.copyWith(
            blurSigma: (glassIntensity / 70 * 24).clamp(0.0, 48.0),
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      // User-selected UI font (HarmonyOS Sans / MiSans); null = OS default.
      fontFamily: fontFamily,
      // Latin glyphs keep the crisp OS default; CJK glyphs (missing from that
      // default on Windows) resolve to each platform's flagship UI font so
      // Chinese renders in a mainstream, well-hinted typeface everywhere.
      fontFamilyFallback: _cjkFontFallback,
      extensions: [scaledGlass],
    );
  }

  /// Per-platform stack of high-quality, pre-installed Chinese UI fonts, tried
  /// in order for any glyph the primary font can't render:
  /// 微软雅黑 on Windows, 苹方 (PingFang) on macOS, Noto/文泉驿 on Linux.
  static List<String> get _cjkFontFallback {
    if (Platform.isWindows) {
      return const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Noto Sans SC'];
    }
    if (Platform.isMacOS) {
      return const ['PingFang SC', 'Heiti SC', 'Noto Sans SC'];
    }
    // Linux and any other target.
    return const [
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'Source Han Sans SC',
      'WenQuanYi Micro Hei',
    ];
  }

  static const GlassTheme _darkGlass = GlassTheme(
    backdrop: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF14122E), Color(0xFF1A1840), Color(0xFF0F2E2B)],
      stops: [0.0, 0.5, 1.0],
    ),
    panelFill: Color(0x14FFFFFF),
    panelStroke: Color(0x1FFFFFFF),
    rowSelected: Color(0x335B6CFF),
    sidebarFill: Color(0x33000000),
    blurSigma: 24,
  );

  static const GlassTheme _lightGlass = GlassTheme(
    backdrop: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE7E9F2), Color(0xFFECEAF4), Color(0xFFE6F1EC)],
      stops: [0.0, 0.5, 1.0],
    ),
    // Center cards are crisp near-white so they pop off the neutral backdrop
    // (the soft shadow does the separating, not translucency).
    panelFill: Color(0xF5FFFFFF),
    panelStroke: Color(0x12101430),
    rowSelected: Color(0x1A4F6BFF),
    // Flush columns (sidebar, AI panel, header) stay lightly translucent so the
    // backdrop's faint lavender→mint shows through, like the mockup.
    sidebarFill: Color(0xCCFFFFFF),
    blurSigma: 24,
  );
}
