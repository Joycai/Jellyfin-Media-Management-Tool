import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../ui/app_backdrop.dart';
import '../ui/glass_surface.dart';
import 'window_state.dart';

/// 窗口框架：窗口底 → 顶栏 → 主体 → 状态栏。
///
/// 三件只有这里知道的事：
///
/// * **窗口圆角交给系统，这里一个像素都不裁。** 设计稿 1.3b 要 macOS 12 /
///   Windows 10 的窗口圆角，而两个系统对无边框窗口本来就会自己倒角（DWM 在
///   Win11 上、AppKit 在 macOS 上）。我们再套一层 `ClipRRect` 只会在四角露出
///   Flutter 窗口的不透明底色 —— 除非整个原生窗口是透明的，而那要动 C++/Swift
///   并且会连带丢掉系统投影。所以「最大化时圆角归零」也是白拿的：系统自己会。
/// * **Windows 最大化时窗口向外溢出 8px 边框**，不补回内边距主体就会被裁掉一圈。
///   这是 Win32 的既有行为，不是 Flutter 的问题，所以补偿只能在这一层做。
/// * 窗口底的两层径向渐变由 [AppBackdrop] 画 —— 所有玻璃面板模糊时采样的就是它，
///   所以它必须在最底下，且**不能**被裹进任何 `BackdropFilter`。
/// * **外壳的玻璃面共用一次背景快照。** 顶栏 / 侧栏 / 中栏 / 右面板 / 状态栏是
///   同一平面上互不重叠的五块，各自独立快照就是白白多读几次全屏渲染目标：实测
///   最大化 4K 下 80.4ms → 64.6ms。[BackdropGroup] 只覆盖这棵子树，对话框、
///   菜单、浮层都是 push 上来的 route，够不到它 —— 这正是要的：它们**盖在**面板
///   之上，需要模糊到面板本身，同组共享快照会让重叠处只剩一层模糊的效果。
class AppShell extends StatelessWidget {
  final Widget titleBar;
  final Widget body;

  /// 状态栏 h28 · 仅文字与进度，无按钮。null = 不显示。
  final Widget? statusBar;

  const AppShell({
    super.key,
    required this.titleBar,
    required this.body,
    this.statusBar,
  });

  @override
  Widget build(BuildContext context) {
    final window = WindowStateScope.of(context);
    final maximized = window.isMaximized;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titleBar,
        Expanded(child: body),
        ?statusBar,
      ],
    );

    // 最大化时 Windows 把窗口向外撑出 8px；把它加回内边距，否则顶栏的窗口按钮
    // 和左侧品牌都会被切掉半截。
    if (isWindows && maximized) {
      content = Padding(
        padding: const EdgeInsets.all(AppSizes.windowsMaximizedInset),
        child: content,
      );
    }

    return AppBackdrop(child: BackdropGroup(child: content));
  }
}

/// 状态栏 h28 · 仅文字与进度，无按钮。
class AppStatusBar extends StatelessWidget {
  /// 左侧：计数、总大小这类事实。
  final List<Widget> leading;

  /// 右侧：最近一次操作的状态（语义圆点 + 文案）。
  final List<Widget> trailing;

  const AppStatusBar({
    super.key,
    this.leading = const [],
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlassSurface(
      fill: t.panelFill,
      blur: t.blurPanel,
      border: Border(top: BorderSide(color: t.stroke)),
      child: SizedBox(
        height: AppSizes.statusBar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.contentPaddingH,
          ),
          child: DefaultTextStyle.merge(
            style: AppTypeScale.caption.copyWith(color: t.textSecondary),
            child: Row(
              children: [
                for (final w in leading) ...[
                  w,
                  const SizedBox(width: AppSpacing.md12),
                ],
                const Spacer(),
                for (final w in trailing) ...[
                  const SizedBox(width: AppSpacing.md12),
                  w,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态栏 / 面板脚里的「语义圆点 + 文案」。
class StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const StatusDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(label),
    ],
  );
}
