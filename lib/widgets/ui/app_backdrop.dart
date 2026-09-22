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
/// * **降分辨率烘，但倍数按设备像素算。** 渐变是平滑的，双线性放大不会丢东西 ——
///   会被放大的是渐变光栅化时加进去的**抖动噪声**，所以倍数不能随便给，见
///   [_AppBackdropState._sharpDownscale]。清晰层 2 设备像素/纹素、模糊层 4：
///   3024x1760 上 8.3MB（清晰 1536x896 + 两张模糊 768x448），4K 最大化 12.5MB。
///   比从前那版 1/4 逻辑像素（同一块屏上三张共 1.0MB）贵。作参照：同一块 4K
///   上 1:1 烘**一张**就要 31.7MB，而实画那条路一张纹理都不占 —— 它花的是每帧
///   ~33ms，那个 33 和这里的 MB 数没有关系。
/// * **必须按窗口尺寸烘，不能按屏幕尺寸烘一张通用的。**
///   [RadialGradient.radius] 是相对**短边**的，所以换一个宽高比，同一份配方画
///   出来的就不是同一个形状 —— 拿屏幕比例的图去拉伸填充窄窗口会把圆压成椭圆。
///   代价用「逻辑尺寸量化到 64px + 去抖」抵消，见 [_AppBackdropState._snapLogical]。
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
/// * **模糊层在它自己那张小图上模糊，sigma 也要跟着换算**
///   （`_BakeRequest.blurScale`）。模糊本身就是低通，降采样带来的误差比清晰版
///   还小 —— 也正因为如此，它可以比清晰层烘得更稀。
/// * **`TileMode.clamp`。** 边缘要延展而不是渐隐到透明，否则窗口四边会出现一圈
///   暗边 —— 真 `BackdropFilter` 在屏幕边界上也是 clamp。
/// * **这是一条结构约束，不是一个纯优化。** 它成立的前提是「面板背后只有这张
///   图」。哪天谁在某块面板背后放了动态内容，模糊里就不会有它。嵌套的玻璃面由
///   [BakedBackdropScope] 自动挡掉（见 [GlassSurface]），但同层的新东西挡不住 ——
///   `test/widgets/ui/baked_glass_test.dart` 钉的就是这条。
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

  /// 每请求一次烘焙 +1。失败时用它判断「这次飞行还是不是最新的那次」，见
  /// [_bake] 的 catch。
  int _generation = 0;

  /// 标记「这张图铺到哪块矩形上」，供 [GlassSurface] 把自己的位置换算成图上的
  /// 采样区。用 [GlobalKey] 而不是假设背景就在窗口原点：整页路由各有各的一层。
  final _area = GlobalKey();

  /// 拖强调色取色器是**实时预览**的，会一路调用 `setAccentColor`；不去抖的话
  /// 拖过一条色相就是每帧一次 `toImage`。底色是很淡的一层，滞后 120ms 看不出来。
  static const _debounceDelay = Duration(milliseconds: 120);

  /// 清晰层的烘焙分辨率：一个纹素铺 2 个**设备**像素。
  ///
  /// 「设备」这个词是这里唯一要紧的事。渐变光栅化时是**带抖动**的 —— 为了不让
  /// 8bit 量化在这么淡的一层上留下色阶，Skia / Impeller 都会加一层 ±1 的逐像素
  /// 噪声。在 1:1 的清晰图上那是 1 像素的噪声，看不见；可它会被放大倍数照样放
  /// 大。这条从前按**逻辑**像素除 4，Retina（dpr 2）上就是除 8，于是 1 像素的
  /// 抖动被双线性拉成 8 设备像素一块的色斑，整片背景看起来像一块抹布。
  ///
  /// 实测（MacBook Pro 3024x1760，把原图按人眼能分辨的尺度降采样后量化残差）：
  ///
  /// | 放大倍数（设备像素/纹素） | 残差 RMS | 相邻像素相关性 |
  /// |---|---|---|
  /// | 1（逐帧实画，理想） | 0.16/255 | −0.06（1px 抖动，看不见） |
  /// | **8（从前：逻辑像素 / 4）** | **0.31/255** | **+0.71（约 8px 一块）** |
  /// | 4（设备像素 / 4） | 0.28/255 | +0.29 |
  /// | **2（现在）** | **0.22/255** | **−0.12（与实画同一档）** |
  ///
  /// 「先把抖动糊掉再放大」试过，不行：模糊会把逐像素噪声换成**等高线色带**，
  /// 比色斑更明显。唯一的解法就是别把抖动放大到看得见。
  static const _sharpDownscale = 2;

  /// 模糊层的烘焙分辨率：一个纹素铺 4 个设备像素。
  ///
  /// 模糊之后图上本来就没有比 sigma 更细的结构，抖动也早被模糊本身抹平了，
  /// 所以这一层不需要跟清晰层一样密 —— 它占三分之二的张数，按清晰层烘是白花
  /// 四倍显存。
  static const _blurDownscale = 4;

  /// 模糊层比清晰层稀几倍。[_blurSizeFor] 直接按它折半，所以两层的比例是**由
  /// 构造保证**的，不是两条算式碰巧算出同一个数 —— 纹理上限把清晰层缩回去的
  /// 时候也一样成立。
  static const _layerRatio = _blurDownscale ~/ _sharpDownscale;

  /// 量化步长（**逻辑**像素）：窗口尺寸变化不足一格就复用上一张，拉伸几十个
  /// 像素在一层柔和的渐变上是看不见的。这是「别在拖动窗口边框时每帧重烘」的
  /// 实现方式。
  ///
  /// 记在逻辑像素上，而不是烘焙纹素上：它要买的是「窗口得变多大才值得重烘」，
  /// 那个量跟屏幕缩放、跟降采样倍数都无关。按纹素记的话，同一个 `Q` 换算回窗口
  /// 尺寸是 `Q * downscale / dpr`，每一层、每一种缩放都是另一个意思。拿从前那版
  /// 的 `Q = 16`（它正是按纹素记的）算：
  ///
  /// * 旧方案只有一层、固定 64 逻辑像素。改成按设备像素分档之后，dpr 2 的清晰层
  ///   只剩 16 逻辑像素，**重烘频率是旧方案的四倍**；
  /// * 同一块屏上，清晰层又会是模糊层的 [_layerRatio] 倍 —— 这个比值跟 `Q`、跟
  ///   dpr 都无关，而两层本该同时重烘。
  ///
  /// 先对齐逻辑尺寸、再换算成纹素，这两件事就都没有了：[_snapLogical] 的结果
  /// 两层共用。挑 64 是因为它在 dpr 2 的清晰层上正好折成 64 个**纹素**，
  /// 跟旧方案那 64 逻辑像素是同一个手感。（逻辑格换算回窗口尺寸当然永远是
  /// 它自己 —— 会随 dpr 变的是它值多少纹素。）
  static const _quantum = 64;

  /// 单边纹理上限。超过就**两边一起缩**：只截一边会改掉图的宽高比，而径向渐变
  /// 的半径是按短边算的，圆会被拉成椭圆 —— 就是类文档第二条说的那件事。
  ///
  /// 缩放只在 [_sharpSizeFor] 里做一次，模糊层跟着 [_blurSizeFor] 折半，所以
  /// 上限生效时两层的比例照旧。清晰层是 2 设备像素/纹素，所以窗口宽到 8200
  /// 设备像素上下才够得着（跨双 5K 拼接；确切阈值随 dpr 和量化格略有出入，
  /// dpr 3 上是 8067），但够得着就得是对的。
  static const _maxBakeSide = 4096.0;

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

  /// 把逻辑尺寸对齐到量化格。**两层烘焙共用这一个结果**，见 [_quantum]。
  Size _snapLogical(Size size) => Size(
    (size.width / _quantum).ceil() * _quantum.toDouble(),
    (size.height / _quantum).ceil() * _quantum.toDouble(),
  );

  /// 清晰层的烘焙尺寸。[snapped] 是已经对齐过的逻辑尺寸。
  ///
  /// 纹理上限**只在这里**收一次：清晰层是最密的一层，它先触顶，模糊层跟着
  /// [_blurSizeFor] 折半，两层的比例就不会因为上限而走样。边长取到
  /// [_layerRatio] 的整数倍，折半才不会掉小数。
  Size _sharpSizeFor(Size snapped, double dpr) {
    var w = snapped.width * dpr / _sharpDownscale;
    var h = snapped.height * dpr / _sharpDownscale;
    final side = w > h ? w : h;
    if (side > _maxBakeSide) {
      final k = _maxBakeSide / side;
      w *= k;
      h *= k;
    }
    return Size(_alignLayers(w), _alignLayers(h));
  }

  /// 模糊层的烘焙尺寸：清晰层折半，见 [_layerRatio]。
  Size _blurSizeFor(Size sharp) =>
      Size(sharp.width / _layerRatio, sharp.height / _layerRatio);

  static double _alignLayers(double texels) {
    final t = texels.ceil();
    final aligned = (t + _layerRatio - 1) ~/ _layerRatio * _layerRatio;
    return (aligned < _layerRatio ? _layerRatio : aligned).toDouble();
  }

  void _requestBake(_BakeRequest request) {
    if (_pending == request) return;
    _pending = request;
    final generation = ++_generation;
    _debounce?.cancel();
    _debounce = Timer(
      _debounceDelay,
      () => unawaited(_bake(request, generation)),
    );
  }

  /// 把两层径向渐变画进一张 [size] 像素的图。
  Future<ui.Image> _gradientImage(RadialPairGradient g, Size size) async {
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
    try {
      return await picture.toImage(size.width.round(), size.height.round());
    } finally {
      picture.dispose();
    }
  }

  Future<void> _bake(_BakeRequest request, int generation) async {
    // 清晰层这次分配也要在 try 里面 —— 它是三张里最大的一张，最可能失败的就是
    // 它，而且 `sigmas` 为空（玻璃强度 0 或关掉预烘）时 try 体本来就只剩它。
    ui.Image? image;
    final blurred = <double, ui.Image>{};
    try {
      image = await _gradientImage(request.gradient, request.sharpSize);
      if (request.sigmas.isNotEmpty) {
        // 模糊层从一张**单独烘的小图**出发，而不是从清晰层降采样或原地模糊：
        // 它只需要 [_blurDownscale] 那一档密度，见那条常量。
        final source = await _gradientImage(request.gradient, request.blurSize);
        try {
          for (final sigma in request.sigmas) {
            blurred[sigma] = await _blurOf(source, sigma * request.blurScale);
          }
        } finally {
          source.dispose();
        }
      }
    } catch (_) {
      // 一次失败就整批作废：拿一半的档位去配对会让某些面板悄悄换成另一种观感。
      for (final partial in blurred.values) {
        partial.dispose();
      }
      image?.dispose();
      // 把这一档从 `_pending` 上放开，否则它就永远卡在这儿了：`_bakedFrom` 没
      // 动，每次 build 都还会请求同一份，而 `_requestBake` 看见 `_pending`
      // 相等就直接 return —— 于是一次失败（比如显存不够）之后，这一档就再也
      // 烘不出来了，直到窗口尺寸或主题变了才有机会重来。（画面上是什么样取决于
      // 之前烘成过没有：第一次就失败是停在纯底色上，之前成功过则是把上一张继续
      // 拉伸到新尺寸用。）
      //
      // 按 [_generation] 而不是按 request 判断：同一份请求可能有两次烘焙在飞
      // （拖窗口跨出一格又跨回来），失败的那次不该把另一次**可能成功**的结果
      // 一起作废掉。
      //
      // 注意这只是解开闩，它**不安排重建** —— 真正的重来要等下一次 build。
      // 窗口彻底静止时那就是「一直停在纯底色上」，这是有意的：在这里
      // `setState` 会把一次确定性失败变成每 120ms 一轮的重试风暴。
      if (_generation == generation) _pending = null;
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

  /// 把烘好的背景再模糊一遍。[sigma] 已经换算到模糊层的像素空间。
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

    // 烘焙分辨率按设备像素算，不按逻辑像素 —— 见 [_sharpDownscale]。
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && !size.isEmpty) {
          final snapped = _snapLogical(size);
          final sharpSize = _sharpSizeFor(snapped, dpr);
          final blurSize = _blurSizeFor(sharpSize);
          final request = _BakeRequest(
            sharpSize,
            blurSize,
            blurSize.width / snapped.width,
            g,
            sigmas,
          );
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
                // filterQuality 必须给到 low 以上：默认 none 是最近邻，降分辨率
                // 烘的图放大会直接暴露成色块。
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
  const _BakeRequest(
    this.sharpSize,
    this.blurSize,
    this.blurScale,
    this.gradient,
    this.sigmas,
  );

  /// 清晰层的烘焙尺寸（像素）。
  final Size sharpSize;

  /// 模糊层的烘焙尺寸（像素）。
  final Size blurSize;

  /// 逻辑像素 → [blurSize] 像素的比例，用来把 sigma 换算过去。
  ///
  /// 从**对齐后**的逻辑尺寸相除得来，不是写死的 `dpr / _blurDownscale`：一来
  /// 它得跟着 [_AppBackdropState._maxBakeSide] 的缩放走 —— 触到上限的是清晰层
  /// （模糊层只有它的一半，够不着），而模糊层是从收完的清晰层折半来的，跟着
  /// 一起小了；sigma 要是写死成 `dpr / _blurDownscale`，就配不上那张图的实际
  /// 比例，模糊会过头。二来对齐后的尺寸一格之内不变，所以拖窗口不会每个像素
  /// 换一个 sigma。
  ///
  /// 剩下的误差是对齐格：sigma 按对齐后的尺寸折算，而 `_RenderBakedBlur` 是按
  /// **真实**窗口尺寸、**分轴**取采样区的，所以模糊比 sigma 的名义值略弱，两轴
  /// 还弱得不一样多。误差就是「窗口离上一条格线有多远」，平均半格：正好压在
  /// 格上是 0%（最小宽度 1024 就是），刚过一格最坏 —— 宽 5.8%（1025 → 1088）、
  /// 高 8.2%（705 → 768，最小高度是 700）。高度那一轴平均更差，因为它数值更
  /// 小而格子一样宽：900 → 960 是 6.3%，1032 → 1088 是 5.1%，而常见宽度
  /// （1500～1900）在 2% 上下。一层毛玻璃上看不出这点差别；改成按真实尺寸
  /// 折算倒是真会出事，那样拖窗口每个像素换一个 sigma，量化格就白设了。
  final double blurScale;

  final RadialPairGradient gradient;
  final Set<double> sigmas;

  @override
  bool operator ==(Object other) =>
      other is _BakeRequest &&
      other.sharpSize == sharpSize &&
      other.blurSize == blurSize &&
      other.blurScale == blurScale &&
      setEquals(other.sigmas, sigmas) &&
      other.gradient.base == gradient.base &&
      other.gradient.first == gradient.first &&
      other.gradient.firstCenter == gradient.firstCenter &&
      other.gradient.second == gradient.second &&
      other.gradient.secondCenter == gradient.secondCenter;

  @override
  int get hashCode => Object.hash(
    sharpSize,
    blurSize,
    blurScale,
    Object.hashAllUnordered(sigmas),
    gradient.base,
    gradient.first,
    gradient.firstCenter,
    gradient.second,
    gradient.secondCenter,
  );
}
