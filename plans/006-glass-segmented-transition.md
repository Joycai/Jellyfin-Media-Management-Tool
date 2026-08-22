# 006 — GlassSegmented 选中态的瞬间跳变

- **Status**: DONE(2026-08-22 执行并通过审查;手感验证待用户运行确认)
- **Commit**: 64756c8
- **Severity**: LOW
- **Category**: 缓动与时长(悬停/颜色变化类)
- **Estimated scope**: 1 个文件,约 5 行

## 问题

[lib/widgets/glass/glass_segmented.dart:43](../lib/widgets/glass/glass_segmented.dart) 的分段控件里,选中项的底色/描边是普通 `Container`,切换选项时旧格瞬灭、新格瞬亮,没有过渡。

```dart
// lib/widgets/glass/glass_segmented.dart:43 — 现状
child: Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 5,
  ),
  decoration: BoxDecoration(
    color: item.value == value
        ? scheme.primary.withValues(alpha: 0.16)
        : null,
    borderRadius: BorderRadius.circular(6),
    border: item.value == value
        ? Border.all(
            color: scheme.primary.withValues(alpha: 0.35),
          )
        : Border.all(color: Colors.transparent),
  ),
  child: Row( ... ),
),
```

## 目标

`Container` → `AnimatedContainer`,150ms `Curves.ease`(颜色变化类的标准曲线),并把未选中的 `color: null` 改为显式 `Colors.transparent`,让颜色 lerp 两端都有明确值:

```dart
// 目标
child: AnimatedContainer(
  duration: const Duration(milliseconds: 150),
  curve: Curves.ease,
  padding: const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 5,
  ),
  decoration: BoxDecoration(
    color: item.value == value
        ? scheme.primary.withValues(alpha: 0.16)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(6),
    border: item.value == value
        ? Border.all(
            color: scheme.primary.withValues(alpha: 0.35),
          )
        : Border.all(color: Colors.transparent),
  ),
  child: Row( ... ),
),
```

文字/图标颜色与字重的切换保持瞬时(它们在动画中的底色格内,150ms 内的瞬变读不出来;字重本就不宜 lerp)——这是有意为之,不是遗漏。

## 需要遵循的仓库惯例

- 该文件是玻璃家族组件,只此一处改动即覆盖所有调用方。
- 不引入滑动小丸(每格独立装饰的现有结构保持不变)——那是重做组件,不是本计划。

## 步骤

1. 编辑 [lib/widgets/glass/glass_segmented.dart](../lib/widgets/glass/glass_segmented.dart) 第 43 行起:按目标代码替换 `Container` 为 `AnimatedContainer`,`Row` 子树原样。

## 边界

- 不动外层容器、`InkWell`、`Semantics`。
- 不动文字/图标的样式切换逻辑。
- 不新增依赖。

## 验证

- **机械验证**:`flutter analyze --fatal-infos`、`dart format --set-exit-if-changed lib/widgets/glass/glass_segmented.dart`、`flutter test` 全绿。
- **手感验证**:`flutter run -d windows`,找到任一使用分段控件的界面来回切换:
  - 选中底色应淡入新格、淡出旧格,而非瞬间跳变;
  - 快速连续切换不产生残影或延迟感(AnimatedContainer 会从当前状态重定向,天然可打断)。
- **完成标准**:两个手感检查符合。
