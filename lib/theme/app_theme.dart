import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// 从 [AppTokens] 构建 Material 主题。
///
/// 这里**不再定义任何取值** —— 每一个颜色、圆角、高度、字号都来自
/// `design_tokens.dart`。Material 自带的控件主题（输入框、按钮、滑块、对话框）
/// 被配成与设计稿 1.4 一致，这样即便某个还没迁移的界面用的是裸 Material 控件，
/// 它也已经落在设计系统里，而不是 Material 的 seed 色板上。
class AppTheme {
  /// 08 设置页的强调色预设（前五个，第六个是自定义取色）。
  static const List<Color> accentPresets = [
    AppPalette.accent,
    AppPalette.ai,
    AppPalette.success,
    Color(0xFFFF8A5B),
    Color(0xFF6F69FF),
  ];

  static ThemeData light({
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
    bool reduceEffects = false,
  }) => _build(
    Brightness.light,
    accent: accent,
    glassIntensity: glassIntensity,
    fontFamily: fontFamily,
    reduceEffects: reduceEffects,
  );

  static ThemeData dark({
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
    bool reduceEffects = false,
  }) => _build(
    Brightness.dark,
    accent: accent,
    glassIntensity: glassIntensity,
    fontFamily: fontFamily,
    reduceEffects: reduceEffects,
  );

  /// 每个亮度记住上一次构建的结果。
  ///
  /// `MyApp.build` 每次 `SettingsService` / `FontService` 通知都会同时要一份浅色
  /// 和一份深色主题 —— 收藏被切换、最近被压栈、列宽被拖动。这些调用的入参几乎
  /// 总是一样的，重建不仅白做，还会给 `MaterialApp` 一个新的 `ThemeData` 身份，
  /// 把 `Theme.of` 之下的一切重建一遍。
  ///
  /// 每个亮度一格正合适：重复调用完全相同因此命中，而真正的变化（拖玻璃强度
  /// 滑块）落空并付出它本来就该付的代价。按入参做 Map 反而会每拖一个像素长一条。
  static final Map<Brightness, (String, ThemeData)> _memo = {};

  static ThemeData _build(
    Brightness brightness, {
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
    bool reduceEffects = false,
  }) {
    final key =
        '${accent?.toARGB32()}|$glassIntensity|$fontFamily|$reduceEffects';
    final cached = _memo[brightness];
    if (cached != null && cached.$1 == key) return cached.$2;
    final built = _buildUncached(
      brightness,
      accent: accent,
      glassIntensity: glassIntensity,
      fontFamily: fontFamily,
      reduceEffects: reduceEffects,
    );
    _memo[brightness] = (key, built);
    return built;
  }

  static ThemeData _buildUncached(
    Brightness brightness, {
    Color? accent,
    double? glassIntensity,
    String? fontFamily,
    bool reduceEffects = false,
  }) {
    final t = AppTokens.build(
      brightness: brightness,
      accent: accent,
      glassIntensity: glassIntensity ?? 70,
      reduceEffects: reduceEffects,
      uiFont: fontFamily,
    );
    final isDark = t.isDark;
    // 「系统默认」= 字族交给引擎，中文回落照旧。
    // 选了自定义字体 = 它**只接管中文**：系统的拉丁字体排首位，自定义字体排在
    // 它后面，靠「这个字族里没有这个字形」自然分流。见 [AppTypeScale.latinUi]。
    final cjk = AppTypeScale.cjkFallback(defaultTargetPlatform);
    final latin = AppTypeScale.latinUi(defaultTargetPlatform);
    final family = fontFamily == null ? null : latin.first;
    final fallback = fontFamily == null
        ? cjk
        : [...latin.skip(1), fontFamily, ...cjk];

    final scheme =
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: brightness,
        ).copyWith(
          primary: t.accent,
          onPrimary: t.badgeText,
          secondary: t.success,
          tertiary: t.ai,
          error: t.danger,
          onError: isDark ? AppPalette.darkBase : Colors.white,
          surface: isDark ? const Color(0xFF16182B) : Colors.white,
          onSurface: t.textBody,
          onSurfaceVariant: t.textSecondary,
          outline: t.strokeStrong,
          outlineVariant: t.stroke,
        );

    // ButtonStyle.textStyle 是**替换**而不是合并，裸 TextStyle 会把用户选的
    // 界面字体从每个按钮上悄悄抹掉。字族与中文回落必须显式带上。
    TextStyle text(TextStyle base) =>
        base.copyWith(fontFamily: family, fontFamilyFallback: fallback);

    OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.button),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      dividerColor: t.stroke,
      splashFactory: NoSplash.splashFactory,
      // 1.4f：只动不透明度、底色与 4px 内的位移；不做缩放、不做弹性曲线。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: _DesktopPageTransitionsBuilder(),
          TargetPlatform.linux: _DesktopPageTransitionsBuilder(),
          TargetPlatform.macOS: _DesktopPageTransitionsBuilder(),
        },
      ),
      // 1.4b 输入框：高 32、圆角 10、内距 12。
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: t.controlFill,
        hintStyle: text(AppTypeScale.control).copyWith(color: t.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md12,
          vertical: AppSpacing.sm,
        ),
        // Material 给前缀图标的 48px 最小高度会把同一行里的两个输入框顶得不
        // 一样高；顶栏的搜索框和刮削面板都踩过这个坑。
        prefixIconConstraints: const BoxConstraints(
          minWidth: 30,
          minHeight: AppSizes.control,
          maxHeight: AppSizes.control,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 24,
          minHeight: AppSizes.control,
          maxHeight: AppSizes.control,
        ),
        constraints: const BoxConstraints(minHeight: AppSizes.control),
        enabledBorder: fieldBorder(Colors.transparent),
        border: fieldBorder(Colors.transparent),
        focusedBorder: fieldBorder(t.accent.withValues(alpha: 0.55)),
        errorBorder: fieldBorder(t.danger.withValues(alpha: 0.50)),
        focusedErrorBorder: fieldBorder(t.danger.withValues(alpha: 0.70)),
        disabledBorder: fieldBorder(Colors.transparent),
        errorStyle: text(
          const TextStyle(fontSize: 11),
        ).copyWith(color: t.dangerText),
      ),
      // 1.4a 按钮：高 32、圆角 8、左右内距 14。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizes.control),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: text(AppTypeScale.controlStrong),
          backgroundColor: t.accent,
          foregroundColor: t.badgeText,
          disabledBackgroundColor: t.accentDisabled,
          disabledForegroundColor: t.badgeText.withValues(alpha: 0.55),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.control),
          shape: buttonShape,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: text(AppTypeScale.controlStrong),
          backgroundColor: t.controlFill,
          foregroundColor: t.textBody,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.control),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: text(AppTypeScale.control),
          foregroundColor: t.textBody,
          backgroundColor: t.controlFill,
          side: BorderSide(color: t.strokeStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSizes.controlSm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: text(AppTypeScale.control),
          foregroundColor: t.accentText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSizes.control, AppSizes.control),
          fixedSize: const Size(AppSizes.control, AppSizes.control),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.icon),
          ),
          foregroundColor: t.textSecondary,
          backgroundColor: t.controlFill,
          hoverColor: t.controlFillHover,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(text(AppTypeScale.caption)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.tiny),
            ),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        side: BorderSide(color: t.strokeStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? t.accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(t.badgeText),
        visualDensity: VisualDensity.compact,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.strokeStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: t.accent,
        inactiveTrackColor: t.strokeStrong,
        thumbColor: Colors.white,
        overlayColor: t.accent.withValues(alpha: 0.16),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xF216182B) : const Color(0xF21A1D29),
          borderRadius: BorderRadius.circular(AppRadii.button),
          border: Border.all(color: t.strokeStrong),
        ),
        textStyle: text(AppTypeScale.caption).copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      ),
      // 1.4e：对话框与菜单应当走 GlassAlertDialog / showGlassMenu，它们额外带
      // 背景模糊。这里配成同一套取值，是为了让还没迁移的裸 Material 面也落在
      // 设计系统里 —— 安全网，不是替代品。
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: t.strokeStrong),
        ),
        titleTextStyle: text(AppTypeScale.title).copyWith(color: t.textTitle),
        contentTextStyle: text(
          const TextStyle(fontSize: 12, height: AppTypeScale.leadingBody),
        ).copyWith(color: t.textSecondary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: t.strokeStrong),
        ),
        textStyle: text(AppTypeScale.control).copyWith(color: t.textBody),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(color: t.strokeStrong),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xF016182B)
            : const Color(0xF01A1D29),
        contentTextStyle: text(
          AppTypeScale.control,
        ).copyWith(color: Colors.white),
        actionTextColor: AppPalette.accentOnDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl24),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.strokeStrong,
        linearMinHeight: 4,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          (isDark ? Colors.white : AppPalette.ink).withValues(alpha: 0.18),
        ),
      ),
      textTheme: _textTheme(t, text),
      fontFamily: family,
      // 拉丁字形保留系统默认的清晰度；中文字形（Windows 的默认字体没有）回落到
      // 用户挑的那款，没挑就回落到各平台的旗舰界面字体。
      fontFamilyFallback: fallback,
      extensions: [t],
    );
  }

  static TextTheme _textTheme(
    AppTokens t,
    TextStyle Function(TextStyle) text,
  ) => TextTheme(
    displaySmall: text(AppTypeScale.display).copyWith(color: t.textTitle),
    headlineSmall: text(AppTypeScale.heading).copyWith(color: t.textTitle),
    titleMedium: text(AppTypeScale.title).copyWith(color: t.textTitle),
    titleSmall: text(AppTypeScale.controlStrong).copyWith(color: t.textTitle),
    bodyMedium: text(AppTypeScale.body).copyWith(color: t.textBody),
    bodySmall: text(AppTypeScale.caption).copyWith(color: t.textSecondary),
    labelLarge: text(AppTypeScale.control).copyWith(color: t.textBody),
    labelMedium: text(AppTypeScale.caption).copyWith(color: t.textSecondary),
    labelSmall: text(AppTypeScale.groupLabel).copyWith(color: t.textMuted),
  );
}

/// 整页路由。转场时长走设计规范，而不是 Material 的默认值。
///
/// `MaterialPageRoute` 硬编码 300ms，而 1.4f 的动效档位只有
/// 80 / 100 / 120 / 180 / 240 —— 对话框和 popover 都老实用了 [AppMotion]，
/// 只有整页路由漏在外面。180ms 同时也少付 40% 的转场帧：那段时间里上下两棵树
/// 同时绘制，是全应用最贵的一段（见 `GlassCoverScope`）。
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration => AppMotion.panel;

  @override
  Duration get reverseTransitionDuration => AppMotion.panel;
}

/// 桌面端页面转场：淡入 + 1.5% 上浮。
///
/// 默认的 `ZoomPageTransitionsBuilder` 是安卓的放大浮入，在桌面窗口里像手机
/// 应用；这里换成桌面惯用的快速淡入，且不动退场中的旧页面。
class _DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const _DesktopPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
