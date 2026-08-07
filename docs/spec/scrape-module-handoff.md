# 刮削模块 — 剩余实施计划（交接给 Claude Code）

> 交接日期：2026-08-07
> 背景文档：[scrape-module-spec.md](scrape-module-spec.md)（总体设计）、[scrape-giga-recipe.md](scrape-giga-recipe.md)（GIGA 站点分析与已验证配方）
> 架构摘要已写进仓库根目录 `CLAUDE.md` 的 **Metadata scraping** 一节 —— 先读那一节再动手。

---

## 0. 当前状态

P0 纯逻辑层已全部落盘并提交到仓库。**但这批代码从未编译过** —— 上一轮的执行环境访问不到 pub.dev 和 Flutter SDK。

已用另一种方式做过实质验证：把 `builtin_recipes.dart` 里的配方 JSON 原样抠出来，在 Python 里按 `RecipeApplier` 的逻辑逐行复刻，跑真实 fixture，**14 个字段全部命中、0 失败**。所以*配方数据和算法设计*是验过的，待确认的是 **Dart 转写本身**。

### 已存在的文件

```
lib/models/
  media_metadata.dart          MediaMetadata / MetadataField / MetadataActor / FieldOrigin
  scrape_recipe.dart           ScrapeRecipe / FieldRule / KeyValueRule / LabelRule / TagGroupRule / DeriveRule
lib/services/scrape/
  scrape_transform.dart        transform 小语言（text/int/double/date/regex/regexInt）
  recipe_applier.dart          纯函数：Document + Recipe + pageUrl -> MediaMetadata
  builtin_recipes.dart         内置 GIGA 配方（JSON 常量）
  structured_data.dart         JSON-LD / OpenGraph + isSiteWideTemplate 校验
  cookie_store.dart            Netscape cookies.txt 解析 + Cookie 头合成（纯内存）
  html_decoding.dart           编码探测与解码（含未知编码降级标记）
  page_fetcher.dart            唯一对外发请求处：UA / Cookie / Referer / 超时 / 每域名限流
  image_downloader.dart        图片下载 + 按魔数定扩展名 + ImageSelection
  recipe_store.dart            scrapers.json 持久化 + 配方选择/健康计数（ChangeNotifier）
  scrape_service.dart          编排（ChangeNotifier）：scrapeUrl / scrapeHtml / commit
lib/services/metadata/
  nfo_writer.dart              MediaMetadata -> NFO XML，保留未托管元素
  nfo_reader.dart              NFO XML -> MediaMetadata（origin = existingNfo）
  nfo_merge.dart               字段级 keep/replace/merge 计划 + 三个预设
  metadata_writer.dart         第二个写盘 chokepoint（PathSafety + 真备份）
test/fixtures/giga_product_7743.html    真实（裁剪过的）markup
test/services/scrape/*.dart             6 个测试文件
test/services/metadata/*.dart           3 个测试文件
```

新依赖已加进 `pubspec.yaml`：`html: ^0.15.6`、`xml: ^6.6.1`。

### 尚未做

- UI 全部（对话框、预览、入口）
- `main.dart` 未注册 `ScrapeService` / `RecipeStore`
- l10n 一个 key 都没加
- 阶梯 3（LLM 学配方）
- undo manifest 扩展
- 批量刮削 / Library 分区

---

## 1. 第一步：验证闸门（在写任何新代码之前）

```bash
flutter pub get
dart format .                       # 必须跑，CI 用 --set-exit-if-changed
flutter analyze --fatal-infos
flutter test
```

`dart format .` 会改动上一轮提交的文件，这是预期的 —— 手写代码不可能天然符合 formatter。

### 预判的失败点与修法

按可能性排序。**如果实际报错不在这几条里，先读报错再改，不要照着下面猜。**

| # | 症状 | 原因与修法 |
|---|---|---|
| 1 | `recipe_applier.dart` / `structured_data.dart` 报 `Element.text` 类型错误 | `package:html` 的 `Node.text` 声明为 `String?`，但 `Element` 可能覆写成非空 `String`。代码里已用 `final String? text = el.text; return text ?? '';` 这种写法两边兼容。若报 `dead_null_aware_expression`（analyze 的 info，`--fatal-infos` 会挂），把该处改成直接 `return el.text;` 并调整返回类型。集中在 `RecipeApplier._textOf` 和 `StructuredData.inspect` 里读 `script.text` 的地方。 |
| 2 | `csslib` 对某个选择器报错或行为不同 | 所有 `querySelector(All)` 调用都包在 `_queryAll` / `_queryFirst` 的 try/catch 里，理论上不会抛。若 `recipe_applier_test.dart` 里 “an unparseable selector is ignored” 失败，说明 csslib 是静默返回而非抛异常 —— 那测试断言仍应通过；真失败了就看它到底返回了什么。 |
| 3 | `xml` 版本解不出来 | 必须是 `^6.6.1`。`msix` 已传递引入 6.6.1，写 `^7` 会像 `intl: ^0.20.3` 一样失败。 |
| 4 | `XmlBuilder.declaration` / `XmlNode.copy()` / `XmlElement.getElement` 签名不符 | 对照 `xml` 6.6.1 的 API 调整 `nfo_writer.dart` / `nfo_reader.dart`。语义不要改。 |
| 5 | `Uri.resolve` 对含空格的引用抛 `FormatException` | `RecipeApplier.resolveUrl` 已 catch 并原样返回。`recipe_applier_test.dart` 里的断言是宽松的（`endsWith('pac_s.jpg')`），故意不依赖 Dart 的编码行为。 |
| 6 | `http.Response.bytes(..., request: ...)` 命名参数不存在 | 改测试里的 MockClient 构造即可；`ScrapeService` 有 `response.request?.url ?? url` 的回退，不影响生产代码。 |
| 7 | switch 语句 case 未终止 | 代码里已刻意避免带空 body 的 case。若仍报，改成 if/else。 |

**闸门通过的标准：`flutter analyze --fatal-infos` 零输出，`flutter test` 全绿。** 在此之前不要开始 Phase B —— 在没有编译反馈的基础上叠 UI 会让排错面积翻倍。

通过之后建议单独提交一次（`fix: make scrape core compile & pass tests`），把“转写修正”和“新功能”分开。

---

## 2. Phase B1 — 注册服务

**文件**：`lib/main.dart`

```dart
final recipeStore = RecipeStore();
unawaited(recipeStore.init());          // 尽力而为；未 init 时 forUrl 回退到内置配方

// providers 列表里追加：
ChangeNotifierProvider.value(value: recipeStore),
ChangeNotifierProvider(create: (_) => ScrapeService(recipes: recipeStore)),
```

### 注意

- **不要放在 `AiProfilesService.init()` 之前**。CLAUDE.md 里那条 init 顺序不变量（AiProfiles 必须先于 Settings）不能破坏；`RecipeStore` 与它们无关，放在 `HistoryService` 之后最安全。
- `RecipeStore.init()` 可以 `unawaited` —— 它只影响“学来的配方”，未加载时 `forUrl` 会回退到 `BuiltinRecipes`，UI 不会卡。
- `ScrapeService` 必须拿到同一个 `recipeStore` 实例，否则设置页改了配方、刮削那边看不到。
- `ScrapeService.dispose()` 会关掉它的 `http.Client`，交给 Provider 管即可。

### 服务数量

CLAUDE.md 里写的是 “Seven `ChangeNotifier`s”，加完变成九个 —— **记得同步改那句话和那张表**，否则文档立刻过期。

---

## 3. Phase B2 — 入口

### 3.1 右键菜单

**文件**：`lib/widgets/file_browser/file_context_menu.dart`

在 `enum _MenuAction` 里加 `scrape`，菜单项插在 `preview` 之后、`rename` 之前：

```dart
if (_canScrape(entry))
  _item(_MenuAction.scrape, Icons.travel_explore_outlined, l10n.menuScrapeMetadata),
```

`_canScrape` 的判定：视频文件，或者目录。判定视频用现成的 `FileLabelService.getLabel(p.extension(path))`，不要新写一套扩展名表。

选中多项时**先只支持单项**（对焦点行生效），批量放 Phase E。

### 3.2 快捷键

**文件**：`lib/shortcuts/app_shortcuts.dart`

`AppShortcutId` 加 `scrape`，在 `appShortcuts()` 的 `files` 分组里加一条。建议 `cmd(LogicalKeyboardKey.keyM)`（M = metadata；Ctrl+S 已被系统语义占用，Ctrl+I 容易和斜体冲突）。**先确认它和现有条目不冲突** —— `test/shortcuts/app_shortcuts_test.dart` 里已有重复检测，跑一次就知道。

`describe:` 指向新的 l10n key。`skipWhileTyping: true`。

**文件**：`lib/screens/home_screen.dart` 的 `_shortcutHandlers()` 里绑上 `AppShortcutId.scrape: _scrape`。

### 3.3 `_scrape()`

放在 `home_screen.dart` 里，紧挨着 `_organize()`，结构照抄它：

```dart
Future<void> _scrape() async {
  if (!_onFiles) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final browser = context.read<FileBrowserService>();
  final scraper = context.read<ScrapeService>();
  // 焦点行 -> 目标视频；没有焦点行就用当前目录
  ...
  final input = await showScrapeUrlDialog(context, suggestedKeyword: code);
  if (input == null) return;
  // 走 TaskService（见 Phase B5），完成后弹 ScrapePreviewDialog
}
```

`_organize()` 里 `mounted` 检查、`messenger` 提前取出（避免 async gap 后用 context）的写法照搬 —— 那是 `use_build_context_synchronously` 的既有解法。

---

## 4. Phase B3 — `ScrapeUrlDialog`

**新文件**：`lib/widgets/scrape/scrape_url_dialog.dart`

```dart
class ScrapeInput {
  final String url;
  /// 非空时走 ScrapeService.scrapeHtml（阶梯 4，粘贴兜底）
  final String? pastedHtml;
}

Future<ScrapeInput?> showScrapeUrlDialog(
  BuildContext context, {
  String? suggestedKeyword,   // 从文件名认出的番号
});
```

内容：

1. URL 输入框。若 `suggestedKeyword` 非空，上方显示一行“检测到番号 SPSF-43”，并给几个按钮用 `SettingsService.searchSites` 的模板去搜（`url.replaceAll('{keyword}', kw)`，`url_launcher` 打开）。**复用现有的搜索站点机制，不要新建一份站点表。**
2. 一个默认折叠的 “直接粘贴页面 HTML” 区域（`ExpansionTile` + 多行 `TextField`）。展开时 URL 框仍必填 —— `scrapeHtml` 需要它解析相对链接，这在代码里是硬要求，UI 要提示清楚（错误文案见 l10n 表）。
3. 底部一行小字说明 Cookie 状态：若 `recipes.forUrl(uri)` 命中且带 `cookies`，显示“该站点已内置访问 Cookie”；否则显示“未配置 Cookie，若抓取失败可在设置里导入 cookies.txt”。

URL 合法性只做 `Uri.tryParse` + `hasScheme` 的即时校验，真正的失败让 `ScrapeService` 抛。

---

## 5. Phase B4 — `ScrapePreviewDialog`（重头戏）

**新文件**：`lib/widgets/scrape/scrape_preview_dialog.dart`

```dart
class ScrapeCommitDecision {
  final MediaMetadata metadata;    // 用户改完的最终值
  final ImageSelection images;
  final bool backup;               // 是否记录 undo 清单并备份原 NFO
  final String nfoFileName;
  final String targetDir;
}

Future<ScrapeCommitDecision?> showScrapePreviewDialog(
  BuildContext context, {
  required ScrapeResult result,
  required String defaultTargetDir,
  required String defaultNfoFileName,
});
```

### 布局

对标 `lib/widgets/ai/organize_preview_dialog.dart`（同样是“可编辑的 diff + 确认/取消”），尺寸和玻璃质感照它来。

**顶部**：来源 URL、命中的配方名、`ScrapeNote` 警告条（每个 note 一行，带图标）。

**主区 · 字段表**，每行四列：

| 字段名 | 现有值（灰） | 抓取值（带来源徽章） | 决策 |
|---|---|---|---|

- 行来自 `result.mergePlan.decisions.keys`，顺序按 `MetadataField.all`。**`decisions` 里没有的字段说明两边一致，不显示** —— 这是设计好的降噪，别改成显示全部。
- 决策列：非列表字段是 `保留 / 覆盖` 两态（`SegmentedButton`），列表字段多一个 `合并`。
- 来源徽章读 `metadata.origins[field]`，`FieldOrigin.llm` 用警示色 —— 用户需要一眼看出哪些值是猜的。
- 文本字段支持就地编辑：点开一个小编辑框，改完 `metadata.set(field, value, FieldOrigin.manual)`。**所有编辑只改内存里的 `MediaMetadata`**，落盘只有 `ScrapeService.commit` 一个出口，和 `OrganizeAction.target` 的处理方式一致。
- `plot` / `outline` 可能上千字，用固定高度 + 内部滚动，别让对话框被一个字段撑爆。

**顶部工具条**：三个预设按钮，直接调 `plan.withPreset(...)`：

- 只补空缺（`MergePreset.fillEmptyOnly`）—— 有现存 NFO 时的默认
- 全部覆盖（`replaceAll`）
- 全部保留（`keepAll`）

**图片区**：网格，每张缩略图带勾选框、尺寸、用途标签（封面 / 背景 / 样张 N）。

- 默认勾选：封面 + 背景 + 前 5 张样张（即 `ImageSelection` 的默认值，别在 UI 里另写一套默认）。
- 缩略图需要真的下载才能显示。**建议先只显示 URL 和用途，不预加载** —— 一个页面 31 张样张，为了预览把它们全下一遍违背了限流的初衷。若要显示，只预加载封面一张。
- 输出 `ImageSelection(poster:, fanart:, extraFanart: {选中的下标})`。

**底部**：目标目录（可改，默认 `defaultTargetDir`）、NFO 文件名（默认 `MetadataWriter.nfoNameForVideo(videoFileName)`）、“记录撤销信息”勾选框（默认勾上）、取消 / 写入。

### 硬性要求

- 取消 = 一个字节都没落盘。这是整个模块唯一的 gate，和 organize 的 preview 同性质。
- 每个用户可见字符串都走 `AppLocalizations`，两个 ARB 文件同时加。
- 玻璃值读 `Theme.of(context).extension<GlassTheme>()!`，禁止硬编码颜色。

---

## 6. Phase B5 — 接入 Tasks

**文件**：`lib/services/task_service.dart`

`TaskKind` 加 `scrape`。加一个方法，结构照抄 `startAnalyze`：

```dart
OrganizerTask startScrape({
  required ScrapeService scraper,
  required String url,
  String? targetDir,
  String? nfoFileName,
  required void Function(ScrapeResult) onDone,
});
```

要点：

- 复用 `AiCancelToken`。`PageFetcher.fetch` 已经支持它，取消靠关闭 token 自己的 `http.Client`，会抛 `AiCancelled` —— catch 分支照抄 `startAnalyze` 里对 `AiCancelled` 的处理（算 stopped 不算 failed）。
- `summary` 写成类似 `'SPSF-43 · 14 字段 · 31 图'`。
- `onDone` 回调里弹预览对话框。**注意**：任务是 fire-and-forget，回调触发时用户可能已经切走了页面 —— 参考 `_organize()` 里那个带 “前往任务” action 的 SnackBar 模式，别强弹对话框。

写入阶段（`ScrapeService.commit` + 图片下载）也应该是一个 task，因为它有网络 IO 和进度。可以复用 `TaskKind.scrape` 或加 `TaskKind.scrapeCommit`，`ImageProgress` 回调喂进度。

---

## 7. Phase B6 — l10n

`lib/l10n/app_en.arb` 和 `lib/l10n/app_zh.arb` **必须同时加**，然后 `flutter gen-l10n`（或直接 `flutter run`）。生成的 `app_localizations*.dart` 不要手改。

预估 60–90 个 key。清单（按用途分组，命名沿用现有风格）：

**入口 / 菜单**
`menuScrapeMetadata`, `shortcutScrape`

**URL 对话框**
`scrapeUrlTitle`, `scrapeUrlHint`, `scrapeUrlInvalid`, `scrapeDetectedCode`, `scrapeSearchOnSite`, `scrapePasteHtml`, `scrapePasteHtmlHint`, `scrapePasteNeedsUrl`, `scrapeCookieBuiltIn`, `scrapeCookieMissing`, `scrapeStart`

**进度 / 提示**
`scrapeStarted`, `scrapeFailed`, `scrapeCancelled`, `scrapeNoteSiteWideIgnored`, `scrapeNoteNoRecipe`, `scrapeNoteDegradedEncoding`, `scrapeNoteRecipeStale`

**预览对话框**
`scrapePreviewTitle`, `scrapeSource`, `scrapeRecipeName`, `scrapeColumnField`, `scrapeColumnExisting`, `scrapeColumnScraped`, `scrapeColumnDecision`,
`scrapeDecisionKeep`, `scrapeDecisionReplace`, `scrapeDecisionMerge`,
`scrapePresetFillEmpty`, `scrapePresetReplaceAll`, `scrapePresetKeepAll`,
`scrapeOriginStructured`, `scrapeOriginRecipe`, `scrapeOriginLlm`, `scrapeOriginExisting`, `scrapeOriginManual`, `scrapeOriginDerived`,
`scrapeNoChanges`, `scrapeWriteBackup`, `scrapeTargetFolder`, `scrapeNfoFileName`, `scrapeWrite`

**字段名**（19 个，对应 `MetadataField.all`）
`fieldTitle`, `fieldOriginalTitle`, `fieldSortTitle`, `fieldCode`, `fieldPlot`, `fieldOutline`, `fieldTagline`, `fieldPremiered`, `fieldRuntime`, `fieldStudio`, `fieldSeries`, `fieldDirector`, `fieldRating`, `fieldGenres`, `fieldTags`, `fieldActors`, `fieldPoster`, `fieldFanart`, `fieldExtraFanart`

**图片区**
`scrapeImages`, `scrapeImagePoster`, `scrapeImageFanart`, `scrapeImageExtra`, `scrapeImageCount`

**结果**
`scrapeWriteSucceeded`, `scrapeWritePartial`, `scrapeWriteFailed`

**设置页**
`settingsScraping`, `settingsScrapeCookies`, `settingsScrapeImportCookies`, `settingsScrapeClearCookies`, `settingsScrapeCookieCount`, `settingsScrapeCookieWarning`, `settingsScrapeRecipes`, `settingsScrapeRecipeBuiltin`, `settingsScrapeRecipeLearned`, `settingsScrapeRecipeRetired`, `settingsScrapeRecipeDelete`

建议写一个 `String scrapeFieldLabel(AppLocalizations l10n, String field)` 的映射函数放在 `lib/widgets/scrape/` 下，别在 UI 里散落 19 个 switch。

---

## 8. Phase B7 — 设置页

**文件**：`lib/widgets/settings/settings_screen.dart`，新增一个「刮削」分区。

### Cookie 管理

- “导入 cookies.txt” 按钮 → `file_picker` 选文件 → `CookieStore.parseNetscape` → 存进 `ScrapeService.fetcher.cookies`。
- 按域名列出已导入的 Cookie 数量，提供“清除该域名 / 全部清除”。
- **值必须默认打码**，只显示 name 和域名。
- 一行醒目提示：导入的 Cookie 可能包含等同登录态的会话凭证，且会随浏览器登出失效、需要重新导入。

### 持久化的安全要求

`CookieStore` 目前**是纯内存的，故意的**。如果这一步要做持久化：

- 单独存 `cookies.json`，**不要**混进 `config.json`（理由和 `ai_profiles.json` 分开存一模一样：一次滑块拖动不应该重写凭证文件）；
- 绝不写进 `debugPrint` 或任何日志；
- 给一个明确的“记住 Cookie”开关，默认关。

### 配方列表

只读展示 `RecipeStore.all`：域名、路径模式、来源（内置 / 学习 / 手编）、成功/失败计数、是否已退休。学习/手编的可删除，内置的不可删。

---

## 9. Phase C — undo 扩展

**文件**：`lib/services/history_service.dart`

现有 manifest 只记录移动。刮削会**新建**文件、并可能**覆盖**已有 NFO，需要新的 op 类型：

```jsonc
{
  "type": "scrape",
  "baseDir": "...",
  "created": ["<abs path>", ...],           // 撤销 = 删除
  "restored": { "<abs path>": "<backup>" }  // 撤销 = 从备份拷回
}
```

`MetadataWriteResult` 已经把这两组数据准备好了：`createdPaths` 和 `restorablePaths`，直接落进 manifest 即可。

备份目录约定 `<appSupport>/undo/blobs/<opId>/`，`ScrapeService.commit` 的 `backupDir` 参数传它。

### 必须写清楚的一件事

CLAUDE.md 里有一句 **“`backup` does not copy anything”**，那是描述 organize 流程的。刮削这条线里 `backup` **真的复制文件**（覆盖 NFO 不可能靠“移回去”还原）。这个语义分叉已经写进 `metadata_writer.dart` 的文件头注释和 CLAUDE.md 的新章节，改动这块时不要把它抹掉 —— 下一个人一定会被那句老话误导。

`refresh()` 的 7 天清理要连带删掉 `blobs/<opId>/` 目录，否则备份会无限堆积。

---

## 10. Phase D — 阶梯 3：LLM 学配方

只有遇到没有内置配方的站点时才需要。

**新文件**：`lib/services/scrape/html_cleaner.dart`、`scrape_prompt.dart`、`recipe_learner.dart`

### HtmlCleaner

把页面压成“骨架”再喂模型：

- 删 `script` / `style` / `svg` / `noscript` / 注释；
- 属性白名单只留 `id` / `class` / `itemprop` / `href` / `src`；
- 文本节点截断到 80 字符；
- 连续空白折叠。

实测能把 200 KB 压到 20–30 KB。再叠一层“只保留正文主区域”的启发式，通常能落到 8k–15k token。

### ScrapePrompt

对标 `lib/services/ai/ai_prompt.dart`：静态纯函数、无 Provider 依赖、可单测。

让模型输出的是**选择器和标签映射**，不是内容 —— 直接照抄 `builtin_recipes.dart` 里 GIGA 配方的 JSON 结构作为 few-shot 示例。

### RecipeLearner

流程：

1. 调 `AiProvider.complete`（复用现有 provider，不要新写 HTTP）；
2. 解析成 `ScrapeRecipe`；
3. **立刻本地自检**：用 `RecipeApplier` 在同一份 HTML 上跑一遍，必填字段（title、code 或 poster）为空则带着失败反馈重试一次；
4. 两次都失败 → 降级到阶梯 4（提示用户粘贴 HTML）。

### 一条不能省的规则

**学出来的配方必须人工过一眼再入库，不能自动写进 `scrapers.json`。**

理由在 `scrape-giga-recipe.md` §2.3：GIGA 的简介有折叠版（101 字，截断）和展开版（223 字，全文）两份，模型很可能只看到 `display:block` 的折叠版就学走了。学出来的配方**能跑、不空、看起来完全正常，但内容是截断的** —— 自动校验只能发现空值，发现不了截断值。

具体做法：学完先进预览，把 `FieldOrigin.llm` 的字段高亮，用户确认后才 `RecipeStore.save`。

---

## 11. Phase E — 规模化

按价值排序，都不阻塞前面的：

1. **批量刮削** —— 整个文件夹逐个匹配。注意 `PageFetcher` 的每域名限流是串行队列，300 个标题会真的排队跑，这是设计意图，进度 UI 要如实反映而不是假装并行。
2. **Library 分区** —— `home_screen.dart` 里目前是占位符。刮削结果的浏览、重刮理所当然长在这里。
3. **配方导入/导出** —— `ScrapeRecipe.toJson` 已经能 round-trip（有测试）。
4. **和 organize 流水线打通** —— 把刮到的 `title` / `year` 作为 `titleHint` / `mediaTypeHint` 注入 `AiPrompt.buildUserPrompt`，提高重命名准确率。这是两条流水线唯一应该有的耦合点，而且是单向的（刮削 → organize），不要反过来。

---

## 12. 已有 API 速查

写 UI 时对着这张表即可，不必重读全部实现。

### `ScrapeService`

```dart
Future<ScrapeResult> scrapeUrl(String url, {
  String? targetDir, String? nfoFileName, AiCancelToken? cancelToken});

Future<ScrapeResult> scrapeHtml(String rawHtml, {
  required String sourceUrl, String? targetDir, String? nfoFileName});

Future<MetadataWriteResult> commit({
  required MediaMetadata metadata,
  required Uri pageUrl,
  required String targetDir,
  required String nfoFileName,
  ScrapeRecipe? recipe,
  ImageSelection images = const ImageSelection(),
  String? backupDir,
  NfoKind kind = NfoKind.movie,
  AiCancelToken? cancelToken,
  ImageProgress? onImageProgress,   // void Function(int done, int total)
});

bool get isScraping;
```

### `ScrapeResult`

```dart
MediaMetadata scraped;       // 页面抓到的
MediaMetadata? existing;     // 磁盘上已有 NFO 读回的，可能为 null
NfoMergePlan mergePlan;      // 默认决策
Uri pageUrl;                 // 重定向后的最终 URL；图片下载的 Referer
ScrapeRecipe? recipe;
List<ScrapeNote> notes;      // 警告
MediaMetadata get merged;    // 按当前 plan 算出的最终值
```

### `NfoMergePlan`

```dart
Map<String, MergeDecision> decisions;   // 只含两边不同的字段
Set<String> newFields;                  // 抓到了、磁盘上没有
Set<String> conflictFields;             // 两边都有且不同
MergeDecision decisionFor(String field);
NfoMergePlan withDecision(String field, MergeDecision d);   // 不可变，返回新实例
NfoMergePlan withPreset(MergePreset p);
```

`MergeDecision`：`keep` / `replace` / `merge`（merge 仅列表字段）
`MergePreset`：`fillEmptyOnly` / `replaceAll` / `keepAll`

### `MediaMetadata`

```dart
Object? get(String field);                                  // 用 MetadataField.xxx 取
void set(String field, Object? value, FieldOrigin origin);  // 强制转换失败则丢弃，不覆盖旧值
bool isBlank(String field);
Map<String, FieldOrigin> origins;
MediaMetadata copy();
int? get year;                                              // 从 premiered 推
```

`MetadataField.all`（19 个 key，预览行的显示顺序）、`MetadataField.listFields`（可 merge 的四个）。

### `ImageSelection`

```dart
const ImageSelection({bool poster = true, bool fanart = true, Set<int>? extraFanart});
static const posterOnly;
Set<int> resolveExtra(int available);   // extraFanart 为 null 时取前 5
```

### `MetadataWriteResult`

```dart
int succeeded, failed;
bool hasFailures;
Map<String, String> failures;           // 路径 -> 错误
List<String> createdPaths;              // 撤销要删的
Map<String, String> restorablePaths;    // 路径 -> 备份路径
```

### `PageFetcher` / `CookieStore`

```dart
PageFetcher({http.Client? client, CookieStore? cookieStore, int? minIntervalMs});
CookieStore cookies;                    // 公开，设置页直接操作

static List<NetscapeCookie> CookieStore.parseNetscape(String text);
static String CookieStore.toNetscape(List<NetscapeCookie> cookies);
void importAll(List<NetscapeCookie>);   // 按域名替换，不是追加
void clearDomain(String domain);
void clear();
```

---

## 13. 不能破坏的红线

1. **`applyOrganizeAction` 和 `MetadataWriter` 是仅有的两个写盘口。** 新代码要写磁盘，走它们，或者在注释里说清为什么不走。
2. **每个目标路径都要过 `PathSafety.isWithin(baseDir, target, context: fs.path)`。** `context:` 不能省，否则注入的 POSIX 内存文件系统会被按 Windows 规则解析。
3. **不要把刮削结果塞进 `OrganizePlan`。** 全应用只有一个 plan，第二次 `analyzeFolder` 会立刻置空 —— 误触一次 Organize 就会吃掉用户还没确认的元数据。
4. **预览取消 = 零字节落盘。**
5. **所有用户可见字符串走 `AppLocalizations`，`app_en.arb` 和 `app_zh.arb` 同时加。**
6. **新快捷键只写在 `lib/shortcuts/app_shortcuts.dart`**，不要在 widget 里裸写 `SingleActivator`。
7. **批量操作汇报计数，不是第一个错误。** `MetadataWriteResult` 已经按这个形状返回了。
8. **路径拼接一律走 `path` 包**，禁止字符串相加。
9. **不引入 codegen**（`freezed` / `json_serializable` / `build_runner`）。JSON 手写。
10. **`RecipeApplier` / `NfoWriter` / `NfoReader` / `NfoMerge` / `StructuredData` / `ScrapeTransform` / `CookieStore` / `HtmlDecoding` 保持纯函数、无 Provider 依赖。** 这是整个模块能离线单测的原因，别为了图方便往里塞 `BuildContext` 或 `getApplicationSupportDirectory()`。
11. **CI 三件套本地先跑**：`dart format --set-exit-if-changed`、`flutter analyze --fatal-infos`、`flutter test`。一个 lint info 就能挂掉构建。

---

## 14. 验收清单

- [ ] `flutter pub get` / `dart format .` / `flutter analyze --fatal-infos` / `flutter test` 全过
- [ ] `ScrapeService` + `RecipeStore` 在 `main.dart` 注册，且共用同一个 `RecipeStore` 实例
- [ ] CLAUDE.md 里 “Seven ChangeNotifiers” 那句和那张表已更新
- [ ] 右键菜单和快捷键都能打开 URL 对话框
- [ ] 对一个真实 GIGA 作品页跑通：URL → 预览 → 写入，`SPSF-43.nfo` + `poster.jpg` 正确落盘
- [ ] Jellyfin 扫描该文件夹，标题、简介、演员、封面、类型标签全部正确显示
- [ ] 对同一个作品再刮一次：字段级 diff 正确显示，`playcount` 之类的未托管元素没被洗掉
- [ ] 预览里点取消，磁盘上一个字节都没变
- [ ] 断网状态下点刮削，报错友好，不崩
- [ ] 粘贴 HTML 的兜底路径能跑通（用 `test/fixtures/giga_product_7743.html` 的内容试）
- [ ] 新字符串在中英两个 ARB 里都有，切换语言无 `null`
- [ ] 任务可取消，取消后状态是 stopped 不是 failed
