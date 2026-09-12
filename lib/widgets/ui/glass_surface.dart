import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import 'app_backdrop.dart';
import 'glass_cover.dart';

/// 全应用**唯一**一处 `BackdropFilter`。
///
/// 五条来自实测的规矩都锁在这里，而不是散在每个面板上：
///
/// * **底色不透明时不加模糊。** `BackdropFilter` 是把子节点画在被模糊的背景之上
///   的，子节点不透明就等于把模糊结果整块盖掉 —— 浅色主题的中央表格渐变正是
///   这种情况。跳过它省下的是一整块、按设备分辨率逐帧重跑的多通道 GPU 滤镜。
///   所以 `blur: true` 不是拿到模糊的保证；把底色调成不透明也就是决定放弃那层
///   毛玻璃。
/// * **玻璃强度 0 整块跳过滤镜，而不是传 sigma 0。** 零 sigma 的滤镜照样会结束
///   一个渲染通道并回读整个目标，代价正在那里。
/// * **代价按滤镜个数算，不按半径算。** Impeller 先降采样再模糊，所以半径几乎
///   不影响耗时：最大化 4K 下强度 50 是 82.0ms、强度 100 是 83.8ms（+2%），而
///   把滤镜拿掉省 46ms。滑块是**观感**控制，只有 0 那一档是性能控制。
/// * **同一平面上的多个滤镜共用一次背景快照。** 见 build 里的 [BackdropGroup]。
/// * **背景是静态的时候，模糊结果也是静态的 —— 直接贴预烘的那张。** 见
///   [BakedBackdropScope]；这条把上一条剩下的 46ms 也拿掉了。
/// * **模糊只在有裁剪的地方开。** 没有 `ClipRRect` 的 `BackdropFilter` 会采样到
///   圆角之外。
/// * **被不透明路由盖住时不加模糊。** 看不见的那层照样每帧回读整块背景；推开
///   设置页的 300ms 里，主页那 6 个滤镜一个都没人看得到。见 [GlassCoverScope]。
///
/// 在 3840×2064（devicePixelRatio 2.0）的 AMD 核显上实测，Files 分区最大化、
/// 背景已烘焙：四个滤镜 **~46ms**，占整帧 57%；把它们拿掉，整个 UI 剩 1.7ms。
/// 代价是面积 × dpr²，而且超线性 —— 同一层模糊在小窗口里几乎免费，最大化时是
/// 灾难，所以任何前后对比都必须在投诉发生的那个尺寸上测。
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

    // 背景已经连模糊一起烘好了：裁一块贴上，不必再开滤镜。找不到（还没烘好、
    // 开关关着、或者上层特意挡掉了）就走下面的真滤镜。
    final baked = wantsBlur ? BakedBackdropScope.of(context) : null;
    final bakedImage = baked?.imageFor(blur);
    if (bakedImage != null) {
      return _wrapShadow(
        ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: _BakedBlur(image: bakedImage, backdrop: baked!),
              ),
              // 挡掉作用域：嵌套在这块玻璃里的玻璃，背后就不只有背景了 ——
              // 还有这一层的底色和内容。它必须退回真滤镜才能看到那些。
              BakedBackdropScope(backdrop: null, child: content),
            ],
          ),
        ),
        radius,
      );
    }

    if (wantsBlur) {
      final filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
      // 有 BackdropGroup 就并进去，共用一次背景快照；没有就照旧自己快照一次。
      // 判断依据是「祖先里有没有组」而不是一个参数，因为这恰好把该分组的和
      // 不该分组的分开了：外壳那几块在 AppShell 的组里，而对话框 / 菜单 /
      // 浮层都是 push 上来的 route，不在这棵子树内 —— 它们盖在面板之上、要
      // 模糊到面板本身，同组会让重叠处看起来只应用了一层模糊。
      final grouped = BackdropGroup.of(context) != null;
      content = ClipRRect(
        borderRadius: radius,
        child: grouped
            ? BackdropFilter.grouped(filter: filter, child: content)
            : BackdropFilter(filter: filter, child: content),
      );
    } else if (radius != BorderRadius.zero) {
      content = ClipRRect(borderRadius: radius, child: content);
    }

    return _wrapShadow(content, radius);
  }

  Widget _wrapShadow(Widget content, BorderRadius radius) {
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

/// 把预烘的模糊背景中属于这块面板的那一片画出来。
///
/// 之所以要一个 render object 而不是 `Image` + `Alignment`：要画的是**这块面板
/// 在整张背景图上对应的区域**，而面板并不知道自己在窗口里的位置。只有在 paint
/// 时用 `localToGlobal` 换算才拿得到，而且窗口一改尺寸它就变了。
class _BakedBlur extends LeafRenderObjectWidget {
  const _BakedBlur({required this.image, required this.backdrop});

  final ui.Image image;
  final BakedBackdrop backdrop;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBakedBlur(image, backdrop);

  @override
  void updateRenderObject(BuildContext context, _RenderBakedBlur renderObject) {
    renderObject
      ..image = image
      ..backdrop = backdrop;
  }
}

class _RenderBakedBlur extends RenderBox {
  _RenderBakedBlur(this._image, this._backdrop);

  ui.Image _image;
  set image(ui.Image value) {
    if (identical(value, _image)) return;
    _image = value;
    markNeedsPaint();
  }

  BakedBackdrop _backdrop;
  set backdrop(BakedBackdrop value) {
    if (identical(value, _backdrop)) return;
    _backdrop = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final area = _backdrop.areaSize;
    final box = _backdrop.area.currentContext?.findRenderObject();
    if (area == null || area.isEmpty || box is! RenderBox) return;
    if (size.isEmpty) return;

    // 面板左上角在背景那块矩形里的位置。绕一趟全局坐标是因为两者中间隔着
    // Padding、Row、动画容器，没有直达的变换。
    final origin = box.globalToLocal(localToGlobal(Offset.zero));
    final scaleX = _image.width / area.width;
    final scaleY = _image.height / area.height;
    final source = Rect.fromLTWH(
      origin.dx * scaleX,
      origin.dy * scaleY,
      size.width * scaleX,
      size.height * scaleY,
    );
    context.canvas.drawImageRect(
      _image,
      source,
      offset & size,
      Paint()..filterQuality = FilterQuality.low,
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
