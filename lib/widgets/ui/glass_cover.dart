import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 「我这条路由现在被一个**不透明**路由盖住了吗」。
///
/// [GlassSurface] 用它来决定要不要建 `BackdropFilter`：盖在上面的整页路由是
/// 不透明的，底下那层的模糊一个像素都看不见，却照样每帧做一次全屏背景回读。
///
/// 实测（3024x1772、dpr 2.0、ProMotion 120Hz，每帧预算 8.3ms）：推开设置页的
/// 300ms 里两棵树同时绘制，一帧要做 8 次 backdrop 回读，光栅 p50 8.5–10.5ms，
/// **30 帧无一例外超预算**；关掉模糊的对照组（性能模式）是 1.7–3.8ms。主页那
/// 6 个滤镜里有 4 个是大块的（文件表 872x718、侧栏 244x810、AI 面板 352x810、
/// 顶栏 1512x48），全是白做的。
///
/// **为什么不能只看 `ModalRoute.secondaryAnimation`。** 压上来的任何路由都会
/// 驱动它，对话框、菜单、popover 全算 —— 而那些是半透明的，下面那层照样看得
/// 见，把它的模糊关掉是肉眼可见的塌陷。只有 `opaque` 的路由才真的挡住了下面，
/// 所以这里跟的是导航栈本身，而不是某个动画。
class OpaqueCoverObserver extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _stack = [];

  /// [route] 之上是否还压着不透明的路由。栈外的路由（还没推上来、或已经弹掉）
  /// 一律答否 —— 它本来也不在画。
  bool isCovered(Route<dynamic>? route) {
    if (route == null) return false;
    final index = _stack.indexOf(route);
    if (index < 0) return false;
    for (var i = index + 1; i < _stack.length; i++) {
      final above = _stack[i];
      if (above is TransitionRoute && above.opaque) return true;
    }
    return false;
  }

  /// Navigator 会在 **build 期间** flush 观察者通知（初始路由的
  /// `restoreState` 就是这条路径），而这里的监听者是装在 `MaterialApp` 外面的
  /// `InheritedNotifier` —— 当场通知就是在 build 里 `markNeedsBuild` 一个祖先，
  /// 直接撞断言。build 在飞的时候推迟到帧末，其余情况照常当场通知：整页转场里
  /// 早一帧晚一帧看不出来，构建期崩掉却是硬故障。
  void _sync(void Function() mutate) {
    mutate();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
      return;
    }
    notifyListeners();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(() => _stack.add(route));

  /// 退场动画跑完才把它从栈里拿掉。
  ///
  /// `didPop` 是在弹出**开始**时调用的，而那一刻上面那页还整页画着，下面那页
  /// 还一个像素都看不见。当场移除等于让底下那层在整段退场里白白把模糊上回去
  /// —— 实测退场的光栅 p50 因此比进场高出约 3ms。
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final animation = route is TransitionRoute ? route.animation : null;
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      _sync(() => _stack.remove(route));
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(onStatus);
      _sync(() => _stack.remove(route));
    }

    animation.addStatusListener(onStatus);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(() => _stack.remove(route));

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _sync(() {
        final at = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
        if (at < 0) {
          if (newRoute != null) _stack.add(newRoute);
          return;
        }
        if (newRoute == null) {
          _stack.removeAt(at);
        } else {
          _stack[at] = newRoute;
        }
      });
}

/// 把 [OpaqueCoverObserver] 递给树里的 [GlassSurface]。装在 `MaterialApp`
/// **外面** —— 继承式 widget 照样能被路由子树看见，而观察者本身要先于
/// Navigator 存在。
class GlassCoverScope extends InheritedNotifier<OpaqueCoverObserver> {
  const GlassCoverScope({
    super.key,
    required OpaqueCoverObserver super.notifier,
    required super.child,
  });

  /// 没有 scope 时答否（widget 测试里就是这样），而不是断言：拿不到导航栈的
  /// 唯一诚实答案是「没人盖着我」，而这恰好也是改动前的行为。
  static bool isCovered(BuildContext context) {
    final observer = context
        .dependOnInheritedWidgetOfExactType<GlassCoverScope>()
        ?.notifier;
    if (observer == null) return false;
    return observer.isCovered(ModalRoute.of(context));
  }
}
