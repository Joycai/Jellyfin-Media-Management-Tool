# 003 — 用桌面风格的页面转场取代安卓 Zoom 转场

- **Status**: DONE(2026-08-22 执行并通过审查;light/dark 共用一处 ThemeData,单处插入生效)
- **Commit**: 1699a41
- **Severity**: MEDIUM
- **Category**: 一致性(Cohesion)/ 缓动与时长
- **Estimated scope**: 1 个文件(lib/theme/app_theme.dart),约 40 行

## 问题

应用里的整页跳转(设置、整理历史、任务详情/整理进度)都用裸 `MaterialPageRoute`:

- `lib/widgets/settings/settings_screen.dart:44`
- `lib/widgets/ai/organize_progress_screen.dart:23`
- `lib/widgets/ai/organize_history_screen.dart:18`

`AppTheme`(lib/theme/app_theme.dart:157 起的 `ThemeData`)没有设置 `pageTransitionsTheme`,所以 Windows/Linux 落在 Flutter 默认的 `ZoomPageTransitionsBuilder`——安卓系统风格的放大浮入。在一个刻意做了液态玻璃、44px 输入框、桌面窗口管理的应用里,这个转场是唯一一处"手机味",与产品气质不符,而且新页面进入时旧页面还会同步缩小,桌面用户对这种双向运动很敏感。

## 目标

在 `AppTheme` 里为三个桌面平台统一注册一个"淡入 + 极轻微上浮"的转场:进入时新页面从 `Offset(0, 0.015)`(自身高度的 1.5%)上浮并淡入,曲线 `Curves.easeOutCubic`;返回时反向播放。路由时长由 `MaterialPageRoute` 固定为 300ms,配合强 ease-out,视觉上约 200ms 即完成。旧页面不做任何动画(桌面惯例:底层内容保持稳定)。

```dart
// lib/theme/app_theme.dart — 新增私有类(文件内任意合适位置,建议放在 AppTheme 类之后)
/// 桌面端页面转场:淡入 + 1.5% 上浮。默认的 ZoomPageTransitionsBuilder 是
/// 安卓系统的放大浮入,在桌面窗口里显得像手机应用;这里换成桌面惯用的
/// 快速淡入,且不动退场中的旧页面。
class _DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const _DesktopPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
```

并在 `ThemeData`(lib/theme/app_theme.dart:157)里加入:

```dart
pageTransitionsTheme: const PageTransitionsTheme(
  builders: {
    TargetPlatform.windows: _DesktopPageTransitionsBuilder(),
    TargetPlatform.linux: _DesktopPageTransitionsBuilder(),
    TargetPlatform.macOS: _DesktopPageTransitionsBuilder(),
  },
),
```

## 需要遵循的仓库惯例

- `AppTheme` 是全应用唯一的样式来源(CLAUDE.md"Control metrics live in the theme, not in widgets")——转场同理,只在主题里注册,**不要**把任何调用点改成 `PageRouteBuilder`。
- 该文件同时构建 light/dark 两套 `ThemeData`:若两套是同一个方法生成的就只加一处;若是两处 `ThemeData(...)`,两处都要加。
- macOS 平台默认是 Cupertino 滑入转场,本方案有意将其一并统一为淡入(应用自绘玻璃 UI,不依赖平台横滑手势返回)。

## 步骤

1. 在 [lib/theme/app_theme.dart](../lib/theme/app_theme.dart) 中加入 `_DesktopPageTransitionsBuilder` 类(如上)。
2. 在 `ThemeData` 构造(第 157 行起;若 light/dark 分开构造则每处)加入 `pageTransitionsTheme` 块(如上)。
3. 确认没有触碰任何 `MaterialPageRoute` 调用点。

## 边界

- 不改 settings_screen.dart / organize_progress_screen.dart / organize_history_screen.dart 的任何代码。
- 不改对话框转场(那是 002 号计划的事,两者互不依赖)。
- 不新增依赖。

## 验证

- **机械验证**:`flutter analyze --fatal-infos`、`dart format --set-exit-if-changed lib/theme/app_theme.dart`、`flutter test` 全部通过。
- **手感验证**:`flutter run -d windows`:
  - 打开设置页:新页面应轻轻淡入上浮,**底层主界面全程纹丝不动**,不再有"整体缩放"感。
  - 从设置页返回:反向淡出,同样不牵动主界面。
  - 切换到暗色主题重复一次(确认两套 ThemeData 都生效)。
- **完成标准**:任意整页跳转均无缩放运动;进入动画在肉眼约 200ms 内完成。
