# 005 — 平滑进度条/置信度条的数值跳变

- **Status**: DONE(2026-08-22 执行并通过审查;手感验证待用户运行确认)
- **Commit**: 64756c8
- **Severity**: LOW
- **Category**: 错失的机会(Missed opportunities)/ 防止突兀变化
- **Estimated scope**: 2 个文件,各约 10 行

## 问题

两处 `LinearProgressIndicator` 的 `value` 变化时直接跳到新值:

1. **任务卡进度条** — [lib/widgets/tasks/tasks_screen.dart:255](../lib/widgets/tasks/tasks_screen.dart)。apply 任务的通知被 `ApplyController` 以 50ms 节流,进度条以可见的台阶前进而不是连续移动。

```dart
// lib/widgets/tasks/tasks_screen.dart:255 — 现状
ClipRRect(
  borderRadius: BorderRadius.circular(999),
  child: LinearProgressIndicator(
    value: task.status == TaskStatus.failed ? 0 : progress,
    minHeight: 6,
    backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
    valueColor: AlwaysStoppedAnimation(
      task.status == TaskStatus.failed ? scheme.error : accent,
    ),
  ),
),
```

2. **文件行 AI 置信度条** — [lib/widgets/file_browser/media_table.dart:835](../lib/widgets/file_browser/media_table.dart)。值在用户编辑动作/新计划落地时原地跳变。

```dart
// lib/widgets/file_browser/media_table.dart:833 — 现状
child: ClipRRect(
  borderRadius: BorderRadius.circular(4),
  child: LinearProgressIndicator(
    value: v,
    minHeight: 5,
    backgroundColor: color.withValues(alpha: 0.18),
    valueColor: AlwaysStoppedAnimation(color),
  ),
),
```

## 目标

两处都用 `TweenAnimationBuilder<double>` 包住,200ms `Curves.easeOut` 补间到新值。

**关键:`Tween` 只给 `end`,不给 `begin`。** begin 为 null 时首帧直接落在当前值、只有后续变化才补间——这正是想要的语义:

- 任务卡:打开 Tasks 页时进行中的任务直接显示当前进度,不从 0 播一遍;
- 置信度条:`ListView` 滚动回收重建行时**不得**重播动画(否则滚动时满屏条形图闪烁),只有值原地变化才动。

```dart
// 目标(tasks_screen.dart;media_table 同型,换成各自的值与样式)
ClipRRect(
  borderRadius: BorderRadius.circular(999),
  child: TweenAnimationBuilder<double>(
    tween: Tween<double>(
      end: task.status == TaskStatus.failed ? 0 : progress,
    ),
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    builder: (context, value, _) => LinearProgressIndicator(
      value: value,
      minHeight: 6,
      backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
      valueColor: AlwaysStoppedAnimation(
        task.status == TaskStatus.failed ? scheme.error : accent,
      ),
    ),
  ),
),
```

media_table 一侧:`tween: Tween<double>(end: v)`,`builder` 内 `LinearProgressIndicator(value: value, minHeight: 5, ...)` 其余参数原样;**旁边的百分比文字 `'${(v * 100).round()}%'` 保持用原始 `v`,不用动画值**——数字滚动是另一种动画,不在本计划范围。

## 需要遵循的仓库惯例

- 与已合入的动效家族一致:200ms 内、easeOut、无弹跳(参照 `showGlassMenu` 的 180ms/easeOutCubic,glass_menu.dart:26)。
- 失败态(`TaskStatus.failed` → 0 + error 色)的取值逻辑原样保留在 tween/valueColor 里,不重构。

## 步骤

1. 编辑 [lib/widgets/tasks/tasks_screen.dart](../lib/widgets/tasks/tasks_screen.dart) 第 255–265 行:按目标代码包 `TweenAnimationBuilder`。
2. 编辑 [lib/widgets/file_browser/media_table.dart](../lib/widgets/file_browser/media_table.dart) 第 833–841 行:同型包法,参数原样。

## 边界

- 不动 `ApplyController` 的 50ms 节流。
- 不动 settings_screen.dart:2093 的字体下载进度条(字节流进度,本就连续,README 未列入)。
- 不给 `Tween` 加 `begin`。
- 不新增依赖。

## 验证

- **机械验证**:`flutter analyze --fatal-infos`、`dart format --set-exit-if-changed lib`、`flutter test` 全绿。
- **手感验证**:`flutter run -d windows`:
  - 跑一次 apply(多文件),Tasks 页进度条应连续滑动而非台阶跳进;
  - 打开 Tasks 页时,进行中任务的条**不**从 0 播放;
  - 文件表格出现置信度条后快速上下滚动,条形图不得闪烁/重播。
- **完成标准**:三个手感检查全部符合。
