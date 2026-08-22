# 001 — 加快右键菜单的打开动画

- **Status**: DONE(2026-08-22 执行并通过审查;手感验证待用户运行确认)
- **Commit**: 1699a41
- **Severity**: HIGH
- **Category**: 缓动与时长(Easing & duration)/ 频率
- **Estimated scope**: 1 个文件,约 5 行

## 问题

右键菜单是本应用的核心交互(文件行右键、图片格子右键、各处排序菜单),每天被触发几十次。`showGlassMenu` 直接落到 Material 的 `showMenu`,而 Material 弹出菜单的默认动画是 **300ms** 的分段揭示(先横向再纵向展开,菜单项再逐个淡入)。300ms 对移动端可以,对桌面端高频操作来说明显拖沓——用户右键后要等菜单"长"出来。

```dart
// lib/widgets/glass/glass_menu.dart:24 — 现状
return showMenu<T>(
  context: context,
  position: RelativeRect.fromRect(
    globalPosition & Size.zero,
    Offset.zero & overlay.size,
  ),
  color: scheme.surface,
  ...
);
```

审计基准:下拉/菜单类动画应在 150–250ms 内完成,且退出应比进入更快。

## 目标

利用 `showMenu` 的 `popUpAnimationStyle` 参数(Flutter 3.19+,本项目 Flutter 3.44 可用)把动画压缩到 180ms 打开 / 120ms 关闭,曲线用强 ease-out:

```dart
// 目标
return showMenu<T>(
  context: context,
  popUpAnimationStyle: const AnimationStyle(
    duration: Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    reverseDuration: Duration(milliseconds: 120),
  ),
  position: RelativeRect.fromRect(
    globalPosition & Size.zero,
    Offset.zero & overlay.size,
  ),
  ...
);
```

## 需要遵循的仓库惯例

- `showGlassMenu` 是全应用唯一的菜单入口(CLAUDE.md:"One place to change, every menu follows")——只改这一处,所有菜单同步生效。**不要**去任何调用点单独加动画参数。
- 文件内已有的参数排列风格保持不变,新参数紧跟 `context:` 之后即可。

## 步骤

1. 编辑 [lib/widgets/glass/glass_menu.dart](../lib/widgets/glass/glass_menu.dart) 第 24 行起的 `showMenu<T>` 调用,插入上面目标代码中的 `popUpAnimationStyle:` 参数(`AnimationStyle` 来自 `package:flutter/material.dart`,该文件已导入)。

## 边界

- 不改 `glassMenuItem` / `glassMenuHeader` 的任何布局或样式。
- 不改菜单定位逻辑(`RelativeRect` 那几行)。
- 不新增依赖。
- 若 `showMenu` 的实际签名里没有 `popUpAnimationStyle`(Flutter 版本漂移),停止并报告,不要改用自定义路由。

## 验证

- **机械验证**:`flutter analyze --fatal-infos` 无新增告警;`dart format --set-exit-if-changed lib/widgets/glass/glass_menu.dart` 通过。
- **手感验证**:`flutter run -d windows`,在文件表格里右键:
  - 菜单应"弹"出来而不是"长"出来——快速起步、末尾轻收。
  - 连续快速右键不同的行,菜单不应产生残影或排队感。
  - 按 Esc 或点击空白处关闭,消失应比出现更快。
- **完成标准**:菜单从右键到完全可读 ≤ 200ms(可用慢放录屏确认),关闭 ≤ 150ms。
