import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';
import 'caption_buttons.dart';
import 'window_state.dart';

/// 一级分区。中文最长 3 字、英文最长 1 词（1.2 排版规则）。
enum AppSection { files, library, tasks }

/// 统一顶栏 —— 设计稿 2.1 的「方案 A」。
///
/// 一条 48px 同时承载品牌、一级分区 Tab、全局搜索、动作图标与窗口控件。
/// Windows 把窗口按钮放右端，macOS 把系统交通灯留在左端并让出 84px；除此之外
/// 两套完全一致，所以这里只有一个 widget，不是两个。
///
/// **整条顶栏铺一层拖拽区，所有控件以「打洞」方式覆盖在上层。** 这样新增一个
/// 动作图标不需要重算拖拽区 —— 控件自己带 `HitTestBehavior.opaque` 的手势，
/// 命中就不会落到下面的拖拽层；控件之间的缝隙自动仍然可拖。
class AppTitleBar extends StatelessWidget {
  final AppSection section;
  final ValueChanged<AppSection> onSection;
  final int runningTasks;

  final FocusNode searchFocus;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final String searchShortcut;

  final VoidCallback onHistory;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  /// 历史按钮上的角标：最近一条操作可撤销且用户尚未打开过浮层。
  final bool historyHasNews;

  /// 浮层打开中 —— 按钮保持强调色底，与其他动作按钮区分。
  final bool historyOpen;

  /// 无历史：灰度 + 50% 不透明。
  final bool historyEmpty;

  const AppTitleBar({
    super.key,
    required this.section,
    required this.onSection,
    required this.runningTasks,
    required this.searchFocus,
    required this.searchController,
    required this.onSearch,
    required this.searchShortcut,
    required this.onHistory,
    required this.onRefresh,
    required this.onSettings,
    this.historyHasNews = false,
    this.historyOpen = false,
    this.historyEmpty = false,
  });

  static bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = AppLocalizations.of(context)!;
    final window = WindowStateScope.of(context);
    final focused = window.isFocused;

    // 最大化贴屏后背后不再有桌面壁纸可透，玻璃底不透明度 0.58 → 0.72。
    final fill = !focused
        ? t.topBarFillUnfocused
        : window.isMaximized && !t.reduceEffects
        ? Color.alphaBlend(t.topBarFill, t.windowBase).withValues(alpha: 0.94)
        : t.topBarFill;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppSizes.breakpointCompact;
        return GlassSurface(
          fill: fill,
          blur: t.blurTopBar,
          saturate: true,
          // 顶栏没有投影，只用 1px 底边（2.2）。
          border: Border(
            bottom: BorderSide(
              color: focused
                  ? t.stroke
                  : t.stroke.withValues(alpha: t.stroke.a * 0.6),
            ),
          ),
          child: SizedBox(
            height: AppSizes.topBar,
            child: Stack(
              children: [
                // 底层：整条可拖拽。双击 = 最大化 / 还原，右键 = 系统窗口菜单。
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
                    if (_isMac)
                      // 交通灯由系统绘制；全屏时它随菜单栏隐藏，预留 84 → 12，
                      // 240ms 缓动回收。
                      AnimatedContainer(
                        duration: AppMotion.respecting(
                          context,
                          const Duration(milliseconds: 240),
                        ),
                        curve: AppMotion.panelCurve,
                        width: window.isFullScreen
                            ? AppSizes.topBarLeftInset
                            : AppSizes.macTrafficLightInset,
                      )
                    else
                      const SizedBox(width: AppSizes.topBarLeftInset),
                    Opacity(
                      opacity: focused ? 1 : AppTokens.unfocusedOpacity,
                      child: _Brand(showName: !compact),
                    ),
                    const AppVerticalDivider(),
                    Opacity(
                      opacity: focused ? 1 : AppTokens.unfocusedOpacity,
                      child: _Tabs(
                        section: section,
                        onSection: onSection,
                        runningTasks: runningTasks,
                        focused: focused,
                      ),
                    ),
                    // 搜索区是唯一的 flex 项：200–460 之间吸收所有剩余宽度。
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.searchMargin,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppSizes.searchMax,
                            ),
                            child: Opacity(
                              opacity: focused ? 1 : AppTokens.unfocusedOpacity,
                              child: AppTextField(
                                controller: searchController,
                                focusNode: searchFocus,
                                onChanged: onSearch,
                                icon: Icons.search_rounded,
                                // 压到 200 后先丢快捷键提示，再丢占位长句。
                                hint: compact
                                    ? l10n.searchHintShort
                                    : l10n.searchHint,
                                shortcut: compact ? null : searchShortcut,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: focused ? 1 : AppTokens.unfocusedOpacity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIconButton(
                            icon: Icons.history_rounded,
                            tooltip: l10n.historyTitle,
                            onPressed: onHistory,
                            active: historyOpen,
                            dimmed: historyEmpty || !focused,
                            badgeDot: historyHasNews && !historyOpen
                                ? t.success
                                : null,
                          ),
                          const SizedBox(width: AppSizes.actionGap),
                          AppIconButton(
                            icon: Icons.refresh_rounded,
                            tooltip: l10n.refresh,
                            onPressed: onRefresh,
                          ),
                          const SizedBox(width: AppSizes.actionGap),
                          AppIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: l10n.settings,
                            onPressed: onSettings,
                          ),
                        ],
                      ),
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
      },
    );
  }
}

/// Logo 26 · r7 品牌渐变 + 产品名 12.5 / 600。
///
/// 产品名在 < 1180 时**隐去，不做省略号** —— 半截产品名比没有产品名更糟。
class _Brand extends StatelessWidget {
  final bool showName;
  const _Brand({required this.showName});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSizes.logo,
          height: AppSizes.logo,
          decoration: BoxDecoration(
            gradient: t.brandGradient,
            borderRadius: BorderRadius.circular(7),
            boxShadow: t.reduceEffects
                ? null
                : [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'J',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(width: AppSizes.logoGap),
          Text(
            l10n.appBrand,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: AppTypeScale.controlStrong.copyWith(color: t.textBody),
          ),
        ],
      ],
    );
  }
}

/// Tab 区永不压缩、永不省略 —— 中文 ≈ 248，英文 ≈ 262，都在 1024 下放得进。
class _Tabs extends StatelessWidget {
  final AppSection section;
  final ValueChanged<AppSection> onSection;
  final int runningTasks;
  final bool focused;

  const _Tabs({
    required this.section,
    required this.onSection,
    required this.runningTasks,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Tab(
          icon: Icons.folder_rounded,
          label: l10n.tabFiles,
          selected: section == AppSection.files,
          focused: focused,
          onTap: () => onSection(AppSection.files),
        ),
        const SizedBox(width: AppSizes.tabGap),
        _Tab(
          icon: Icons.video_library_rounded,
          label: l10n.tabLibrary,
          selected: section == AppSection.library,
          focused: focused,
          onTap: () => onSection(AppSection.library),
        ),
        const SizedBox(width: AppSizes.tabGap),
        _Tab(
          icon: Icons.bolt_rounded,
          label: l10n.tabTasks,
          selected: section == AppSection.tasks,
          focused: focused,
          badge: runningTasks,
          onTap: () => onSection(AppSection.tasks),
        ),
      ],
    );
  }
}

class _Tab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool focused;
  final int badge;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.focused,
    required this.onTap,
    this.badge = 0,
  });

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // 失焦时激活 Tab 的强调色底换成中性白 5%：失焦的窗口不该继续争夺注意力。
    final Color fill;
    final Color? border;
    if (widget.selected) {
      if (widget.focused) {
        fill = t.tabActiveFill;
        border = t.tabActiveStroke;
      } else {
        fill = t.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : AppPalette.ink.withValues(alpha: 0.05);
        border = null;
      }
    } else {
      fill = _hover ? t.controlFill : Colors.transparent;
      border = null;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 控件上的双击与右键不冒泡到拖拽层。
        onDoubleTap: () {},
        onSecondaryTap: () {},
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.respecting(context, AppMotion.hover),
          curve: AppMotion.standard,
          height: AppSizes.control,
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.tabPaddingH),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.button),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.selected
                    ? t.textTitle
                    : t.textSecondary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: AppTypeScale.control.copyWith(
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: widget.selected ? t.textTitle : t.textSecondary,
                ),
              ),
              if (widget.badge > 0) ...[
                const SizedBox(width: 7),
                AppCountBadge(widget.badge, dimmed: !widget.focused),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
