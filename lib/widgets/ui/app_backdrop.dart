import 'dart:async';
import 'dart:ui' as ui;

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
class AppBackdrop extends StatefulWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> {
  ui.Image? _image;
  _BakeRequest? _baked;
  _BakeRequest? _pending;
  Timer? _debounce;

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
    _image?.dispose();
    super.dispose();
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
    if (!mounted || _pending != request) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _baked = request;
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = AppTokens.of(context).backdrop;
    // 主题动画中途 `Gradient.lerp` 可能给回别的类型；那条路照旧逐帧画，它只在
    // 切主题的那几帧里存在。
    if (g is! RadialPairGradient) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: g),
        child: widget.child,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && !size.isEmpty) {
          final request = _BakeRequest(_bakeSizeFor(size), g);
          if (_baked != request) {
            // build 里不能 setState，也不该起异步工作。
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _requestBake(request),
            );
          }
        }
        final image = _image;
        return Stack(
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
        );
      },
    );
  }
}

/// 一次烘焙的完整输入。相等 = 可以复用已经烘好的那张图。
@immutable
class _BakeRequest {
  const _BakeRequest(this.size, this.gradient);

  final Size size;
  final RadialPairGradient gradient;

  @override
  bool operator ==(Object other) =>
      other is _BakeRequest &&
      other.size == size &&
      other.gradient.base == gradient.base &&
      other.gradient.first == gradient.first &&
      other.gradient.firstCenter == gradient.firstCenter &&
      other.gradient.second == gradient.second &&
      other.gradient.secondCenter == gradient.secondCenter;

  @override
  int get hashCode => Object.hash(
    size,
    gradient.base,
    gradient.first,
    gradient.firstCenter,
    gradient.second,
    gradient.secondCenter,
  );
}
