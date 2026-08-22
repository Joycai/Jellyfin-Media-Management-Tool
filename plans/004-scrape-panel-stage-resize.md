# 004 — 刮削面板三阶段切换的尺寸/内容瞬移

- **Status**: DONE(2026-08-22 执行并通过审查。**实施偏离**:计划原样代码在 widget 测试中触发转场期 RenderFlex overflow,`ClipRect` 后备无法抑制布局断言;改为 `LayoutBuilder` + `OverflowBox` 让评审面板始终按最终尺寸布局、由生长的窗口揭示,静止布局与原先等价。手感验证待用户运行确认)
- **Commit**: 1699a41
- **Severity**: MEDIUM
- **Category**: 错失的机会(Missed opportunities)/ 防止突兀变化
- **Estimated scope**: 1 个文件(lib/widgets/scrape/scrape_panel.dart),约 20 行

## 问题

刮削面板有三个阶段(setup → working → review),窗口宽度分别是 700 / 580 / 1280,高度 760 / 860。阶段切换时 `ConstrainedBox` 的约束瞬间变化,对话框在一帧内从 580px 跳到 1280px——刮削完成的那一刻,窗口猛然横向爆开,内容同时整体替换,是全应用最突兀的一次布局瞬移。

```dart
// lib/widgets/scrape/scrape_panel.dart:444 — 现状
child: ConstrainedBox(
  // Setting a scrape up is a short form, running one is a card of steps,
  // and reviewing one is a table beside a picture grid. The window grows
  // to match rather than making the form sprawl or the review cramped.
  constraints: BoxConstraints(
    maxWidth: reviewing ? 1280 : (working ? 580 : 700),
    maxHeight: reviewing ? 860 : 760,
  ),
  child: GlassDialogSurface(
    child: reviewing
        ? _review()
        : Column( ... ),
  ),
),
```

## 目标

尺寸变化用 280ms `Curves.easeInOutCubic` 补间(屏上形变 → ease-in-out,审计基准 200–500ms 内),内容用 180ms 淡入淡出交换。切换时窗口平滑生长,新阶段内容在生长过程中淡入。

```dart
// 目标:ConstrainedBox → AnimatedContainer,内容套 AnimatedSwitcher
child: AnimatedContainer(
  duration: const Duration(milliseconds: 280),
  curve: Curves.easeInOutCubic,
  // Setting a scrape up is a short form, running one is a card of steps,
  // and reviewing one is a table beside a picture grid. The window grows
  // to match rather than making the form sprawl or the review cramped.
  constraints: BoxConstraints(
    maxWidth: reviewing ? 1280 : (working ? 580 : 700),
    maxHeight: reviewing ? 860 : 760,
  ),
  child: GlassDialogSurface(
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: KeyedSubtree(
        key: ValueKey(_stage),
        child: reviewing
            ? _review()
            : Column( ... 原有内容原样 ... ),
      ),
    ),
  ),
),
```

原有的解释性注释(为什么三个阶段尺寸不同)保留,挪到 `constraints:` 上方。

## 需要遵循的仓库惯例

- 该文件的注释风格是"解释为什么"而非"解释是什么"——新增动画如需注释,只写一条约束性的(例如为什么内容交换比尺寸补间快)。
- 时长/曲线与 002 号计划的对话框入场(220ms easeOutCubic)属于同一动效家族,不要引入弹跳曲线。

## 步骤

1. 编辑 [lib/widgets/scrape/scrape_panel.dart](../lib/widgets/scrape/scrape_panel.dart) 第 444–451 行:`ConstrainedBox` 改为 `AnimatedContainer`,加 `duration` 与 `curve`,`constraints` 表达式不变。
2. 把 `GlassDialogSurface` 的 `child` 包进 `AnimatedSwitcher` + `KeyedSubtree(key: ValueKey(_stage))`,内部的 `reviewing ? _review() : Column(...)` 整体原样移入。`_stage` 是本类现有字段(第 131 行),直接可用。
3. 运行并走一遍完整刮削流程,观察控制台:若阶段切换瞬间出现 RenderFlex overflow 报警(旧内容在收窄的约束里布局所致),把 `KeyedSubtree` 外再包一层 `ClipRect` 消除视觉溢出;若报警仍在但仅出现于转场帧且无视觉异常,在计划结果中如实记录。

## 边界

- 不改三个阶段各自的内部布局(`_setup` / `_working` / `_review`)。
- 不改 `showScrapePanel` 的路由参数(那属于 002)。
- 不改尺寸数值本身(700/580/1280/760/860)。
- 不新增依赖。

## 验证

- **机械验证**:`flutter analyze --fatal-infos`、`dart format --set-exit-if-changed lib/widgets/scrape/scrape_panel.dart`、`flutter test` 通过。
- **手感验证**:`flutter run -d windows`,对一个视频文件按 Ctrl+M 打开刮削面板:
  - 填入 URL 点击 Process:窗口应平滑收窄到 580,步骤卡淡入。
  - 刮削完成进入 review:窗口应在约 300ms 内平滑展开到 1280,评审内容淡入——**不再是一帧爆开**。
  - 在 review 点"返回"回 setup:反向同样平滑。
  - 全程无内容被裁切卡住的残影,无持续的 overflow 黄黑条。
- **完成标准**:三次阶段切换均无瞬移;转场期间与结束后控制台无遗留异常(转场帧的一次性 overflow 报警按步骤 3 处理)。
