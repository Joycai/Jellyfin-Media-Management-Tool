import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Every value the redesigned UI is allowed to paint with.
///
/// Transcribed from the Claude Design project `Jellyfin媒体库整理工具`
/// (`docs/spec/ui-redesign/01-foundations.md`). The rule the whole redesign
/// rests on: **a widget never writes a raw colour, radius, height or duration
/// of its own** — it reads one of these. That is what makes swapping the accent
/// or turning on performance mode a one-line change instead of a sweep.
///
/// Split three ways on purpose:
///
/// * [AppSpacing] / [AppRadii] / [AppSizes] / [AppMotion] / [AppTypeScale] are
///   `static const`: they do not vary with brightness, accent or performance
///   mode, so putting them on the [ThemeExtension] would only make every read
///   pay for a `Theme.of` lookup that can never return a different answer.
/// * [AppTokens] is the extension: colours, gradients, shadows and blur, all of
///   which *do* vary.
/// * [AppTokensX] is the accessor — `context.tokens`.

// ---------------------------------------------------------------------------
// 1.3 间距 · 圆角 · 尺寸 — 与亮度无关，全部 static const
// ---------------------------------------------------------------------------

/// 1.3a 间距。基准步进 2px。
abstract final class AppSpacing {
  /// 图标与文字、徽标与标签。
  static const double xxs = 4;

  /// 同组按钮之间。
  static const double xs = 6;

  /// 图标与标签、行内元素。
  static const double sm = 8;

  /// 控件左右内距、列表行内距。
  static const double md = 10;
  static const double md12 = 12;

  /// 卡片内元素间距、侧栏内距。
  static const double lg = 16;

  /// 卡片与对话框内距、主内容区左右。
  static const double xl = 22;
  static const double xl24 = 24;

  /// 区块之间、空状态四周。
  static const double xxl = 32;
  static const double xxl40 = 40;
}

/// 1.3b 圆角。嵌套时内层 = 外层 − 内距，最小 6。
abstract final class AppRadii {
  /// 快捷键胶囊、小标签。
  static const double chip = 5;

  /// 段控内段、小色块。
  static const double tiny = 6;

  /// 按钮、图标底、侧栏行、类型图标。
  static const double button = 8;
  static const double icon = 9;

  /// 输入框、搜索框、列表行。
  static const double field = 10;

  /// 弹层、内容卡、对话框。
  static const double card = 12;
  static const double panel = 14;

  /// 窗口（macOS 12 / Windows 10）。
  static const double windowMac = 12;
  static const double windowWin = 10;

  /// 最大化时窗口圆角归零，内部不变。
  static const double windowMaximized = 0;

  /// 内层圆角推导：外层 − 内距，最小 6。
  static double nested(double outer, double padding) =>
      (outer - padding).clamp(6.0, outer);
}

/// 1.3c 控件高度，以及 02 骨架的布局基准。
abstract final class AppSizes {
  // --- 控件高度 -----------------------------------------------------------
  /// 行内小按钮、标签。
  static const double controlXs = 24;

  /// 次级按钮、状态栏内控件。
  static const double controlSm = 28;

  /// 标准按钮、输入框、图标按钮、Tab。
  static const double control = 32;

  /// 文件列表行。
  static const double row = 34;

  /// 双行列表行（历史、任务）。
  static const double rowTall = 44;

  /// 统一顶栏。
  static const double topBar = 48;

  // --- 顶栏内部（2.2） -----------------------------------------------------
  static const double topBarLeftInset = 12;
  static const double logo = 26;
  static const double logoGap = 9;
  static const double dividerHeight = 20;
  static const double dividerMargin = 12;
  static const double tabGap = 4;
  static const double tabPaddingH = 12;
  static const double taskBadge = 16;
  static const double searchMin = 200;
  static const double searchMax = 460;
  static const double searchMargin = 16;
  static const double actionGap = 6;

  /// 窗口按钮：唯一无圆角的控件，命中区 46 × 48。
  static const double captionButtonWidth = 46;

  /// 三颗窗口按钮锁定的总宽，最大化时其下方与右侧不得出现任何应用内容。
  static const double captionBarWidth = captionButtonWidth * 3;

  /// macOS 交通灯左侧预留；全屏时回收到 [topBarLeftInset]。
  static const double macTrafficLightInset = 84;
  static const double macTrafficLight = 12;
  static const double macTrafficLightGap = 8;

  /// Windows 最大化时向外溢出的边框，需要补回内边距，否则主体被裁切。
  static const double windowsMaximizedInset = 8;

  // --- 2.6 布局骨架 --------------------------------------------------------
  static const double sidebar = 244;
  static const double sidebarMin = 200;
  static const double sidebarMax = 360;

  /// 折叠后的图标栏宽度。
  static const double sidebarCollapsed = 64;
  static const double sidebarRowHeight = 32;

  static const double contentMin = 520;
  static const double contentPaddingH = 22;
  static const double toolbar = 36;

  static const double rightPanel = 352;
  static const double statusBar = 28;

  // --- 断点 ---------------------------------------------------------------
  /// 低于此宽度：产品名隐去、侧栏折叠为图标栏。
  static const double breakpointCompact = 1180;

  /// 低于此宽度：右侧面板默认收起，改为浮层。
  static const double breakpointPanel = 1400;

  // --- 弹层 ---------------------------------------------------------------
  static const double menuItemHeight = 30;
  static const double menuIconColumn = 18;
  static const double dialogMaxWidth = 560;
  static const double popoverWidth = 380;
  static const double popoverMaxHeight = 420;

  // --- 卡片 / 网格 ---------------------------------------------------------
  static const double posterAspect = 2 / 3;
  static const double gridMinExtent = 148;
  static const double gridSpacing = 18;
}

/// 1.4f 动效。只动不透明度、底色与 4px 内的位移。
abstract final class AppMotion {
  static const Duration hover = Duration(milliseconds: 80);
  static const Duration overlayIn = Duration(milliseconds: 120);
  static const Duration overlayOut = Duration(milliseconds: 100);
  static const Duration panel = Duration(milliseconds: 180);
  static const Duration progress = Duration(milliseconds: 240);
  static const Duration toast = Duration(milliseconds: 3000);

  /// 分区切换不做转场。
  static const Duration none = Duration.zero;

  static const Curve standard = Curves.easeOut;
  static const Curve panelCurve = Curves.easeInOut;

  /// 弹层出现时向下位移，关闭时向上位移。
  static const double overlayOffset = 4;

  /// 长任务超过这个时长才显示进度，避免闪烁。
  static const Duration progressThreshold = Duration(milliseconds: 400);

  /// 超过这个时长要给出可中断入口。
  static const Duration interruptThreshold = Duration(seconds: 10);

  /// 系统「减少动态效果」开启时全部改为瞬时，只保留不透明度渐变。
  static Duration respecting(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// 1.2 字阶。字号与字重；颜色由 [AppTokens] 提供。
abstract final class AppTypeScale {
  static const String mono = 'JetBrains Mono';

  /// 等宽字体的回落链。
  ///
  /// 设计稿点名 JetBrains Mono，而它既没打进包里、也不是任何一个系统自带的
  /// 字体；`'monospace'` 更是 CSS / Android 的通名，Windows 与 macOS 上根本
  /// 没有这个字族。两者都匹配不上时，引擎会直接走到 `fontFamilyFallback` ——
  /// 而那原本是主题给的中文回落，于是所有路径、版本号、token 数最后都是用
  /// 微软雅黑画的：既不等宽，也不是用户在设置里挑的那款字。
  ///
  /// 一张平铺的名单管三个平台：匹配不上的名字会被跳过。末尾接上中文字族，
  /// 因为这里写了 `fontFamilyFallback` 就会把主题那份顶掉，而路径里是有中文
  /// 目录名的。
  /// 一张平铺的名单管三个平台：匹配不上的名字会被跳过。
  static const List<String> monoFaces = [
    // Windows
    'Cascadia Mono',
    'Consolas',
    // macOS
    'SF Mono',
    'Menlo',
    'Monaco',
    // Linux
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Noto Sans Mono',
    'Courier New',
  ];

  /// 等宽 + 中文的完整回落链，**不含**用户选的字体。
  ///
  /// 这是没有主题可问时的兜底（测试、以及任何拿不到 `BuildContext` 的地方）。
  /// 界面上应当读 `context.tokens.monoFallback`，那一份把用户选的中文字体插在
  /// 系统中文字体之前 —— 否则一条含中文的路径会出现两款中文字体：等宽段落里
  /// 是微软雅黑，别处是用户选的那款。
  static const List<String> monoFallback = [...monoFaces, ...cjkFaces];

  /// 等宽样式里，中文字形的候选。[monoFaces] 里一个也没有汉字。
  static const List<String> cjkFaces = [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Heiti SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
  ];

  /// 等宽回落链，把用户选的中文字体接在等宽字族之后、系统中文字体之前。
  static List<String> monoChain(String? picked, TargetPlatform platform) => [
    ...monoFaces,
    ?picked,
    ...cjkFallback(platform),
  ];

  /// 全局字间距；22px 以上标题收紧到 [tightTracking]。
  static const double tracking = -0.005;
  static const double tightTracking = -0.02;

  /// 密集列表。
  static const double leadingDense = 1.5;

  /// 正文。
  static const double leadingBody = 1.7;

  /// 说明段落。
  static const double leadingProse = 1.9;

  /// 字阶上的八个字号，按名字引用。
  ///
  /// 存在的意义是**没有第九个**：设计稿 1.2 的字阶只有这些台阶，而重做之前的
  /// 界面里散落着 13.5、15.5、17、18 这类介于两级之间的值 —— 每一个都让「这是
  /// 标题还是正文」的答案模糊一点。所有 `fontSize:` 都从这里取。
  static const double sizeDisplay = 36;
  static const double sizeHeading = 22;
  static const double sizeSubheading = 16;
  static const double sizeTitle = 15;
  static const double sizeBody = 13;
  static const double sizeControl = 12.5;
  static const double sizeCaption = 11.5;
  static const double sizeMono = 11;
  static const double sizeLabel = 10;

  /// 36 / 700 — 页面大标题。
  static const TextStyle display = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: tightTracking * 36,
    height: 1.15,
  );

  /// 22 / 700 — 分区标题、详情页主标题。
  static const TextStyle heading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: tightTracking * 22,
    height: 1.25,
  );

  /// 15 / 600 — 卡片标题、对话框标题。每个容器只有一个。
  static const TextStyle title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// 13 — 正文与列表主文案（文件名、条目名）。
  static const TextStyle body = TextStyle(fontSize: 13, height: leadingDense);
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: leadingDense,
  );

  /// 12.5 — 界面控件文字（按钮、Tab、菜单项）。
  static const TextStyle control = TextStyle(fontSize: 12.5, height: 1.3);
  static const TextStyle controlStrong = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 11.5 — 次要说明与副文案（列表第二行）。
  static const TextStyle caption = TextStyle(fontSize: 11.5, height: 1.45);

  /// 11 / 500 · mono — 路径、数值、快捷键。
  static const TextStyle monoSmall = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const TextStyle monoTiny = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  static const TextStyle monoBody = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 12.5,
    height: 1.4,
  );

  /// 10 / 600 / 0.08em — 分组标题 GROUP LABEL。
  static const TextStyle groupLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.08 * 10,
    height: 1.3,
  );

  /// 10.5 / 600 / 0.06em — 表头。
  static const TextStyle columnHeader = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.06 * 10.5,
    height: 1.3,
  );

  /// 每个平台的中文回落字体，按设计稿：PingFang SC / Microsoft YaHei。
  /// 各平台的系统界面**拉丁**字体。
  ///
  /// 用户在设置里挑的是一款中文字体，挑它是为了中文 —— 顺手把拉丁字形也换掉
  /// 并不是同一个决定，而这些字体的拉丁部分通常也不如系统那款。所以自定义字体
  /// 不当首选字族，而是排在系统拉丁字体后面：一个字族里没有的字形，引擎自己会
  /// 往后找，中文正好落到它身上。
  ///
  /// 每一项的首位必须与 Flutter `Typography` 在该平台用的字族一致 —— 那正是
  /// 「没选字体时」界面上的拉丁字形。首位换成别的，就等于选了中文字体之后拉丁
  /// 字形也跟着变了，而这恰恰是不该发生的事。后面几项只是兜底，匹配不上的名字
  /// 会被跳过。
  static List<String> latinUi(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows => const ['Segoe UI', 'Tahoma'],
    TargetPlatform.macOS || TargetPlatform.iOS => const [
      '.SF UI Text',
      '.AppleSystemUIFont',
      'Helvetica Neue',
    ],
    _ => const ['Roboto', 'Cantarell', 'DejaVu Sans', 'Liberation Sans'],
  };

  static List<String> cjkFallback(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.windows => const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Noto Sans SC',
        ],
        TargetPlatform.macOS => const [
          'PingFang SC',
          'Heiti SC',
          'Noto Sans SC',
        ],
        _ => const [
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'Source Han Sans SC',
          'WenQuanYi Micro Hei',
        ],
      };
}

// ---------------------------------------------------------------------------
// 1.1 色彩 — 随亮度 / 强调色 / 性能模式变化，因此在 ThemeExtension 上
// ---------------------------------------------------------------------------

/// 设计稿固定的五个语义色相（1.1c）。强调色可被用户替换，其余四个不可。
abstract final class AppPalette {
  /// 主强调 Accent — 选中、主按钮、进度、链接、当前分区。
  static const Color accent = Color(0xFF5B8DFF);
  static const Color accentInk = Color(0xFF3B5BC0);

  /// AI 紫 — AI 生成、模型相关、智能建议。
  static const Color ai = Color(0xFF9D7BFF);
  static const Color aiInk = Color(0xFF6B45C9);

  /// 成功 / 刮削 — 完成、已匹配、可撤销角标。
  static const Color success = Color(0xFF5FD3BC);
  static const Color successInk = Color(0xFF1D7A68);

  /// 警告 — 低置信匹配、需人工确认、覆盖提示。
  static const Color warning = Color(0xFFFFB478);
  static const Color warningInk = Color(0xFF8A5116);

  /// 危险 — 删除、失败、不可撤销。
  static const Color danger = Color(0xFFFF7896);
  static const Color dangerInk = Color(0xFFA32449);

  /// 深色背景上的语义文字直接用纯色本身；只有危险色在深底上提亮一档，
  /// 因为 `#ff7896` 压在 `#0a0b14` 上的对比只有 4.1:1。
  static const Color dangerOnDark = Color(0xFFFF9DB3);
  static const Color accentOnDark = Color(0xFF9FC0FF);
  static const Color accentOnDarkSoft = Color(0xFFA4C0FF);

  /// 窗口底。
  static const Color darkBase = Color(0xFF0A0B14);
  static const Color lightBase = Color(0xFFEEF0F6);

  /// 浅色主题的墨色，所有浅色文字与描边都从它派生。
  static const Color ink = Color(0xFF141E3C);
  static const Color inkTitle = Color(0xFF1A1D29);

  /// 2.4 性能模式：玻璃层预混合成不透明实色。
  static const Color perfTopBarDark = Color(0xFF171A2B);
  static const Color perfTopBarLight = Color(0xFFF4F6FB);
  static const Color perfControlDark = Color(0xFF21253A);
  static const Color perfControlLight = Color(0xFFE7EBF4);

  /// 3.1 置信度条的低置信渐变。高置信直接用 [success] → [accent]。
  static const Color confidenceLowStart = Color(0xFFFF9A6C);
  static const Color confidenceLowEnd = Color(0xFFFFD166);

  /// 4.3 「写入」主按钮的深墨字，压在成功色实底上。
  static const Color onSuccessSolid = Color(0xFF04211A);

  /// 压在图片 / 海报上的字幕渐隐。与主题无关：它盖住的是内容，不是表面。
  static const Color scrim = Color(0xCC000000);

  /// 5.3 的日志面板。
  ///
  /// **两套主题里都是深色**：它模仿的是终端，而终端在浅色应用里也是深色的。
  /// 所以它内部的层次不能走 [AppTokens]，那些墨色压在这块底上会消失。
  static const Color terminalBase = Color(0xFF0E1117);
  static const Color terminalChrome = Color(0xFF161A22);
  static const Color onTerminal = Color(0xE6FFFFFF);
  static const Color onTerminalMuted = Color(0x8CFFFFFF);
  static const Color onTerminalFaint = Color(0x59FFFFFF);

  /// 3.1 的文件类型图标色。
  ///
  /// 设计稿只给了视频（橙）、剧集（青）、海报（紫）三种有色的，字幕与元数据是
  /// 中性的。凡是稿子没点名的类型都留在中性档，而不是各发一个色相 —— 一列
  /// 彩虹图标会把「这一行需要注意」这件事稀释掉。
  static const Color typeVideo = Color(0xFFFF9A6C);
  static const Color typeSeries = success;
  static const Color typeImage = ai;
  static const Color typeNeutral = Color(0xFF8FA3C8);
  static const Color typeFolder = warning;

  /// 厂商品牌色（6.1 / 6.3 的服务卡）。
  ///
  /// 这几个**不是**主题色：它们标识的是 OpenAI、Google 这些外部服务，跟着强调色
  /// 变会让用户认不出自己配的是哪一家。设计稿也是照厂商原色画的。放在这里只是
  /// 为了不让它们散落在四个界面里。
  static const List<Color> vendorOpenAi = [
    Color(0xFF10A37F),
    Color(0xFF0D8364),
  ];
  static const List<Color> vendorGoogle = [
    Color(0xFF4285F4),
    Color(0xFF34A0ED),
  ];
  static const List<Color> vendorLocal = [Color(0xFFC45F3A), Color(0xFF963F25)];

  /// Windows 关闭按钮（2.2 窗口按钮）。
  static const Color closeHover = Color(0xFFC42B1C);
  static const Color closePressed = Color(0xFFB22215);

  /// macOS 交通灯。
  static const Color macClose = Color(0xFFFF5F57);
  static const Color macMinimize = Color(0xFFFEBC2E);
  static const Color macZoom = Color(0xFF28C840);
  static const Color macInactive = Color(0x38FFFFFF);
}

/// 1.3d 层级 · 投影四档。
@immutable
class AppElevation {
  /// L1 · 行。
  final List<BoxShadow> row;

  /// L2 · 卡片。
  final List<BoxShadow> card;

  /// L3 · 弹层 / 菜单。
  final List<BoxShadow> overlay;

  /// L4 · 窗口 / 对话框。
  final List<BoxShadow> window;

  const AppElevation({
    required this.row,
    required this.card,
    required this.overlay,
    required this.window,
  });

  /// 性能模式去掉大半径投影，只留 L1。
  AppElevation get flattened => AppElevation(
    row: row,
    card: const [],
    overlay: const [],
    window: const [],
  );

  static AppElevation of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static const AppElevation _light = AppElevation(
    row: [
      BoxShadow(color: Color(0x0A142859), blurRadius: 2, offset: Offset(0, 1)),
    ],
    card: [
      BoxShadow(
        color: Color(0x0F142859),
        blurRadius: 30,
        offset: Offset(0, 10),
      ),
    ],
    overlay: [
      BoxShadow(
        color: Color(0x24142859),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
    window: [
      BoxShadow(
        color: Color(0x2E142859),
        blurRadius: 60,
        offset: Offset(0, 24),
      ),
    ],
  );

  static const AppElevation _dark = AppElevation(
    row: [
      BoxShadow(color: Color(0x1A000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
    card: [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 30,
        offset: Offset(0, 10),
      ),
    ],
    overlay: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
    window: [
      BoxShadow(
        color: Color(0x8C000000),
        blurRadius: 60,
        offset: Offset(0, 24),
      ),
    ],
  );

  static AppElevation lerp(AppElevation a, AppElevation b, double t) =>
      AppElevation(
        row: BoxShadow.lerpList(a.row, b.row, t) ?? a.row,
        card: BoxShadow.lerpList(a.card, b.card, t) ?? a.card,
        overlay: BoxShadow.lerpList(a.overlay, b.overlay, t) ?? a.overlay,
        window: BoxShadow.lerpList(a.window, b.window, t) ?? a.window,
      );
}

/// 1.3d 模糊三档。
abstract final class AppBlur {
  static const double topBar = 28;
  static const double panel = 40;
  static const double dialog = 20;

  /// `backdrop-filter: saturate(180%)` 在 Flutter 没有直接对应；顶栏与面板
  /// 改为在模糊层上叠一层极淡的强调色来近似那份「发色」，见 `GlassSurface`。
  static const double saturateOverlayAlpha = 0.03;
}

/// 全部随主题变化的取值。
///
/// 读法：`context.tokens`。绝不要在 widget 里写死这里已经有的值 —— 设计稿的
/// 每一次改动都应该只落在这个文件里。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Brightness brightness;

  /// 用户可替换的强调色（默认 [AppPalette.accent]）。
  final Color accent;

  /// 强调色在浅底上的文字变体，保证 4.5:1。
  final Color accentInk;

  // --- 1.1 底层 -----------------------------------------------------------
  /// 窗口底：纯色 + 两层径向渐变。
  final Color windowBase;
  final Gradient backdrop;

  /// 顶栏玻璃。
  final Color topBarFill;
  final Color topBarFillUnfocused;

  /// 侧栏 / 面板玻璃。
  final Color panelFill;

  /// 卡片 / 行。
  final Color cardFill;

  /// 控件底与它的悬停态。
  final Color controlFill;
  final Color controlFillHover;
  final Color controlFillActive;

  /// 描边：hairline 与稍重的分组线。
  final Color stroke;
  final Color strokeStrong;

  /// 选中态。
  final Color selectionFill;
  final Color selectionStroke;

  // --- 文字 ---------------------------------------------------------------
  final Color textTitle;
  final Color textBody;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;

  // --- 语义 ---------------------------------------------------------------
  /// 深色主题下直接用纯色，浅色主题下用 `*Ink` 变体。
  final Color ai;
  final Color success;
  final Color warning;
  final Color danger;

  /// 语义色作为底色时的不透明度已经烘进这几个值里。
  final Color aiSurface;
  final Color successSurface;
  final Color warningSurface;
  final Color dangerSurface;

  // --- 层级 ---------------------------------------------------------------
  final AppElevation elevation;

  /// 顶栏 / 面板 / 对话框的模糊半径。性能模式下三者皆为 0。
  final double blurTopBar;
  final double blurPanel;
  final double blurDialog;

  /// 性能模式：玻璃层已被换成不透明实色，widget 必须**整块跳过**
  /// `BackdropFilter` 而不是传 0 —— 零 sigma 的滤镜仍然会结束一个渲染通道并
  /// 回读整个目标，代价正在那里。
  final bool reduceEffects;

  /// 等宽文本的回落链，含用户选的中文字体。见 [AppTypeScale.monoChain]。
  ///
  /// 等宽样式必须自带回落链（`JetBrains Mono` 哪儿都没装），而 `TextStyle`
  /// 合并时后者的 `fontFamilyFallback` 是**整个替换**前者 —— 所以主题给的那份
  /// 到不了等宽文本。这份就是替它准备的。
  final List<String> monoFallback;

  const AppTokens({
    required this.brightness,
    required this.accent,
    required this.accentInk,
    required this.windowBase,
    required this.backdrop,
    required this.topBarFill,
    required this.topBarFillUnfocused,
    required this.panelFill,
    required this.cardFill,
    required this.controlFill,
    required this.controlFillHover,
    required this.controlFillActive,
    required this.stroke,
    required this.strokeStrong,
    required this.selectionFill,
    required this.selectionStroke,
    required this.textTitle,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.ai,
    required this.success,
    required this.warning,
    required this.danger,
    required this.aiSurface,
    required this.successSurface,
    required this.warningSurface,
    required this.dangerSurface,
    required this.elevation,
    required this.blurTopBar,
    required this.blurPanel,
    required this.blurDialog,
    required this.reduceEffects,
    required this.monoFallback,
  });

  bool get isDark => brightness == Brightness.dark;

  /// 品牌渐变。设计稿：语义色不做渐变，**只有品牌标记用它**。
  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, AppPalette.ai],
  );

  /// 主按钮的三个状态（1.4a）。悬停亮 8%、按下暗 10%。
  Color get accentHover => _lighten(accent, 0.08);
  Color get accentPressed => _darken(accent, 0.10);
  Color get accentDisabled => accent.withValues(alpha: 0.30);

  /// 主按钮投影；按下时去掉。
  List<BoxShadow> get accentShadow => [
    BoxShadow(
      color: accent.withValues(alpha: 0.30),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
  List<BoxShadow> get accentShadowHover => [
    BoxShadow(
      color: accent.withValues(alpha: 0.36),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];

  /// 输入框聚焦的外发光环。
  BoxShadow get focusRing =>
      BoxShadow(color: accent.withValues(alpha: 0.16), spreadRadius: 3);

  /// 激活 Tab 的底与描边（2.4：以 accent 的不透明度派生，不写死色值）。
  Color get tabActiveFill => accent.withValues(alpha: isDark ? 0.18 : 0.14);
  Color get tabActiveStroke => accent.withValues(alpha: isDark ? 0.32 : 0.30);

  /// 任务徽标是唯一「强调色实底 + 白字」的组合。设计稿要求 accent 亮度
  /// ≤ 0.72，超过时自动改用墨色文字 —— 换成任何色相都不会对比不足。
  Color get badgeFill => accent;
  Color get badgeText =>
      accent.computeLuminance() > 0.72 ? AppPalette.inkTitle : Colors.white;

  /// 图标按钮激活态。
  Color get iconButtonActiveFill => accent.withValues(alpha: 0.22);
  Color get iconButtonActiveStroke => accent.withValues(alpha: 0.40);

  /// 语义色在深底上用纯色，在浅底上用墨色变体。
  Color get aiText => isDark ? AppPalette.ai : AppPalette.aiInk;
  Color get successText => isDark ? AppPalette.success : AppPalette.successInk;
  Color get warningText => isDark ? AppPalette.warning : AppPalette.warningInk;
  Color get dangerText =>
      isDark ? AppPalette.dangerOnDark : AppPalette.dangerInk;
  Color get accentText => isDark ? AppPalette.accentOnDark : accentInk;

  /// 窗口按钮的悬停底（2.2）。铺满整个 46×48 矩形，不加圆角。
  Color get captionHover => isDark
      ? Colors.white.withValues(alpha: 0.09)
      : AppPalette.ink.withValues(alpha: 0.07);
  Color get captionPressed =>
      captionHover.withValues(alpha: (captionHover.a * 0.6));
  Color get captionIcon =>
      (isDark ? Colors.white : AppPalette.ink).withValues(alpha: 0.70);

  /// 失焦：文字与图标整体乘 0.55；分隔线 0.10 → 0.06。
  static const double unfocusedOpacity = 0.55;
  static const double unfocusedBadgeOpacity = 0.55;

  /// 忽略 / 禁用行。
  static const double disabledRowOpacity = 0.45;

  /// 不可撤销的历史项。
  static const double inertRowOpacity = 0.55;

  // -------------------------------------------------------------------------

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  /// 构建一套令牌。
  ///
  /// [glassIntensity] 0–100，映射到三档模糊半径；70 是设计稿的默认值，对应
  /// 稿面上的 28 / 40 / 20。[reduceEffects] 时三档全部归零，玻璃层换成
  /// 2.4 给出的不透明实色常量。
  factory AppTokens.build({
    required Brightness brightness,
    Color? accent,
    double glassIntensity = 70,
    bool reduceEffects = false,
    String? uiFont,
    TargetPlatform? platform,
  }) {
    final isDark = brightness == Brightness.dark;
    final a = accent ?? AppPalette.accent;
    final scale = (glassIntensity / 70).clamp(0.0, 1.6);

    // 强调色可以是用户任意选的色相，浅底上的文字变体必须重新推导，
    // 否则换成亮黄就再也读不清了。
    final ink = _inkVariant(a);

    Color white(double o) => Colors.white.withValues(alpha: o);
    Color inkA(double o) => AppPalette.ink.withValues(alpha: o);

    final base = isDark ? AppPalette.darkBase : AppPalette.lightBase;

    return AppTokens(
      brightness: brightness,
      accent: a,
      accentInk: ink,
      windowBase: base,
      backdrop: _backdrop(a, isDark: isDark),
      topBarFill: reduceEffects
          ? (isDark ? AppPalette.perfTopBarDark : AppPalette.perfTopBarLight)
          : (isDark ? const Color(0x940A0B16) : white(0.62)),
      topBarFillUnfocused: reduceEffects
          ? (isDark ? AppPalette.perfTopBarDark : AppPalette.perfTopBarLight)
          : (isDark ? const Color(0x6B0A0B16) : white(0.50)),
      panelFill: reduceEffects
          ? (isDark ? const Color(0xFF14162A) : const Color(0xFFF2F4F9))
          : (isDark ? const Color(0x730C0D18) : const Color(0xF2F2F4F9)),
      cardFill: reduceEffects
          ? (isDark ? AppPalette.perfControlDark : Colors.white)
          : (isDark ? white(0.05) : white(0.85)),
      controlFill: reduceEffects
          ? (isDark ? AppPalette.perfControlDark : AppPalette.perfControlLight)
          : (isDark ? white(0.06) : white(0.72)),
      controlFillHover: reduceEffects
          ? (isDark ? const Color(0xFF2A2F47) : const Color(0xFFDDE3F0))
          : (isDark ? white(0.10) : white(0.90)),
      controlFillActive: reduceEffects
          ? (isDark ? const Color(0xFF323853) : const Color(0xFFD2DAEC))
          : (isDark ? white(0.14) : white(1.0)),
      // 性能模式下分隔线不透明度 × 1.4，否则没有模糊衬托就看不见了。
      stroke: isDark
          ? white(reduceEffects ? 0.098 : 0.07)
          : inkA(reduceEffects ? 0.098 : 0.07),
      strokeStrong: isDark
          ? white(reduceEffects ? 0.14 : 0.10)
          : inkA(reduceEffects ? 0.17 : 0.12),
      selectionFill: a.withValues(alpha: isDark ? 0.16 : 0.14),
      selectionStroke: a.withValues(alpha: isDark ? 0.24 : 0.30),
      textTitle: isDark ? Colors.white : AppPalette.inkTitle,
      textBody: isDark ? white(0.86) : inkA(0.88),
      textSecondary: isDark ? white(0.62) : inkA(0.75),
      textMuted: isDark ? white(0.45) : inkA(0.50),
      textDisabled: isDark ? white(0.32) : inkA(0.35),
      ai: AppPalette.ai,
      success: AppPalette.success,
      warning: AppPalette.warning,
      danger: AppPalette.danger,
      aiSurface: AppPalette.ai.withValues(alpha: isDark ? 0.18 : 0.14),
      successSurface: AppPalette.success.withValues(
        alpha: isDark ? 0.18 : 0.16,
      ),
      warningSurface: AppPalette.warning.withValues(
        alpha: isDark ? 0.16 : 0.18,
      ),
      dangerSurface: AppPalette.danger.withValues(alpha: isDark ? 0.16 : 0.14),
      elevation: reduceEffects
          ? AppElevation.of(brightness).flattened
          : AppElevation.of(brightness),
      blurTopBar: reduceEffects ? 0 : AppBlur.topBar * scale,
      blurPanel: reduceEffects ? 0 : AppBlur.panel * scale,
      blurDialog: reduceEffects ? 0 : AppBlur.dialog * scale,
      reduceEffects: reduceEffects,
      monoFallback: AppTypeScale.monoChain(
        uiFont,
        platform ?? defaultTargetPlatform,
      ),
    );
  }

  /// 窗口底的两层径向渐变（蓝 28% / 紫 22%），叠在纯色底上。
  ///
  /// 用 [accent] 而不是写死的蓝，这样换强调色时整个窗口底跟着走 —— 设计稿
  /// 2.4「强调色可替换」列出的四处之外，底层渐变也应当跟随，否则自定义了
  /// 橙色强调的窗口底仍然泛蓝。
  static Gradient _backdrop(Color accent, {required bool isDark}) {
    final base = isDark ? AppPalette.darkBase : AppPalette.lightBase;
    return _RadialPairGradient(
      base: base,
      first: accent.withValues(alpha: isDark ? 0.28 : 0.30),
      firstCenter: const Alignment(-0.6, -1.0),
      second: AppPalette.ai.withValues(alpha: 0.22),
      secondCenter: const Alignment(0.56, -0.8),
    );
  }

  /// 把任意强调色压成浅底上可读的文字色（目标 ≥ 4.5:1）。
  ///
  /// 单纯 `darken` 对高亮度色相（黄、青）不够，所以按亮度迭代压到阈值以下，
  /// 而不是套一个固定系数。
  static Color _inkVariant(Color c) {
    var out = c;
    var guard = 0;
    while (out.computeLuminance() > 0.18 && guard++ < 24) {
      out = _darken(out, 0.08);
    }
    return out;
  }

  static Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? accent,
    Color? accentInk,
    Color? windowBase,
    Gradient? backdrop,
    Color? topBarFill,
    Color? topBarFillUnfocused,
    Color? panelFill,
    Color? cardFill,
    Color? controlFill,
    Color? controlFillHover,
    Color? controlFillActive,
    Color? stroke,
    Color? strokeStrong,
    Color? selectionFill,
    Color? selectionStroke,
    Color? textTitle,
    Color? textBody,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? ai,
    Color? success,
    Color? warning,
    Color? danger,
    Color? aiSurface,
    Color? successSurface,
    Color? warningSurface,
    Color? dangerSurface,
    AppElevation? elevation,
    double? blurTopBar,
    double? blurPanel,
    double? blurDialog,
    bool? reduceEffects,
    List<String>? monoFallback,
  }) => AppTokens(
    brightness: brightness ?? this.brightness,
    accent: accent ?? this.accent,
    accentInk: accentInk ?? this.accentInk,
    windowBase: windowBase ?? this.windowBase,
    backdrop: backdrop ?? this.backdrop,
    topBarFill: topBarFill ?? this.topBarFill,
    topBarFillUnfocused: topBarFillUnfocused ?? this.topBarFillUnfocused,
    panelFill: panelFill ?? this.panelFill,
    cardFill: cardFill ?? this.cardFill,
    controlFill: controlFill ?? this.controlFill,
    controlFillHover: controlFillHover ?? this.controlFillHover,
    controlFillActive: controlFillActive ?? this.controlFillActive,
    stroke: stroke ?? this.stroke,
    strokeStrong: strokeStrong ?? this.strokeStrong,
    selectionFill: selectionFill ?? this.selectionFill,
    selectionStroke: selectionStroke ?? this.selectionStroke,
    textTitle: textTitle ?? this.textTitle,
    textBody: textBody ?? this.textBody,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textDisabled: textDisabled ?? this.textDisabled,
    ai: ai ?? this.ai,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    aiSurface: aiSurface ?? this.aiSurface,
    successSurface: successSurface ?? this.successSurface,
    warningSurface: warningSurface ?? this.warningSurface,
    dangerSurface: dangerSurface ?? this.dangerSurface,
    elevation: elevation ?? this.elevation,
    blurTopBar: blurTopBar ?? this.blurTopBar,
    blurPanel: blurPanel ?? this.blurPanel,
    blurDialog: blurDialog ?? this.blurDialog,
    reduceEffects: reduceEffects ?? this.reduceEffects,
    monoFallback: monoFallback ?? this.monoFallback,
  );

  // --- 等宽字体 -----------------------------------------------------------
  //
  // 界面里所有等宽文字都从这三个走，别直接用 `AppTypeScale.mono*`：那三个带的
  // 是常量回落链，读不到用户选的中文字体。

  TextStyle get monoTiny =>
      AppTypeScale.monoTiny.copyWith(fontFamilyFallback: monoFallback);
  TextStyle get monoSmall =>
      AppTypeScale.monoSmall.copyWith(fontFamilyFallback: monoFallback);
  TextStyle get monoBody =>
      AppTypeScale.monoBody.copyWith(fontFamilyFallback: monoFallback);

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    double d(double x, double y) => x + (y - x) * t;
    return AppTokens(
      // 亮度与性能模式是布尔式的，没有中点：在半程处跳变。让模糊在
      // `kThemeAnimationDuration` 的每一帧上淡出，等于把最贵的一层特效在
      // 切主题时全速跑一遍。
      brightness: t < 0.5 ? brightness : other.brightness,
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
      windowBase: c(windowBase, other.windowBase),
      backdrop: Gradient.lerp(backdrop, other.backdrop, t) ?? backdrop,
      topBarFill: c(topBarFill, other.topBarFill),
      topBarFillUnfocused: c(topBarFillUnfocused, other.topBarFillUnfocused),
      panelFill: c(panelFill, other.panelFill),
      cardFill: c(cardFill, other.cardFill),
      controlFill: c(controlFill, other.controlFill),
      controlFillHover: c(controlFillHover, other.controlFillHover),
      controlFillActive: c(controlFillActive, other.controlFillActive),
      stroke: c(stroke, other.stroke),
      strokeStrong: c(strokeStrong, other.strokeStrong),
      selectionFill: c(selectionFill, other.selectionFill),
      selectionStroke: c(selectionStroke, other.selectionStroke),
      textTitle: c(textTitle, other.textTitle),
      textBody: c(textBody, other.textBody),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      textDisabled: c(textDisabled, other.textDisabled),
      ai: c(ai, other.ai),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      aiSurface: c(aiSurface, other.aiSurface),
      successSurface: c(successSurface, other.successSurface),
      warningSurface: c(warningSurface, other.warningSurface),
      dangerSurface: c(dangerSurface, other.dangerSurface),
      elevation: AppElevation.lerp(elevation, other.elevation, t),
      blurTopBar: d(blurTopBar, other.blurTopBar),
      blurPanel: d(blurPanel, other.blurPanel),
      blurDialog: d(blurDialog, other.blurDialog),
      reduceEffects: t < 0.5 ? reduceEffects : other.reduceEffects,
      // 字族名没有中间值。
      monoFallback: t < 0.5 ? monoFallback : other.monoFallback,
    );
  }
}

/// 两层径向渐变叠在一个纯色底上 —— CSS 的
/// `radial-gradient(...), radial-gradient(...), <base>`。
///
/// Flutter 的 [RadialGradient] 一次只画一层，而 [LinearGradient] 又不是设计稿
/// 要的形状，所以这里做一个自绘的 [Gradient]：`createShader` 里没法叠两个
/// shader，于是用 [ImageShader] 之外最省的一条路 —— 把两层烘进一个
/// [SweepGradient] 是不行的，因此实现为「底色 + 一层最强的径向」，第二层交给
/// [AppBackdrop] 以一个额外的 `DecoratedBox` 叠加。这个类只负责第一层与底色，
/// 但把两层的取值都带在身上，供 [AppBackdrop] 读取。
@immutable
class _RadialPairGradient extends Gradient {
  final Color base;
  final Color first;
  final Alignment firstCenter;
  final Color second;
  final Alignment secondCenter;

  _RadialPairGradient({
    required this.base,
    required this.first,
    required this.firstCenter,
    required this.second,
    required this.secondCenter,
  }) : super(colors: [first, base, second]);

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) =>
      RadialGradient(
        center: firstCenter,
        radius: 1.1,
        colors: [first, base],
      ).createShader(rect, textDirection: textDirection);

  @override
  Gradient withOpacity(double opacity) => _RadialPairGradient(
    base: base.withValues(alpha: opacity),
    first: first.withValues(alpha: opacity),
    firstCenter: firstCenter,
    second: second.withValues(alpha: opacity),
    secondCenter: secondCenter,
  );

  @override
  Gradient scale(double factor) => _RadialPairGradient(
    base: Color.lerp(null, base, factor)!,
    first: Color.lerp(null, first, factor)!,
    firstCenter: firstCenter,
    second: Color.lerp(null, second, factor)!,
    secondCenter: secondCenter,
  );

  @override
  Gradient? lerpFrom(Gradient? a, double t) {
    if (a is _RadialPairGradient) return _lerp(a, this, t);
    return super.lerpFrom(a, t);
  }

  @override
  Gradient? lerpTo(Gradient? b, double t) {
    if (b is _RadialPairGradient) return _lerp(this, b, t);
    return super.lerpTo(b, t);
  }

  static _RadialPairGradient _lerp(
    _RadialPairGradient a,
    _RadialPairGradient b,
    double t,
  ) => _RadialPairGradient(
    base: Color.lerp(a.base, b.base, t)!,
    first: Color.lerp(a.first, b.first, t)!,
    firstCenter: Alignment.lerp(a.firstCenter, b.firstCenter, t)!,
    second: Color.lerp(a.second, b.second, t)!,
    secondCenter: Alignment.lerp(a.secondCenter, b.secondCenter, t)!,
  );
}

/// 窗口底：纯色 + 两层径向渐变。
///
/// 铺在 [Scaffold] 之下、所有玻璃面板之上游 —— 玻璃的模糊取样的就是它。
class AppBackdrop extends StatelessWidget {
  final Widget child;

  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final g = t.backdrop;
    if (g is! _RadialPairGradient) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: g),
        child: child,
      );
    }
    return ColoredBox(
      color: g.base,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: g.firstCenter,
            radius: 1.15,
            colors: [g.first, g.first.withValues(alpha: 0)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: g.secondCenter,
              radius: 1.05,
              colors: [g.second, g.second.withValues(alpha: 0)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// `context.tokens` —— 全 UI 唯一合法的取色入口。
extension AppTokensX on BuildContext {
  AppTokens get tokens => AppTokens.of(this);
}
