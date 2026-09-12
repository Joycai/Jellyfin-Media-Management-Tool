import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// 窗口底：纯色 + 两层径向渐变，**离线烘成一张图**再贴上去。
///
/// 这一层看起来最无辜，实测却是整个 app 第二贵的东西。在 3840x2064
/// (devicePixelRatio 2.0) 的 AMD 核显上，逐帧实时演算这两层渐变要 **~33ms**，
/// 而那时整个 UI 的其余部分（侧栏、文件表、AI 面板、状态栏、全部文字）加起来
/// 只有 1.7ms。
///
/// 贵的不是「半透明」，也不是「渐变」，是**第二层全窗口渐变要在已经画好的内容
/// 上混合**。单独测（2784x1891）：
///
/// | 画什么 | 光栅 p50 |
/// |---|---|
/// | 空白页 | 0.21 ms |
/// | 两层全窗口半透明**纯色** | 0.33 ms |
/// | **一层**全窗口径向渐变 | 0.65 ms |
/// | **两层** | **21.9 ms** |
/// | 三层 | 32.4 ms |
/// | 两层，但第二层缩到 200x200 | 0.93 ms |
/// | 两层，烘成一张图 | **0.52 ms** |
///
/// 代价按第二次绘制覆盖的面积走，而且 **Skia 下完全一样**（0.64 / 20.6 /
/// 27.9），所以这是这条 GPU/驱动路径的性质，不是 Impeller 的 bug。
///
/// 烘焙之所以有效，是它把三次全窗口混合塌缩成一次贴图。三个必须知道的取舍：
///
/// * **按 1/4 分辨率烘。** 渐变是平滑的，双线性放大反而把台阶插值掉了；显存
///   从 33MB 降到 2MB，重烘也快 16 倍。
/// * **必须按窗口尺寸烘，不能按屏幕尺寸烘一张通用的。**
///   [RadialGradient.radius] 是相对**短边**的，所以换一个宽高比，同一份配方画
///   出来的就不是同一个形状 —— 拿屏幕比例的图去拉伸填充窄窗口会把圆压成椭圆。
///   代价用「尺寸量化到 64px + 去抖」抵消，见 [_bakeSizeFor]。
/// * **`RepaintBoundary` 救不了这个。** 光栅缓存有尺寸上限，全窗口的表面远超
///   它 —— 实测包一层 21.9ms → 22.7ms，等于没有。所以只能自己烘。
///
/// 渐变本身是静态的（只随主题亮度与强调色变），逐帧重算它没有任何意义。
///
/// ## 顺带把毛玻璃也烘了（[AppTokens.bakedGlass]）
///
/// 背景静态还带来第二件事。外壳那几块玻璃 —— 顶栏 / 侧栏 / 中栏 / 右面板 /
/// 状态栏 —— 是同一平面上互不重叠的瓦片，而它们**背后只有这张烘好的图**：面板
/// 里的内容画在模糊之上，不在背后。既然输入是静态的，输出也是静态的。
///
/// 所以除了清晰版，这里再按主题用到的每档 sigma 各烘一张**模糊版**，
/// [GlassSurface] 从中裁出自己那一块贴上去，`BackdropFilter` 就不必存在了：
/// 四次全屏渲染目标回读换成四个贴图四边形，实测最大化 4K 下省 ~46ms。
///
/// 三件让它成立的事：
///
/// * **在 1/4 图上模糊，sigma 也要除以 [_downscale]。** 模糊本身就是低通，降
///   采样带来的误差比清晰版还小。
/// * **`TileMode.clamp`。** 边缘要延展而不是渐隐到透明，否则窗口四边会出现一圈
///   暗边 —— 真 `BackdropFilter` 在屏幕边界上也是 clamp。
/// * **这是一条结构约束，不是一个纯优化。** 它成立的前提是「面板背后只有这张
///   图」。哪天谁在某块面板背后放了动态内容，模糊里就不会有它。嵌套的玻璃面由
///   [BakedBackdropScope] 自动挡掉（见 [GlassSurface]），但同层的新东西挡不住 ——
///   `test/widgets/baked_glass_test.dart` 钉的就是这条。
class AppBackdrop extends StatefulWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> {
  ui.Image? _image;
  Map<double, ui.Image> _blurred = const {};
  BakedBackdrop? _baked;
  _BakeRequest? _bakedFrom;
  _BakeRequest? _pending;
  Timer? _debounce;

  /// 标记「这张图铺到哪块矩形上」，供 [GlassSurface] 把自己的位置换算成图上的
  /// 采样区。用 [GlobalKey] 而不是假设背景就在窗口原点：整页路由各有各的一层。
  final _area = GlobalKey();

  /// 拖强调色取色器是**实时预览**的，会一路调用 `setAccentColor`；不去抖的话
  /// 拖过一条色相就是每帧一次 `toImage`。底色是很淡的一层，滞后 120ms 看不出来。
  static const _debounceDelay = Duration(milliseconds: 120);

  /// 烘焙分辨率相对窗口的缩小倍数。
  static const _downscale = 4;

  /// 量化步长（烘焙图的像素）：窗口尺寸变化不足一格就复用上一张，拉伸几十个
  /// 像素在一层柔和的渐变上是看不见的。这是「别在拖动窗口边框时每帧重烘」的
  /// 实现方式。
  static const _quantum = 16;

  @override
  void dispose() {
    _debounce?.cancel();
    _disposeImages();
    super.dispose();
  }

  void _disposeImages() {
    _image?.dispose();
    for (final image in _blurred.values) {
      image.dispose();
    }
  }

  Size _bakeSizeFor(Size size) {
    int q(double v) {
      final raw = (v / _downscale).ceil();
      return ((raw + _quantum - 1) ~/ _quantum * _quantum).clamp(1, 4096);
    }

    return Size(q(size.width).toDouble(), q(size.height).toDouble());
  }

  void _requestBake(_BakeRequest request) {
    if (_pending == request) return;
    _pending = request;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => unawaited(_bake(request)));
  }

  Future<void> _bake(_BakeRequest request) async {
    final size = request.size;
    final g = request.gradient;
    final rect = Offset.zero & size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(rect, Paint()..color = g.base);
    void radial(Alignment center, double radius, Color color) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: center,
            radius: radius,
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    // 半径 1.15 / 1.05 来自设计稿 2.4，和这个 widget 从前逐帧画的完全一致。
    radial(g.firstCenter, 1.15, g.first);
    radial(g.secondCenter, 1.05, g.second);

    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await picture.toImage(size.width.round(), size.height.round());
    } finally {
      picture.dispose();
    }

    final blurred = <double, ui.Image>{};
    try {
      for (final sigma in request.sigmas) {
        blurred[sigma] = await _blurOf(image, sigma / _downscale);
      }
    } catch (_) {
      // 一次失败就整批作废：拿一半的档位去配对会让某些面板悄悄换成另一种观感。
      for (final partial in blurred.values) {
        partial.dispose();
      }
      image.dispose();
      rethrow;
    }

    if (!mounted || _pending != request) {
      for (final unused in blurred.values) {
        unused.dispose();
      }
      image.dispose();
      return;
    }
    setState(() {
      _disposeImages();
      _image = image;
      _blurred = blurred;
      _bakedFrom = request;
      _baked = blurred.isEmpty
          ? null
          : BakedBackdrop._(images: blurred, area: _area);
    });
  }

  /// 把烘好的背景再模糊一遍。[sigma] 已经换算到烘焙图的像素空间。
  Future<ui.Image> _blurOf(ui.Image source, double sigma) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(
      source,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.low
        // clamp 而不是默认的渐隐：源图就是整个窗口，边缘之外没有「空」可采样，
        // 渐隐会在四边留一圈暗边。
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(source.width, source.height);
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final g = t.backdrop;
    // 主题动画中途 `Gradient.lerp` 可能给回别的类型；那条路照旧逐帧画，它只在
    // 切主题的那几帧里存在。
    if (g is! RadialPairGradient) {
      return BakedBackdropScope(
        backdrop: null,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: g),
          child: widget.child,
        ),
      );
    }

    // 只烘外壳真正会用到的那两档。对话框 / 菜单是 push 上来的 route，够不到这棵
    // 子树，给它们烘一张是白占显存。
    final sigmas = t.bakedGlass
        ? <double>{
            if (t.blurTopBar > 0) t.blurTopBar,
            if (t.blurPanel > 0) t.blurPanel,
          }
        : const <double>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && !size.isEmpty) {
          final request = _BakeRequest(_bakeSizeFor(size), g, sigmas);
          if (_bakedFrom != request) {
            // build 里不能 setState，也不该起异步工作。
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _requestBake(request),
            );
          }
        }
        final image = _image;
        return BakedBackdropScope(
          backdrop: _baked,
          child: Stack(
            key: _area,
            fit: StackFit.expand,
            children: [
              // 第一帧（以及每次重烘落地之前）退回纯底色，而不是空白：它是渐变的
              // 基色，换上去的那一下看不出来。
              if (image == null)
                ColoredBox(color: g.base)
              else
                // filterQuality 必须给到 low 以上：默认 none 是最近邻，1/4 图放大
                // 会直接暴露成色块。
                RawImage(
                  image: image,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.low,
                ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

/// 一份已经烘好的模糊背景，连同它铺在哪儿。
///
/// 身份即版本：每次重烘产生一个新实例，[BakedBackdropScope.updateShouldNotify]
/// 就是靠这个把用它的面板叫起来重画的。
@immutable
class BakedBackdrop {
  const BakedBackdrop._({
    required Map<double, ui.Image> images,
    required this.area,
  }) : _images = images;

  final Map<double, ui.Image> _images;

  /// 指向铺满整个背景的那块 widget，用来把面板坐标换算到图上的采样区。
  final GlobalKey area;

  /// 对应 [sigma] 的那张预模糊图，没有烘过这一档就返回 null —— 调用方退回
  /// 真 `BackdropFilter`，而不是拿一档不对的糊上去。
  ui.Image? imageFor(double sigma) => _images[sigma];

  /// 这个背景当前铺满的逻辑矩形尺寸，尚未布局时为 null。
  Size? get areaSize {
    final box = area.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.size;
  }
}

/// 把 [BakedBackdrop] 递给下面的玻璃面。
///
/// `backdrop` 为 null 有两种意思，对使用者是同一件事：还没烘好，或者这块地方
/// **不该**用烘好的图（[GlassSurface] 会给自己的子树挡一层 null，因为嵌套的玻璃
/// 面背后就不只有背景了）。两种情况都退回真 `BackdropFilter`。
class BakedBackdropScope extends InheritedWidget {
  const BakedBackdropScope({
    super.key,
    required this.backdrop,
    required super.child,
  });

  final BakedBackdrop? backdrop;

  static BakedBackdrop? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BakedBackdropScope>()
      ?.backdrop;

  @override
  bool updateShouldNotify(BakedBackdropScope oldWidget) =>
      !identical(oldWidget.backdrop, backdrop);
}

/// 一次烘焙的完整输入。相等 = 可以复用已经烘好的那批图。
@immutable
class _BakeRequest {
  const _BakeRequest(this.size, this.gradient, this.sigmas);

  final Size size;
  final RadialPairGradient gradient;
  final Set<double> sigmas;

  @override
  bool operator ==(Object other) =>
      other is _BakeRequest &&
      other.size == size &&
      setEquals(other.sigmas, sigmas) &&
      other.gradient.base == gradient.base &&
      other.gradient.first == gradient.first &&
      other.gradient.firstCenter == gradient.firstCenter &&
      other.gradient.second == gradient.second &&
      other.gradient.secondCenter == gradient.secondCenter;

  @override
  int get hashCode => Object.hash(
    size,
    Object.hashAllUnordered(sigmas),
    gradient.base,
    gradient.first,
    gradient.firstCenter,
    gradient.second,
    gradient.secondCenter,
  );
}
