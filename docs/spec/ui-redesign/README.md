# UI 重做 · 设计规范

来源：Claude Design 项目 **Jellyfin媒体库整理工具**
（`df5938aa-2555-4263-8898-81f254e1b4fd`，6 页 · 38 个画板）。

这里是把那六页画板逐条抄下来的**取值清单**，不是复述。代码里的每一个颜色、
圆角、高度、时长都应当能在这几份文档里找到出处；找不到出处的数字就是 bug。

| 文档 | 覆盖 | 代码落点 |
|---|---|---|
| [01 通用标准](01-foundations.md) | 色彩、字体与排版、间距圆角尺寸、层级投影、五类组件的全部状态、动效时长 | `lib/theme/design_tokens.dart`、`lib/widgets/ui/` |
| [02 程序外壳](02-shell.md) | 顶栏选型、Windows / macOS 两套 48px 顶栏、窗口状态、拖拽热区、性能模式、布局骨架 | `lib/widgets/shell/`、`windows/runner/flutter_window.cpp`、`macos/Runner/MainFlutterWindow.swift` |
| [03 浏览与详情](03-browse.md) | 主界面、文件列表面板、媒体库网格与详情、空状态、右键菜单 | `lib/screens/home_screen.dart`、`lib/widgets/file_browser/`、`lib/widgets/sidebar/`、`lib/widgets/ai/ai_assistant_panel.dart` |
| [04 刮削](04-scrape.md) | 配置对话框、任务执行、结果确认与图片分配 | `lib/widgets/scrape/` |
| [05 整理](05-organize.md) | 命名规则、整理预览、执行与日志、撤销与历史三形态 | `lib/widgets/ai/` |
| [06 配置](06-config.md) | AI 服务与模型参数、设置各分区、取色浮层、首次引导 | `lib/widgets/settings/`、`lib/widgets/onboarding/` |
| [Backlog](backlog.md) | 设计稿画了但能力未实现的部分、与现有行为的冲突裁决 | —— |

## 令牌层怎么用

```dart
final t = context.tokens;           // 颜色、渐变、投影、模糊 —— 随主题变
t.accent, t.textBody, t.stroke, t.elevation.card, t.blurPanel

AppSpacing.md12, AppRadii.field,    // 与主题无关，static const
AppSizes.topBar, AppMotion.hover,
AppTypeScale.body, AppTypeScale.sizeControl
```

两条规矩：

1. **widget 里不出现字面量。** 颜色、圆角、控件高度、字号、时长都从上面取。
   刻意的一次性取值（680×340 的拖放框、46×5 的置信度条）要在旁边写清楚它出自
   哪一节。
2. **强调色是用户可换的。** 凡是从它派生的东西都写成不透明度派生，不要写死色值；
   压在浅底上的文字用 `t.accentText`（会按亮度重新推导），不要直接用 `t.accent`。

模糊只有一个入口：`GlassSurface`。它带着三条实测出来的规矩（底色不透明就丢掉
滤镜、性能模式整块跳过而不是传 0、没有裁剪不开模糊），不要在别处再写
`BackdropFilter`。
