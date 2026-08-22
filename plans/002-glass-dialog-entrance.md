# 002 — 给玻璃对话框加统一的"缩放+淡入"入场

- **Status**: DONE(2026-08-22 执行并通过审查;18 个调用点全部替换,手感验证待用户运行确认)
- **Commit**: 1699a41
- **Severity**: HIGH
- **Category**: 物理感与原点(Physicality & origin)
- **Estimated scope**: 约 12 个文件;1 处新增 helper + 约 17 个调用点的机械替换

## 问题

这是一个"活在对话框里"的应用——预览、整理计划、刮削面板、重命名、删除确认全部是模态对话框。但所有对话框都走 Material 默认的 `showDialog`,其转场是 **150ms 纯淡入,无任何位移或缩放**。纯淡入的入场没有物理感:表面凭空浮现,和应用其余部分(液态玻璃、有深度的阴影)的质感不匹配。

调用点(全部是 `showDialog<T>(context: ..., builder: ...)` 形态):

- `lib/widgets/file_browser/file_context_menu.dart:156, 200, 257`
- `lib/widgets/ai/rename_rule_dialog.dart:21`
- `lib/widgets/ai/organize_preview_dialog.dart:45`
- `lib/widgets/ai/organize_history_screen.dart:286`
- `lib/widgets/ai/edit_action_dialog.dart:44, 104, 110, 119`
- `lib/widgets/scrape/scrape_review_pane.dart:188`
- `lib/widgets/scrape/batch_scrape_dialog.dart:31`
- `lib/widgets/scrape/scrape_panel.dart:74`(带 `barrierDismissible: false`)
- `lib/widgets/dialogs/preview_dialog.dart:31`(带自定义 `barrierColor: Colors.black.withValues(alpha: 0.72)`)
- `lib/widgets/dialogs/title_hint_dialog.dart:27`
- `lib/widgets/settings/settings_screen.dart:2013, 2032`(2032 带 `barrierDismissible: false`)
- `lib/widgets/settings/ai_services_screen.dart:407`

## 目标

在 [lib/widgets/glass/glass_dialog.dart](../lib/widgets/glass/glass_dialog.dart) 新增一个 `showGlassDialog<T>` helper,作为全应用对话框的唯一入口(与 `showGlassMenu` 对称),然后把上面所有调用点机械替换过去。

入场:220ms,`scale 0.96 → 1.0` + 淡入,强 ease-out。**不要用 `scale(0)`**——真实世界里没有东西从无到有。退场:160ms 淡出(缩放随动画反向自然回落)。

```dart
// lib/widgets/glass/glass_dialog.dart — 新增(文件顶部已 import material)
/// 全应用模态对话框的唯一入口,与 [showGlassMenu] 对称:统一入场动画
/// (fade + 0.96→1 缩放),调用点不再各自决定转场。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
```

说明:`showGeneralDialog` 无法单独设置反向时长,220ms 配合 easeOutCubic 的反向播放,视觉上退场约 150ms 即基本完成,符合"退出快于进入"。

## 需要遵循的仓库惯例

- 模仿 `showGlassMenu`(lib/widgets/glass/glass_menu.dart:13)的文档注释风格:先说"为什么集中在一处"。
- 对话框 widget 本身(`GlassAlertDialog`、各 `Dialog` 子类)一概不动——动画属于路由,不属于表面。
- CI 会跑 `dart format --set-exit-if-changed` 和 `flutter analyze --fatal-infos`,提交前先过。

## 步骤

1. 在 [lib/widgets/glass/glass_dialog.dart](../lib/widgets/glass/glass_dialog.dart) 文件末尾(`GlassDialogSurface` 类之后)加入上面的 `showGlassDialog<T>`。
2. 逐个访问"问题"一节列出的调用点,把 `showDialog<X>(...)` 替换为 `showGlassDialog<X>(...)`,规则:
   - `context:`、`builder:` 原样保留;
   - 有 `barrierDismissible: false` 的(scrape_panel.dart:74、settings_screen.dart:2032)原样传给新 helper;
   - preview_dialog.dart:31 的自定义 `barrierColor` 原样传入;
   - 其余未传参数一律不补。
3. 每个被改的文件补上 `import '../glass/glass_dialog.dart';`(按各文件相对路径调整;已导入则跳过)。若原文件因此不再使用 `showDialog`,不需要删除 material import(它还提供其他符号)。
4. 全库 `grep "showDialog<"` 确认 lib/ 下不再有直接调用(测试代码除外)。

## 边界

- **不改**任何对话框的内容布局、尺寸、按钮。
- **不改** `GlassDialogSurface` 的模糊/阴影参数。
- 不新增依赖,不引入第三方动画库。
- 若某个调用点的实际代码与上面列表不符(行号漂移属正常,形态不符才算),跳过该点并在结果中报告,不要自行发挥。

## 验证

- **机械验证**:`flutter analyze --fatal-infos` 通过;`dart format --set-exit-if-changed lib` 通过;`flutter test` 全绿。
- **手感验证**:`flutter run -d windows`:
  - 随便右键一个文件 → 删除:确认对话框应带轻微"由小及大"的浮现感,而非平面淡入;缩放幅度应小到不刻意(96% 起步几乎察觉不到,只留下"有物理感"的印象)。
  - 按 Esc 关闭:退场应干脆,无弹跳。
  - 打开视频预览对话框(双击视频):遮罩应仍是加深的 72% 黑。
  - 打开刮削面板:仍然不能点遮罩关闭。
- **完成标准**:lib/ 下无直接 `showDialog` 调用;上述四个手感检查全部符合。
