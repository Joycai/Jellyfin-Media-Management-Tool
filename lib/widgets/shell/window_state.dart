import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// 顶栏需要知道的窗口状态：是否聚焦、是否最大化、是否全屏。
///
/// 设计稿 2.3 给这三件事都定了不同的视觉：失焦时所有文字乘 0.55、激活 Tab 的
/// 强调色底换成中性白；最大化时窗口圆角归零、玻璃更不透明、并且要补回 Windows
/// 向外溢出的 8px 边框；macOS 全屏时交通灯随菜单栏隐藏，左侧预留 84 → 12。
///
/// 做成 [ChangeNotifier] 而不是每个 widget 各自挂 [WindowListener]：监听器是
/// 全局注册的，挂十个就要在每次窗口事件上跑十遍，而它们要的是同一个答案。
class WindowStateNotifier extends ChangeNotifier with WindowListener {
  bool _focused = true;
  bool _maximized = false;
  bool _fullScreen = false;
  bool _attached = false;
  bool _maximizeHovered = false;
  bool _maximizePressed = false;

  bool get isFocused => _focused;
  bool get isMaximized => _maximized;
  bool get isFullScreen => _fullScreen;

  /// 最大化按钮的悬停 / 按下，**由原生侧推过来**。
  ///
  /// Windows 只在最大化按钮于 `WM_NCHITTEST` 返回 `HTMAXBUTTON` 时才弹 Snap
  /// Layouts，而一旦这样声明，那块矩形上的鼠标输入就走非客户区，Flutter 再也
  /// 收不到 hover 或 click。所以 runner 把这两个状态转发回来，按钮才不会在
  /// 指针底下变成一块死区。其它平台永远是 false，按钮走自己的 [MouseRegion]。
  bool get maximizeHovered => _maximizeHovered;
  bool get maximizePressed => _maximizePressed;

  /// 与 `windows/runner/flutter_window.cpp` 约定的通道名。
  static const MethodChannel _captionChannel = MethodChannel(
    'jellyfin/window_caption',
  );

  /// 桌面之外（测试、web 构建产物）没有窗口，直接维持默认值。
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> attach() async {
    if (_attached || !supported) return;
    _attached = true;
    windowManager.addListener(this);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _captionChannel.setMethodCallHandler(_onCaptionCall);
    }
    // 首帧之前把真实状态读回来：从最大化状态恢复会话时，顶栏不应该先画一帧
    // 圆角再跳成直角。
    await _sync();
  }

  @override
  void dispose() {
    if (_attached) {
      windowManager.removeListener(this);
      if (defaultTargetPlatform == TargetPlatform.windows) {
        _captionChannel.setMethodCallHandler(null);
      }
    }
    super.dispose();
  }

  Future<void> _onCaptionCall(MethodCall call) async {
    final value = call.arguments == true;
    switch (call.method) {
      case 'maximizeHover':
        if (_maximizeHovered == value) return;
        _maximizeHovered = value;
      case 'maximizePressed':
        if (_maximizePressed == value) return;
        _maximizePressed = value;
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> _sync() async {
    final focused = await windowManager.isFocused();
    final maximized = await windowManager.isMaximized();
    final fullScreen = await windowManager.isFullScreen();
    _set(focused: focused, maximized: maximized, fullScreen: fullScreen);
  }

  void _set({bool? focused, bool? maximized, bool? fullScreen}) {
    final changed =
        (focused != null && focused != _focused) ||
        (maximized != null && maximized != _maximized) ||
        (fullScreen != null && fullScreen != _fullScreen);
    _focused = focused ?? _focused;
    _maximized = maximized ?? _maximized;
    _fullScreen = fullScreen ?? _fullScreen;
    if (changed) notifyListeners();
  }

  @override
  void onWindowFocus() => _set(focused: true);

  @override
  void onWindowBlur() => _set(focused: false);

  @override
  void onWindowMaximize() => _set(maximized: true);

  @override
  void onWindowUnmaximize() => _set(maximized: false);

  @override
  void onWindowEnterFullScreen() => _set(fullScreen: true, maximized: false);

  @override
  void onWindowLeaveFullScreen() => _set(fullScreen: false);

  /// 还原 / 最大化。双击拖拽区与最大化按钮共用。
  Future<void> toggleMaximize() async {
    if (!supported) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> minimize() =>
      supported ? windowManager.minimize() : Future.value();

  Future<void> close() => supported ? windowManager.close() : Future.value();

  /// 右键拖拽区弹出系统窗口菜单（移动 / 大小 / 最小化 / 关闭）。
  Future<void> showSystemMenu() =>
      supported ? windowManager.popUpWindowMenu() : Future.value();

  Future<void> startDragging() =>
      supported ? windowManager.startDragging() : Future.value();
}

/// 让顶栏之下的任何 widget 都能读到窗口状态。
class WindowStateScope extends InheritedNotifier<WindowStateNotifier> {
  const WindowStateScope({
    super.key,
    required WindowStateNotifier super.notifier,
    required super.child,
  });

  /// 没有 scope 时回落到一个惰性单例，而不是断言。
  ///
  /// 顶栏在 widget 测试里是被单独立起来的，`main()` 不跑，自然也没有窗口；
  /// 一个「窗口永远聚焦、从未最大化」的空状态是那种环境下唯一诚实的答案，
  /// 而断言只会让每个碰到外壳的测试都要先搭一遍脚手架。
  static final WindowStateNotifier _detached = WindowStateNotifier();

  static WindowStateNotifier of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WindowStateScope>()
          ?.notifier ??
      _detached;

  /// 只读一次、不订阅。给只在回调里用状态的地方。
  static WindowStateNotifier read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WindowStateScope>()?.notifier ??
      _detached;
}
