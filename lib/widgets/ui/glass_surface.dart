import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import 'glass_cover.dart';

/// 全应用**唯一**一处 `BackdropFilter`。
///
/// 三条来自实测的规矩都锁在这里，而不是散在每个面板上：
///
/// * **底色不透明时不加模糊。** `BackdropFilter` 是把子节点画在被模糊的背景之上
///   的，子节点不透明就等于把模糊结果整块盖掉 —— 浅色主题的中央表格渐变正是
///   这种情况。跳过它省下的是一整块、按设备分辨率逐帧重跑的多通道 GPU 滤镜。
///   所以 `blur: true` 不是拿到模糊的保证；把底色调成不透明也就是决定放弃那层
///   毛玻璃。
/// * **性能模式整块跳过滤镜，而不是传 0。** 零 sigma 的滤镜照样会结束一个渲染
///   通道并回读整个目标，代价正在那里。
/// * **模糊只在有裁剪的地方开。** 没有 `ClipRRect` 的 `BackdropFilter` 会采样到
///   圆角之外。
/// * **被不透明路由盖住时不加模糊。** 看不见的那层照样每帧回读整块背景；推开
///   设置页的 300ms 里，主页那 6 个滤镜一个都没人看得到。见 [GlassCoverScope]。
///
/// 在 3840×2160（devicePixelRatio 2.0）上实测：最大化切分区，p50 光栅
/// 61.5 ms → 23.9 ms、12.5 → 24.8 fps。代价是面积 × dpr²，而且超线性 —— 同一层
/// 模糊在小窗口里几乎免费，最大化时是灾难，所以任何前后对比都必须在投诉发生的
/// 那个尺寸上测。
class GlassSurface extends StatelessWidget {
  /// 玻璃底色。不透明时模糊被自动丢弃。
  final Color fill;

  /// 模糊半径。0 或 [AppTokens.reduceEffects] 时不建 `BackdropFilter`。
  final double blur;

  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final List<BoxShadow> shadow;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  /// 额外叠一层极淡的暖色，近似 CSS 的 `saturate(180%)`。
  /// Flutter 的 `ImageFilter.blur` 没有饱和度参数，硬做要自定义
  /// `ColorFilter` + shader；这一层是够用的近似，且完全免费。
  final bool saturate;

  const GlassSurface({
    super.key,
    required this.fill,
    required this.blur,
    this.borderRadius,
    this.border,
    this.shadow = const [],
    this.padding,
    this.saturate = false,
    this.child,
  });

  /// 底色是否已经把背景完全挡住 —— 那样模糊就是白做的。
  static bool _fillHidesBackdrop(Color fill) => fill.a >= 0.995;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = borderRadius ?? BorderRadius.zero;
    final wantsBlur =
        blur > 0 &&
        !t.reduceEffects &&
        !_fillHidesBackdrop(fill) &&
        !GlassCoverScope.isCovered(context);

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius == BorderRadius.zero ? null : radius,
        border: border,
      ),
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child ?? const SizedBox()),
    );

    if (saturate && wantsBlur) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.accent.withValues(
                    alpha: AppBlur.saturateOverlayAlpha,
                  ),
                  borderRadius: radius == BorderRadius.zero ? null : radius,
                ),
              ),
            ),
          ),
          content,
        ],
      );
    }

    if (wantsBlur) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      );
    } else if (radius != BorderRadius.zero) {
      content = ClipRRect(borderRadius: radius, child: content);
    }

    if (shadow.isEmpty) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius == BorderRadius.zero ? null : radius,
        boxShadow: shadow,
      ),
      child: content,
    );
  }
}

/// 页面级面板 / 卡片（1.4d）。内容卡圆角 12、内距 16。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? fill;
  final bool bordered;

  /// 悬停时投影升到 L2，**不放大**。
  final bool elevated;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadii.card,
    this.fill,
    this.bordered = true,
    this.elevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final surface = GlassSurface(
      fill: fill ?? t.cardFill,
      blur: 0,
      borderRadius: BorderRadius.circular(radius),
      border: bordered ? Border.all(color: t.stroke) : null,
      shadow: elevated ? t.elevation.card : t.elevation.row,
      padding: padding,
      child: child,
    );
    if (onTap == null) return surface;
    return _Hoverable(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap!,
      child: surface,
    );
  }
}

/// 侧栏 / 右面板这类满高玻璃列（1.1「侧栏 / 面板」）。
class AppGlassPane extends StatelessWidget {
  final Widget child;
  final Border? border;
  final EdgeInsetsGeometry? padding;

  const AppGlassPane({
    super.key,
    required this.child,
    this.border,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlassSurface(
      fill: t.panelFill,
      blur: t.blurPanel,
      border: border,
      padding: padding,
      child: child,
    );
  }
}

class _Hoverable extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  const _Hoverable({
    required this.child,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.respecting(context, AppMotion.hover),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: _hover ? context.tokens.elevation.card : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
