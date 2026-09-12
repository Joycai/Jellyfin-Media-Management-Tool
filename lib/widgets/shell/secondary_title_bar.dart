import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';
import 'caption_buttons.dart';
import 'window_state.dart';

/// 二级页面的顶栏（6.x / 5.x 的「← 媒体库」那一条）。
///
/// 存在的理由不只是好看：主顶栏被 `Navigator.push` 的整页路由盖住之后，窗口就
/// **没有任何可拖拽区域、也没有窗口按钮了** —— 隐藏系统标题栏换来的代价必须由
/// 每一个整页界面自己付。所以设置、历史、进度这些页都戴同一条 48px。
///
/// 与主顶栏共用：高度、玻璃底、失焦规则、拖拽/双击/右键行为、窗口按钮。
/// 不同的是左侧换成返回按钮 + 标题 + 面包屑，中间不放搜索。
class SecondaryTitleBar extends StatelessWidget {
  /// 返回按钮的文案（「媒体库」）。
  final String backLabel;
  final VoidCallback onBack;

  final String title;

  /// 标题右侧的面包屑 / 说明。
  final String? subtitle;

  /// 右侧内容（版本行、筛选器等），窗口按钮之前。
  final List<Widget> actions;

  const SecondaryTitleBar({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  static bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final window = WindowStateScope.of(context);
    final focused = window.isFocused;

    return LayoutBuilder(
      builder: (context, box) =>
          _bar(context, t, window, focused, box.maxWidth),
    );
  }

  Widget _bar(
    BuildContext context,
    AppTokens t,
    WindowStateNotifier window,
    bool focused,
    double width,
  ) {
    // 窄窗口先丢面包屑，再让标题省略 —— 返回按钮和窗口按钮都不能压缩：
    // 一个是唯一的出口，另一个是唯一的关窗方式。
    final showSubtitle =
        subtitle != null && width >= AppSizes.breakpointCompact;
    return GlassSurface(
      fill: focused ? t.topBarFill : t.topBarFillUnfocused,
      blur: t.blurTopBar,
      saturate: true,
      border: Border(bottom: BorderSide(color: t.stroke)),
      child: SizedBox(
        height: AppSizes.topBar,
        child: Stack(
          // 行必须撑满 48：Windows/Linux 那边 WindowCaptionButtons 恰好是 48 高，
          // 把行顶到满高；macOS 走的是 `SizedBox(width:)` 分支，没有任何 48 高的
          // 孩子，行就只有最高控件那么高（28），在 Stack 里靠顶排 —— 返回按钮、
          // 标题、面包屑于是整体上移 10px，与系统交通灯错开。
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => window.startDragging(),
                onDoubleTap: window.toggleMaximize,
                onSecondaryTap: window.showSystemMenu,
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: _isMac && !window.isFullScreen
                      ? AppSizes.macTrafficLightInset
                      : AppSizes.topBarLeftInset,
                ),
                Expanded(
                  child: Opacity(
                    opacity: focused ? 1 : AppTokens.unfocusedOpacity,
                    child: Row(
                      children: [
                        AppButton(
                          label: backLabel,
                          icon: Icons.arrow_back_rounded,
                          height: AppSizes.controlSm,
                          onPressed: onBack,
                        ),
                        const AppVerticalDivider(),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypeScale.title.copyWith(
                              fontSize: AppTypeScale.sizeBody,
                              color: t.textTitle,
                            ),
                          ),
                        ),
                        if (showSubtitle) ...[
                          const SizedBox(width: AppSpacing.md12),
                          Flexible(
                            child: Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.caption.copyWith(
                                color: t.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Opacity(
                  opacity: focused ? 1 : AppTokens.unfocusedOpacity,
                  child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                ),
                if (!_isMac) ...[
                  const AppVerticalDivider(),
                  WindowCaptionButtons(window: window),
                ] else
                  const SizedBox(width: AppSizes.topBarLeftInset),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
