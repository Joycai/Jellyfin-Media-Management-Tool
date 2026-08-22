# 007 — 文件行悬停勾选框的瞬现/瞬隐

- **Status**: DONE(2026-08-22 执行并通过审查;手感验证待用户运行确认)
- **Commit**: 64756c8
- **Severity**: LOW
- **Category**: 物理感(纯淡入淡出,无位移)
- **Estimated scope**: 1 个文件,约 12 行

## 问题

[lib/widgets/file_browser/media_table.dart:648](../lib/widgets/file_browser/media_table.dart) 文件行悬停时勾选框瞬间出现、移出瞬间消失(`child: null` 与 `Checkbox` 互换),扫过列表时勾选框在行间生硬地弹进弹出。

```dart
// lib/widgets/file_browser/media_table.dart:648 — 现状
SizedBox(
  width: MediaColumnLayout.gutter,
  child: showCheckbox
      ? Checkbox(
          value: widget.checked,
          onChanged: (_) => widget.onCheck(),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        )
      : null,
),
```

## 目标

悬停是高频交互,只允许**纯透明度**、100ms 的淡入淡出——不加位移、不加缩放。`Checkbox` 常驻构建,用 `AnimatedOpacity` 控制可见性,并用 `IgnorePointer` 保证隐藏时不可点击(否则不可见的勾选框仍会吃掉 gutter 区域的点击):

```dart
// 目标
SizedBox(
  width: MediaColumnLayout.gutter,
  child: AnimatedOpacity(
    opacity: showCheckbox ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 100),
    curve: Curves.ease,
    child: IgnorePointer(
      ignoring: !showCheckbox,
      child: Checkbox(
        value: widget.checked,
        onChanged: (_) => widget.onCheck(),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    ),
  ),
),
```

`showCheckbox` 的定义(`_hovered || widget.checked`,同文件第 595 行)不变:已勾选的行勾选框常显,该逻辑由 opacity 表达式自然继承。

## 需要遵循的仓库惯例

- 同文件 `_FileRowState` 的注释风格是解释"为什么"(见 `_handleTap` 的双击说明);如需注释,只解释 `IgnorePointer` 的存在理由。
- 与审计基准一致:悬停类动效透明度-only,≤100ms。

## 步骤

1. 编辑 [lib/widgets/file_browser/media_table.dart](../lib/widgets/file_browser/media_table.dart) 第 648–660 行:按目标代码替换,`Checkbox` 的四个参数原样保留。

## 边界

- 不动 `showCheckbox` 的计算与 `_hovered` 的维护。
- 不动行高亮(选中渐变/描边)——瞬时反馈是审定过的正确行为。
- 不给动画加位移或缩放。
- 不新增依赖。

## 验证

- **机械验证**:`flutter analyze --fatal-infos`、`dart format --set-exit-if-changed lib/widgets/file_browser/media_table.dart`、`flutter test` 全绿。
- **手感验证**:`flutter run -d windows`:
  - 鼠标快速扫过文件列表,勾选框应柔和浮现/隐去,无弹跳感;
  - 未悬停的行,点击 gutter 空白处不得切换勾选状态(IgnorePointer 生效);
  - 勾选一行后移开鼠标,该行勾选框保持常显;
  - 快速进出同一行,动画从当前透明度重定向,不闪烁。
- **完成标准**:四个手感检查符合。
