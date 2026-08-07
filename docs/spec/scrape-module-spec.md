# 网页元数据抓取（刮削）模块 — 可行性评估与架构设计

> 状态：设计稿（未写代码）
> 目标：给定一个作品页 URL，抓取标题 / 简介 / 演员 / 番号 / 发行日 / 封面 / 缩略图等信息，
> 在应用内预览并允许人工修改，确认后生成 Jellyfin NFO 并把图片落盘；
> 若目标位置已有 NFO，支持按字段选择覆盖。

---

## 0. 结论先行

**可行，且和现有架构契合度很高。** 不需要引入 headless 浏览器、不需要 codegen、不需要动
organize 流水线。核心新增只有两个纯 Dart 依赖（`html` 解析、`xml` 生成）。

但有四个必须先解决的现实障碍，全部有成熟解法，不构成阻断：

| 障碍 | 影响 | 解法 |
|---|---|---|
| 成人站点的年龄门（entrance 页 / Cookie 拦截） | 直接 GET 拿到的是同意页而非作品页 | 按站点配置固定 Cookie + `User-Agent`，跟随重定向 |
| 日文站点非 UTF-8 编码（Shift_JIS / EUC-JP） | `http` 包默认按 latin1 解码 → 全是乱码 | 用 `bodyBytes` + 探测 `<meta charset>` 后解码 |
| 图片防盗链（校验 `Referer`） | 图片下载 403 | 下载时带上作品页 URL 作为 `Referer` |
| 纯 LLM 嗅探每页几万 token | 慢且贵，批量刮削不可用 | **结构化数据优先 + 选择器缓存**（见 §4） |

工作量估算：**最小可用（P0）约 3–4 人天，完整形态约 8–12 人天。** 分阶段计划见 §11。

有一个前提我无法自行验证：你给的是页面标题而不是真实 URL，我也没有实际抓取该站点。
下面的设计是**站点无关**的，但 §12 列了三条需要你用真实页面确认的假设。

---

## 1. 这个模块在现有架构里的位置

现在的应用是一个**纯改名器**：AI 看文件名 → 出 `OrganizePlan` → 预览 → `applyOrganizeAction`
搬文件。所有信息都来自文件名本身，天花板很低。

刮削模块是一条**平行的新流水线**，唯一交汇点是复用 `AiProvider`：

```
现有：  文件夹 ──► AiService.analyzeFolder ──► OrganizePlan ──► 预览 ──► ApplyController ──► 移动文件
                          │
                          └── 共用 AiProvider / AiHttp / AiCancelToken
                          │
新增：  URL ──► ScrapeService.scrape ──► MediaMetadata ──► 预览+合并 ──► MetadataWriter ──► 写 NFO/图片
```

关键设计决策：**两条流水线不耦合**。刮削不改 `OrganizePlan`、不改 `applyOrganizeAction`。
理由是 CLAUDE.md 里那条不变量 —— "全应用只存在一个 plan，第二次 analyze 会直接把当前 plan 置空"。
如果把刮削结果塞进 `OrganizePlan`，一次误触的 analyze 就会吃掉用户刚抓好还没确认的元数据。

复用点则很干净：`AiProvider.complete()` 已经是"(system, user) → 文本"的纯抽象，
provider 层刻意不含任何领域知识，刮削直接拿来用即可，无需改动。

---

## 2. 分层与文件清单

```
lib/models/
  media_metadata.dart        // 抓取结果 + 每字段来源标记（jsonld/selector/llm/manual）
  scrape_recipe.dart         // 一个站点的选择器"配方"
  nfo_merge_plan.dart        // 字段级 保留/覆盖/合并 决策
lib/services/scrape/
  scrape_service.dart        // ChangeNotifier，编排整条链路（唯一注册进 Provider 的）
  page_fetcher.dart          // HTTP：编码探测 / Cookie / Referer / UA / 每域名限流
  html_cleaner.dart          // DOM 瘦身：去 script/style/svg/注释，属性白名单
  structured_data.dart       // JSON-LD / OpenGraph / microdata 提取（零 token 通道）
  recipe_store.dart          // scrapers.json 读写（对标 SettingsService 的手写 JSON）
  recipe_learner.dart        // 调 LLM 推断选择器
  recipe_applier.dart        // 用选择器本地解析，纯函数、易测
  scrape_prompt.dart         // prompt 定义，静态纯函数（对标 AiPrompt）
  image_downloader.dart      // 并发下载 + 尺寸/类型校验
lib/services/metadata/
  nfo_reader.dart            // 读已有 NFO → MediaMetadata
  nfo_writer.dart            // MediaMetadata → Kodi/Jellyfin NFO XML
  metadata_writer.dart       // ★ 唯一写盘口，PathSafety 守门 + 生成 undo 清单
lib/widgets/scrape/
  scrape_url_dialog.dart     // 输入 URL / 粘贴 HTML
  scrape_preview_dialog.dart // 三列 diff + 图片勾选 + 落盘目标
test/services/scrape/        // 用离线 HTML fixture，不打真实网络
test/services/metadata/      // 用内存 FileSystem（沿用 organize_service_test 的做法）
```

按仓库既有约定：`ScrapeService` 是 `ChangeNotifier` 并注册进 `main.dart`；
`RecipeApplier` / `NfoWriter` / `StructuredData` / `ScrapePrompt` 保持纯函数无 Provider 依赖；
JSON 全部手写，不引入 `freezed`/`json_serializable`。

---

## 3. 数据模型

```dart
/// 一个字段的值 + 它从哪来（决定预览里的来源徽章和默认是否勾选覆盖）
enum FieldOrigin { jsonLd, openGraph, selector, llm, existingNfo, manual }

class MediaMetadata {
  String? title;          // <title>
  String? originalTitle;  // <originaltitle>  原始日文标题
  String? sortTitle;
  String? code;           // 番号 → 写入 <uniqueid type="custom">
  String? plot;           // <plot>  简介
  String? tagline;
  String? premiered;      // ISO yyyy-MM-dd → <premiered>
  int? runtimeMinutes;    // <runtime>
  String? studio;         // <studio>  厂牌
  String? series;         // <set> 或 <tag>
  String? director;
  List<String> genres;    // 多个 <genre>
  List<String> tags;      // 多个 <tag>
  List<Actor> actors;     // 多个 <actor>（name / role / thumb）
  double? rating;

  String? posterUrl;      // 竖版封面 → poster.jpg
  String? fanartUrl;      // 横版宣传图 → fanart.jpg
  List<String> extraFanartUrls; // 缩略图组 → extrafanart/backdrop-N.jpg
  String? trailerUrl;

  String? sourceUrl;      // 抓取来源，写进 NFO 注释便于追溯
  Map<String, FieldOrigin> origins; // 字段名 → 来源
}
```

`origins` 是让预览界面有说服力的关键：用户能一眼看出"这条简介是 JSON-LD 里原样拿的"
还是"这是 LLM 猜的"，从而决定信不信。LLM 来源的字段在预览里默认**不勾选覆盖**已有值。

---

## 4. 抓取策略：四级阶梯（这是省钱与稳定的核心）

你选的"LLM 学选择器 + 本地缓存"是对的。我在它前面再加一级更便宜的通道：

```
                      ┌─────────────────────────────────────┐
  URL ──► PageFetcher │ 1. 结构化数据  JSON-LD / og: / micro │  零 token，命中率意外地高
          （编码/Cookie/│    ↓ 缺字段                          │
            Referer）  │ 2. 缓存的选择器配方 scrapers.json    │  零 token
                      │    ↓ 未命中或解析为空                 │
                      │ 3. LLM 学选择器 ──► 校验 ──► 写缓存   │  每域名一次，几千 token
                      │    ↓ 仍失败（JS 渲染 / 强反爬）        │
                      │ 4. 用户从浏览器粘贴 HTML → 回到第 1 级 │  兜底，永不彻底失败
                      └─────────────────────────────────────┘
```

**为什么第 1 级值得单独做**：绝大多数商品/作品页为了 SEO 都带 `og:title` / `og:image` /
`og:description`，不少还带 `application/ld+json`。这一级几十行代码，能在很多站点上直接拿到
标题、封面、简介三个最重要的字段，完全不花 token。

**第 3 级怎么学**：不要把原始 HTML 丢给模型。先经 `HtmlCleaner` 做"骨架化"——
去掉 `script`/`style`/`svg`/`noscript`/注释，属性只保留 `id`/`class`/`itemprop`/`href`/`src`，
文本节点截断到 80 字符，连续空白折叠。实测这类处理能把 200 KB 的页面压到 20–30 KB，
再配合"只保留正文主区域"的启发式，通常能落到 8k–15k token，一次学习成本可以接受。

模型返回的是**选择器**，不是内容：

```json
{
  "domain": "example.com",
  "pathPattern": "/product/*",
  "fields": {
    "title":   { "selector": "h1.product-title", "attr": "text" },
    "plot":    { "selector": "div#description",  "attr": "text" },
    "actors":  { "selector": "ul.cast li a",     "attr": "text", "multiple": true },
    "poster":  { "selector": "img.package",      "attr": "src" },
    "extraFanart": { "selector": ".sample-list img", "attr": "src", "multiple": true },
    "premiered": { "selector": "dd.release-date", "attr": "text",
                   "transform": "date:yyyy年MM月dd日" }
  },
  "confidence": 0.9
}
```

**学完立刻自检**：拿返回的选择器在同一份 HTML 上跑一遍 `RecipeApplier`，
把实际抽到的值回灌给模型让它确认；必填字段（title/poster）为空则带着失败反馈重试一次，
两次都失败才降级到第 4 级。这一步是"自愈"的关键，也避免把坏配方写进缓存。

**配方失效检测**：每次本地解析后统计命中率，写回 `successCount` / `failCount`。
连续 2 次必填字段解析为空 → 自动作废该配方并触发重学（站点改版的典型表现）。

`scrapers.json` 存在 `path_provider` 的 application-support 目录，和 `sites.json` 平级，
由 `RecipeStore` 独占读写 —— 沿用仓库"每个关注点写自己的文件"的做法。

---

## 5. PageFetcher：脏活集中在这里

这一层是整个模块最容易低估的地方，四个坑：

```dart
// 1) 编码：日文站可能是 Shift_JIS / EUC-JP，http 包无 charset 时按 latin1 解码 → 乱码
final res = await client.get(uri, headers: headers);
final charset = detectCharset(res.headers['content-type'], res.bodyBytes); // 再看 <meta charset>
final html = decodeWith(charset, res.bodyBytes);

// 2) 年龄门 / 会话 Cookie：五级方案见 scrape-giga-recipe.md §3
headers['Cookie'] = cookieJar.headerFor(uri);       // GIGA 实测：'old_check=yes; layout=jpn'
headers['User-Agent'] = kDesktopUserAgent;          // 默认 UA 会被部分站点拒绝
headers['Accept-Language'] = 'ja,en;q=0.8';

// 3) 图片防盗链：下载图片时必须带作品页作为 Referer
imageHeaders['Referer'] = pageUrl;

// 4) 限流：同一域名串行 + 最小间隔，避免被封
await _domainThrottle.acquire(uri.host, minInterval: Duration(milliseconds: 800));
```

UTF-8 之外的解码 Dart 标准库不带，需要 `charset`（纯 Dart，含 Shift_JIS / EUC-JP / GBK / ISO-8859 系列）。
注意常被推荐的 `enough_convert` **不含日文编码**，别选错。
**如果目标站点确认是 UTF-8，这个依赖可以不加** —— 见 §12 待确认项。

取消复用现有的 `AiCancelToken` 机制：CLAUDE.md 里那条"取消靠关闭 token 自己的 `http.Client`
实现，所以可取消的请求不能用共享的 `AiHttp.client`"同样适用于抓取，别踩。

---

## 6. NFO 读写与字段级覆盖（你明确要的那块）

Jellyfin 的 NFO 命名规则（已核对官方文档）：

| 类型 | 文件名 |
|---|---|
| 电影 | `movie.nfo` 或 `<视频文件同名>.nfo` |
| 剧集系列 | `tvshow.nfo` |
| 季 | `season.nfo` |
| 单集 | `<视频文件同名>.nfo` |

单文件作品用 `<视频同名>.nfo` 最稳（一个文件夹放多个作品时不会打架）。

**合并流程**是三方对照，不是简单覆盖：

```
已有 NFO（NfoReader）  ─┐
                       ├─► NfoMergePlan ─► 预览对话框（每字段一个决策）─► 最终 MediaMetadata
抓取结果（MediaMetadata）─┘
```

预览对话框每一行三列：**当前值 | 抓取值 | 采用哪个**。决策有三态：

- `keep` —— 保留现有（已有值且抓取值来源是 `llm` 时的默认）
- `replace` —— 用抓取值覆盖（字段为空、或抓取来源是 `jsonLd`/`selector` 时的默认）
- `merge` —— 仅列表字段（`genres` / `tags` / `actors`）可选，去重合并

顶部给三个快捷按钮：**全部保留 / 全部覆盖 / 只补空缺**（"只补空缺"是日常最常用的）。
文本字段可直接就地编辑，和 `OrganizePreviewDialog` 让用户改 `action.target` 的思路一致 ——
**所有修正都在内存里完成，写盘动作只有一个出口。**

`NfoWriter` 用 `XmlBuilder` 生成，注意两点：
- 保留原 NFO 里我们不认识的元素（比如别的刮削器写的自定义标签），只替换我们管的那些，
  避免"用本工具刮一次就把别人的数据洗掉"；
- 结尾按 Kodi/Jellyfin 惯例写一行来源注释（`<!-- scraped from ... -->`），方便追溯。

---

## 7. 图片落盘规范

已核对 Jellyfin 官方文档，电影文件夹内的识别名：

| 用途 | 文件名 | 来源字段 |
|---|---|---|
| 竖版海报 | `poster.jpg`（亦识别 `folder`/`cover`/`movie`） | `posterUrl` |
| 横版背景 | `fanart.jpg`（亦识别 `backdrop`/`background`/`art`） | `fanartUrl` |
| 多张背景 | `extrafanart/backdrop-1.jpg`, `-2.jpg` … | `extraFanartUrls` |
| 缩略图 | `thumb.jpg` / `landscape.jpg` | 可选 |
| 台标 | `logo.png` / `clearlogo.png` | 通常没有 |

预览里每张图给缩略图 + 尺寸 + 勾选框，用户可以只要封面不要那 20 张缩略图。
下载前先 `HEAD`（或读前几 KB）校验 Content-Type 与尺寸，拒绝 1×1 像素点和非图片响应。

---

## 8. 写盘安全与撤销

CLAUDE.md 明确要求："任何写盘代码必须走 `applyOrganizeAction`，或说明为什么不走。"

这里必须说明：**刮削是"新建文件"，不是"移动文件"，`applyOrganizeAction` 的语义
（拒绝覆盖已存在目标、跨卷 copy+delete）不适用。** 因此新增第二个写盘口
`MetadataWriter`，并承担同等义务：

- 每个目标路径都过 `PathSafety.isWithin(baseDir, ...)`，且传 `context:`（跨平台路径解析）；
- 所有路径拼接走 `path` 包，禁止字符串相加；
- 单个文件失败不中断整批，最后按 `ScaffoldMessenger` 汇报**计数**而非首个错误。

撤销这里有个和现有实现不一样的地方，需要显式决策：

> 现有 `HistoryService` 的 manifest 只记录移动，**`backup` 从不复制任何东西**（CLAUDE.md 原话，
> 它只是"要不要记 undo 清单"的开关）。

刮削会**覆盖**已有 NFO，一旦覆盖，光靠"反向移动"无法还原。所以：

- 新增 op 类型 `scrape`，manifest 记录"新建了哪些文件"（撤销 = 删除它们）；
- 被覆盖的原 NFO **必须真的复制一份**到 `undo/blobs/<opId>/`（NFO 是几 KB 的文本，成本可忽略）；
- 图片不备份（可重新下载），只记录新建路径。

这会让 `backup` 这个名字在新流程里第一次真的名副其实，注意在代码注释里写清楚这个语义分叉，
否则下一个人会被 CLAUDE.md 里那句"backup does not copy anything"误导。

---

## 9. UI 接入点

1. **入口**：文件表右键菜单加一项"刮削元数据…"（`file_context_menu.dart`），
   对选中的视频文件/文件夹生效；`app_shortcuts.dart` 里加一个快捷键条目（单一真源，别在 widget 里裸写 `SingleActivator`）。
2. **第一步 `ScrapeUrlDialog`**：粘 URL；带一个"直接粘贴页面 HTML"的折叠区（第 4 级兜底）；
   如果文件名里能认出番号，自动带出并提示"在已配置的站点里搜索"（复用 `SettingsService.searchSites` 的模板机制）。
3. **第二步进度**：走现有 `TaskService`，抓取作为一种新任务类型出现在 Tasks 页，可取消。
4. **第三步 `ScrapePreviewDialog`**：§6 的三列 diff + §7 的图片勾选 + 落盘目录选择。
5. **Library 分区**：`home_screen.dart` 里 Library 目前是占位符 —— 刮削结果的浏览/重刮理所当然应该长在那里，
   但**建议放到 P2**，先把 P0 的"右键 → 抓 → 预览 → 落盘"闭环跑通。

所有新字符串必须同时进 `app_en.arb` 和 `app_zh.arb`。这个模块字段名很多，
预估新增 60–90 个 key，是本次工作量里容易被低估的一块。

---

## 10. 依赖增量

| 包 | 版本 | 用途 | 说明 |
|---|---|---|---|
| `html` | ^0.15.6 | HTML5 解析 + `querySelector`/`querySelectorAll` | 纯 Dart，全平台，选择器方案的基础 |
| `xml` | ^7.0.1 | `XmlBuilder` 生成 NFO / 读已有 NFO | 纯 Dart，全平台 |
| `charset` | ^2.0.1，可选 | Shift_JIS / EUC-JP / GBK 解码 | 仅当目标站点非 UTF-8 时需要（§12）。**别用 `enough_convert`，它没有日文编码** |

全是纯 Dart 包，不含原生代码，不影响 macOS 的 CocoaPods 处境，也不需要动 MSIX 的
`capabilities`（`internetClient` 已经声明了）。`http` 已在依赖里。

**不需要**：headless 浏览器 / webview / puppeteer。第 4 级兜底（粘贴 HTML）用几十行代码
覆盖了 JS 渲染场景，比引入几百 MB 的浏览器运行时划算得多。

---

## 11. 分阶段落地计划

**P0 — 最小可用闭环（约 3–4 人天）**

1. `PageFetcher`（编码探测 / UA / Cookie / Referer / 限流）
2. `StructuredData`（JSON-LD + OpenGraph）
3. `MediaMetadata` 模型
4. `NfoWriter` + `ImageDownloader` + `MetadataWriter`（含 PathSafety）
5. `ScrapeUrlDialog` + 极简预览（只读 + 确认）
   → 此时对带 og 标签的站点已经能用了

**P1 — 混合抓取 + 字段级合并（约 3–4 人天）**

6. `HtmlCleaner` + `ScrapePrompt` + `RecipeLearner` + 自检重试
7. `RecipeStore` / `RecipeApplier` / 失效检测与重学
8. `NfoReader` + `NfoMergePlan` + 三列 diff 预览（**你要的覆盖选择在这里**）
9. undo manifest 扩展 + 原 NFO 备份
10. l10n 补全 + 单测（离线 fixture + 内存 FileSystem）

**P2 — 规模化（约 2–4 人天）**

11. 批量刮削（整个文件夹逐个匹配）
12. Library 分区展示与重刮
13. 配方的导入/导出与分享
14. 与 organize 流水线打通：把刮到的标题/年份作为 `titleHint` 注入 `AiPrompt`，提高重命名准确率

---

## 12. 前提验证结果（2026-08-07 已用真实页面样本确认）

样本：`https://www.giga-web.jp/product/index.php?product_id=7743`（796 KB 另存页）+ cookies.txt。
详细分析、可直接使用的站点配方和验证过的 NFO 产出见 **[scrape-giga-recipe.md](scrape-giga-recipe.md)**。

| 前提 | 结论 |
|---|---|
| 渲染方式 | **服务端渲染（PHP）**。阶梯 2–4 全部可用，不需要浏览器内核 |
| 页面编码 | **UTF-8**（`<meta http-equiv="Content-Type" ... charset=UTF-8>`）→ **`charset` 依赖可以不加** |
| 年龄门 | Cookie `old_check=yes` 标记已通过；另有 `layout=jpn` 控制语言。均为静态标记，无需登录 |
| 结构化数据 | **JSON-LD 零命中，OpenGraph 全站通用**（`og:title` 是站名、`og:url` 是首页）→ **阶梯 1 在本站失效**，直接从阶梯 2 起步 |

需要修正的设计判断（诚实记录）：**阶梯 1（结构化数据）不是万能的**。
本站的 `<title>` 和 `og:*` 全是站点级模板，拿来会得到 11 个作品共用同一个标题。
因此 `StructuredData` 提取后必须做一次**有效性判定** —— 若 `og:url` 与当前页 URL 不一致、
或 `og:title` 等于 `og:site_name`，则判定为站点级模板并整体丢弃，落到阶梯 2。
这一条不做，会静默产出一批错误元数据，比抓不到更糟。

---

## 13. 合规提示

模块本身是通用的网页元数据抓取器，用途是给**自有媒体库**补全元数据，这和
Kodi/Jellyfin 生态里既有的刮削器插件是同一类工具。设计上已经内置了几条自我约束，建议保留：

- 每域名串行 + 最小请求间隔，不做并发轰炸；
- 只抓用户显式给出的单个页面 URL，不做站点爬行；
- 抓取结果只写到用户本地媒体库，不做再分发；
- 建议在设置里放一句提示，让用户自行确认目标站点的服务条款与所在地法规。

---

## 附：整体时序

```
用户右键"刮削元数据"
   └─► ScrapeUrlDialog（URL / 粘贴 HTML）
        └─► TaskService.startScrape（可取消）
             └─► PageFetcher.fetch  ──编码/Cookie/Referer/限流
                  └─► StructuredData.extract        ← 零 token
                       └─(缺字段)─► RecipeStore.lookup(domain)
                            ├─(命中)─► RecipeApplier.apply     ← 零 token
                            └─(未命中)─► HtmlCleaner ─► RecipeLearner(LLM)
                                             └─► 自检 ─► RecipeStore.save
                  └─► MediaMetadata（带 origins 标记）
                       └─► NfoReader.read(已有 nfo)
                            └─► ScrapePreviewDialog（三列 diff + 图片勾选 + 就地编辑）
                                 └─(确认)─► MetadataWriter
                                              ├─ PathSafety.isWithin 校验
                                              ├─ 备份原 NFO → undo/blobs/
                                              ├─ 写 <video>.nfo
                                              ├─ 下载 poster/fanart/extrafanart
                                              └─ 写 undo manifest（op 类型 scrape）
```
