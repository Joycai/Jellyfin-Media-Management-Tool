# GIGA（www.giga-web.jp）站点分析、Cookie 方案与已验证配方

> 配套文档：[scrape-module-spec.md](scrape-module-spec.md)
> 样本：`https://www.giga-web.jp/product/index.php?product_id=7743`（Chrome「另存为网页」，796 KB）
> 分析日期：2026-08-07。本文所有结论都在样本上跑通过，末尾附完整 NFO 产出。

---

## 1. 「服务端渲染 vs JS 渲染」是什么意思

这是决定"能不能用 Dart 的 `http` 抓"的分水岭。

**服务端渲染（SSR）** —— 服务器在自己那边把数据填进 HTML 模板，发给你的**已经是完整页面**。
你 `curl` 一下拿到的字节里就有标题、简介、演员。

**客户端渲染（JS 渲染 / CSR）** —— 服务器只发一个空壳（`<div id="app"></div>`），
真正的数据由浏览器执行 JavaScript 后再去调接口取回来、拼进 DOM。
`curl` 拿到的是空壳，什么都没有。

为什么对我们要命：`package:http` 只是个 HTTP 客户端，它**不执行 JavaScript**。
遇到 CSR 站点只有三条路 —— 抓包找到它背后调的那个 JSON 接口直接打（最优但费事）、
塞进 webview 跑一遍（要拖几百 MB 运行时）、或者让用户从浏览器把渲染完的 HTML 粘出来（兜底）。

**一个坑要提醒你**：你给的这个附件是「另存为网页」，那是**浏览器执行完 JS 之后的 DOM 快照**，
不等于服务器原始响应。所以严格说，光看这个文件不能直接判定 SSR。
但有三条铁证指向服务端渲染：

1. URL 是 `product/index.php?product_id=7743` —— 经典 PHP 页面；
2. HTML 里有 **1731 处双制表符缩进**和 **6 个空注释残留** `<!--\n\t-->` ——
   这是 PHP 模板 `if/endif` 之间的空白被原样输出的典型痕迹，JS 拼出来的 DOM 不会长这样；
3. 全部内容都躺在静态标签里，没有任何空占位容器或 `data-*` 待填坑。

**100% 确认的一行命令**（你在本机跑一下即可）：

```bash
curl -s -H 'Cookie: old_check=yes; layout=jpn' \
     -H 'User-Agent: Mozilla/5.0' \
     'https://www.giga-web.jp/product/index.php?product_id=7743' | grep -c '作品番号'
```

输出 ≥1 → 服务端渲染，本方案全部可用。输出 0 → 落到 §3 的更高层级。

---

## 2. 页面结构分析（这决定了配方怎么写）

### 2.1 三个坏消息

| 发现 | 影响 |
|---|---|
| **无 JSON-LD**（`application/ld+json` 命中 0 个） | 阶梯 1 的一半没了 |
| **OpenGraph 是全站通用模板**：`og:title` = 站名、`og:url` = 首页、`og:image` = 站点 logo | 阶梯 1 的另一半也没了，而且**会静默产出错误数据** |
| `<title>` 同样是站名，不含作品名 | 不能用 title 做标题 |

**由此产生一条必须写进代码的规则**：`StructuredData` 提取完要做有效性判定 ——
若 `og:url` 与当前页 URL 不一致，或 `og:title == og:site_name`，则整块丢弃。
不做这一步，批量刮 100 个作品会得到 100 条一模一样的元数据，比抓不到更糟。

### 2.2 三个好消息

**① 核心信息是规规矩矩的 `dl/dt/dd` 键值表**，在 `#works_txt` 里：

```html
<li><dl><dt>作品番号</dt><dd>SPSF-43</dd></dl></li>
<li><dl><dt>出演女優</dt><dd><span class="yaku"><a href="...actor_id=4048">西元めいさ</a></span></dd></dl></li>
<li><dl><dt>監督</dt><dd><a href="...supervisor_id=26">坂田徹</a></dd></dl></li>
<li><dl><dt>収録時間</dt><dd>本編85分　メイキング5分</dd></dl></li>
<li><dl><dt>DVDリリース日</dt><dd>2026/08/14</dd></dl></li>
```

这比"每个字段一个 CSS 选择器"稳健得多。**配方应该改成"抽出全部 dt/dd 键值对，
再做日文标签 → NFO 字段的映射"** —— 站点改版时 class 名会变，但"作品番号"这四个字不会变。
顺带 LLM 的活也变轻了：它只需要做标签映射，不需要猜选择器。

**② ID 语义清晰**：`#works_pic`（封面）、`#works_txt`（信息表）、`#story_list1/2`（简介）、
`#eye_list1/2`（监督评论）、`#tag`（标签）、`#review_header`（评分）。

**③ 页面本身信息很全**：标题、番号、简介、监督评论、演员、监督、时长、发行日、
11 个类型标签、1 个角色标签、31 张样张、平均分 3.50 —— 足够填满一份体面的 NFO。

### 2.3 四个必须在测试里锁住的坑

1. **`id="works_txt"` 出现两次，且是嵌套的**（外层 div 里套着同 id 的 div）。
   无效 HTML 但真实存在。`querySelector('#works_txt')` 返回外层，
   所以后代选择器 `#works_txt dl` 仍能覆盖内层全部条目 —— 能用，但要写测试钉死这个行为。
2. **`id="tag"` 出现两次**（ジャンルタグ / キャラクタータグ）。
   必须用 `querySelectorAll` 按 `#tag_header` 的文字分流，用 `querySelector` 只会拿到类型标签、丢掉角色标签。
3. **简介有折叠/展开两份**：`#story_list1` 是截断版（107 字，结尾带 `…`），
   `#story_list2` 才是全文（227 字）；监督评论同理，`#eye_list1` 107 字 vs `#eye_list2` 1227 字。
   **必须优先取 `_list2`。** 这条特别值得警惕 —— 如果让 LLM 自己学选择器，
   它很可能只看到 `display:block` 的那个（折叠版）就学走了，学出来的配方"能跑但内容是截断的"。
   **这就是为什么配方学完必须让人过一眼，而不是自动写进缓存就完事。**
4. **全角空格**：`本編85分　メイキング5分` 中间是 U+3000，正则用 `\s` 匹配不到，要显式处理。

---

## 3. Cookie 方案：五级阶梯

先把你的 cookies.txt 逐条解读：

| Cookie | 值 | 作用 | 我们需要吗 |
|---|---|---|---|
| `old_check` | `yes` | **年龄门通过标记** | ✅ 关键 |
| `layout` | `jpn` | 界面语言（日文） | ✅ 建议带，保证标签是日文，配方才对得上 |
| `PHPSESSID` | `rscija2o…` | PHP 会话 | ⚠️ 可能不需要，见下 |
| `WSLB` | `www2` | 负载均衡粘性 | ❌ 不需要 |
| `giga_footstamp` | `7743` | "最近浏览"记录 | ❌ 不需要 |
| `_ga` / `_ga_*` | … | Google Analytics | ❌ 不需要 |

注意 `old_check` 的过期时间字段是 `0` —— **会话 cookie**，也就是说它就是个"这次浏览已确认成年"的
静态标记，**不绑定账号、不会过期、不需要登录**。这是最理想的情况。

### 阶梯设计

```
① 配方内置静态 Cookie      recipe.cookies = "old_check=yes; layout=jpn"
   ↓ 仍被拦（例如站点校验 PHPSESSID）
② 自动预热 + 内存 CookieJar  先 GET 一次首页收 Set-Cookie，合并后再请求目标页
   ↓ 仍被拦（年龄门是个表单/确认页）
③ 年龄门自动识别            检测响应是否为门页，自动跟一次链接或 POST 表单，再重试
   ↓ 仍被拦（需要登录态 / 复杂风控）
④ 导入 cookies.txt          ← 你说的兜底，就是附件 2 这个格式
   ↓ 站点是 JS 渲染 / 强风控
⑤ 粘贴整页 HTML             永不彻底失败
```

**对 GIGA 的判断：① 大概率就够了**，用 §1 那条 curl 命令就能验证。

### ① 静态 Cookie

配方里加一个字段就完事，零成本：

```json
{ "domain": "www.giga-web.jp", "cookies": "old_check=yes; layout=jpn" }
```

### ② 自动预热（P1 做）

`package:http` 没有 cookie jar。**这一层建议直接用 `dart:io` 的 `HttpClient`** ——
它原生就有 `HttpClientRequest.cookies` / `HttpClientResponse.cookies`，
比在 `package:http` 上手搓 `Set-Cookie` 解析干净得多。约 40 行：

```dart
class CookieJar {
  final _byDomain = <String, Map<String, String>>{};   // 只放内存，不落盘

  void absorb(Uri uri, List<Cookie> setCookies) { … }
  String headerFor(Uri uri) => _byDomain[uri.host]?.entries
      .map((e) => '${e.key}=${e.value}').join('; ') ?? '';

  /// 首次访问某域名时先打一次首页，把会话 cookie 收进来。
  Future<void> warmUp(Uri origin) async { … }
}
```

**刻意不落盘**：会话 ID 等同于登录凭证，写进配置文件是净风险，而预热成本只有一次请求。

### ③ 年龄门自动识别（P2 做）

判定：响应 200 但必填字段（标题/番号）全部解析为空，且页面文本命中
`18歳|成人|同意|はい|Enter|I am over` 之类关键词，且页面很小（< 20 KB）。
命中后把这个小页面丢给 LLM 问一句"进入的链接或表单是哪个"，成本几百 token。
拿到后跟一次跳转 / POST 一次，再重试原 URL。

### ④ 导入 cookies.txt（建议和 ① 一起进 P0，因为它便宜）

Netscape 格式极简，7 个 tab 分隔字段：

```
domain   includeSubdomains   path   secure   expiry   name   value
```

解析约 20 行：`#` 开头跳过（但 `#HttpOnly_` 前缀要剥掉后当正常行处理）、
按 `\t` split、`expiry` 为 0 视作会话 cookie、按 `domain`/`path` 匹配请求 URL。

UI：设置 → 抓取 → "导入 Cookie 文件"，选 cookies.txt，按域名存起来。

**安全要求（重要）**：cookies.txt 里的 `PHPSESSID` 等同于一个登录态。
必须和 `ai_profiles.json` 同等对待 —— 存进独立文件、绝不进日志、UI 里默认打码显示、
提供一键清除。同时在 UI 上说明：**导入的会话 cookie 会随浏览器登出而失效，需要重新导入**，
所以它是兜底而非主路。

### ⑤ 粘贴 HTML

`ScrapeUrlDialog` 里的折叠区，粘进来直接进解析管线。你这次给我的附件走的就是这条路 ——
而它确实一次就跑通了，说明这条兜底是可靠的。

---

## 4. 验证过的站点配方

```json
{
  "domain": "www.giga-web.jp",
  "pathPattern": "/product/index.php*",
  "schemaVersion": 1,
  "encoding": "utf-8",
  "cookies": "old_check=yes; layout=jpn",
  "headers": { "Accept-Language": "ja,en;q=0.8" },
  "minIntervalMs": 800,
  "skipStructuredData": true,

  "fields": {
    "title":    { "selector": "#works_pic h5", "attr": "text" },
    "plot":     { "selector": "#story_list2 li.story_window, #story_list1 li.story_window",
                  "attr": "text", "first": true, "strip": ["span"] },
    "review":   { "selector": "#eye_list2 li.story_window, #eye_list1 li.story_window",
                  "attr": "text", "first": true, "strip": ["span"] },
    "rating":   { "selector": "#review_header b", "attr": "text", "transform": "double" },
    "poster":   { "selector": "#works_pic img", "attr": "src", "resolve": true },
    "extraFanart": { "selector": "div.gasatsu a[href]", "attr": "href",
                     "multiple": true, "resolve": true }
  },

  "keyValue": {
    "container": "#works_txt dl",
    "key": "dt", "value": "dd",
    "labelMap": {
      "作品番号":   { "field": "code" },
      "出演女優":   { "field": "actors",  "multiple": true, "from": "a" },
      "監督":       { "field": "director" },
      "収録時間":   { "field": "runtimeMinutes", "transform": "regex:本編\\s*(\\d+)\\s*分" },
      "DVDリリース日": { "field": "premiered", "transform": "date:yyyy/MM/dd" },
      "販売形態":   { "field": "tags", "multiple": true, "from": "a" }
    }
  },

  "tagGroups": {
    "container": "#tag", "all": true,
    "header": "#tag_header", "items": "#tag_main a",
    "route": { "ジャンル": "genres", "キャラクター": "tags" }
  },

  "constants": { "studio": "GIGA" },
  "derive": { "series": "regex:^([A-Za-z]+) from code" }
}
```

配方里几处刻意的设计：

- `skipStructuredData: true` —— 显式关掉阶梯 1，因为 §2.1 已证明本站 og 会给出错误数据。
  这个开关比"运行时判定"更明确，判定逻辑仍然保留给未知站点。
- `plot` 的选择器写成逗号分隔的**优先级列表**配 `first: true`，一条规则同时表达"优先展开版、回退折叠版"。
- `strip: ["span"]` 去掉 `▲閉じる` 那个折叠链接。
- `resolve: true` —— 图片 URL 一律 `Uri.parse(pageUrl).resolve(src)`。
  **注意**：你给的附件里图片路径被"另存为"改写成了本地文件名，那是保存动作的产物；
  真实抓取时 `src` 是服务器的真实相对路径，`resolve` 出来就是正确的绝对 URL，不需要硬编码任何路径规律。
- `tagGroups.all: true` —— 对应 §2.3 的重复 id 坑，强制走 `querySelectorAll`。

---

## 5. 端到端验证结果

用上面的配方在样本上跑，**14 个字段全部命中，0 失败**：

| 字段 | 提取值 |
|---|---|
| title | 美少女戦士セーラーディオーレ 絶望の餌食 |
| code | SPSF-43 |
| plot | 227 字全文（正确取到展开版，非 107 字截断版） |
| directorComment | 1227 字全文 |
| actors | 西元めいさ |
| director | 坂田徹 |
| runtimeMinutes | 85（从 `本編85分　メイキング5分` 解析） |
| premiered | 2026-08-14（从 `2026/08/14` 归一化） |
| rating | 3.50 |
| genres | 11 个（ピンヒールブーツ / ツインテール / 十字架磔 / セーラー服 / …） |
| tags | セーラーヒロイン + 販売形態 2 项 |
| series | SPSF（由番号前缀派生） |
| poster | 1 张 |
| extraFanart | 31 张样张 |

生成的 NFO（简介已截断显示，完整文件另附 `SPSF-43.nfo`）：

```xml
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <title>SPSF-43 美少女戦士セーラーディオーレ 絶望の餌食</title>
  <originaltitle>美少女戦士セーラーディオーレ 絶望の餌食</originaltitle>
  <sorttitle>SPSF-43</sorttitle>
  <plot>セーラーディオーレは豪然たる妖魔との戦いに追い詰められていた。……[BAD END]</plot>
  <premiered>2026-08-14</premiered>
  <year>2026</year>
  <runtime>85</runtime>
  <rating>3.5</rating>
  <studio>GIGA</studio>
  <set><name>SPSF</name></set>
  <director>坂田徹</director>
  <genre>ピンヒールブーツ</genre>
  <genre>ツインテール</genre>
  <!-- … 共 11 个 genre … -->
  <tag>セーラーヒロイン</tag>
  <tag>【月額見放題】先行メイキング映像</tag>
  <tag>HD版対応</tag>
  <actor>
    <name>西元めいさ</name>
    <type>Actor</type>
  </actor>
  <uniqueid type="giga" default="true">SPSF-43</uniqueid>
  <art>
    <poster>poster.jpg</poster>
    <fanart>fanart.jpg</fanart>
  </art>
  <!-- scraped from https://www.giga-web.jp/product/index.php?product_id=7743 -->
</movie>
```

对应的落盘布局：

```
SPSF-43 美少女戦士セーラーディオーレ 絶望の餌食 (2026)/
├── SPSF-43 ….mp4
├── SPSF-43 ….nfo          （或 movie.nfo）
├── poster.jpg              ← 封面 pac_s.jpg
├── fanart.jpg              ← 取样张第 1 张
└── extrafanart/
    ├── backdrop-1.jpg … backdrop-31.jpg
```

几个可以讨论的取舍：

- `<title>` 加番号前缀是为了 Jellyfin 列表里能按番号排序、也便于和文件名对应；
  不想要的话可以只放作品名，`<sorttitle>` 留番号即可。
- **监督评论（1227 字）没有放进 `<plot>`**，因为它是宣传文案不是剧情。
  建议要么丢弃，要么放 `<outline>` 或作为独立字段在预览里让你决定。
- `<set>` 用番号前缀 `SPSF` 派生，这样同系列会在 Jellyfin 里自动归成合集。
- 31 张样张全下会占地方，预览里应该默认只勾选前几张。

---

## 6. 这次验证对主设计的三点修正

1. **阶梯 1（结构化数据）必须带有效性判定**，否则会静默产出批量错误数据 —— 已写回主文档 §12。
2. **配方的核心不是"每字段一个 CSS 选择器"，而是"键值表 + 标签映射"**。
   建议把 `keyValue` 做成配方的一等公民（很多同类站点都是 `dl/dt/dd` 或 `table/th/td` 结构），
   LLM 的任务从"猜选择器"降级为"做标签映射"，稳定性和 token 成本都更好。
3. **LLM 学出来的配方必须人工过一眼再入库**。折叠/展开双份简介这个坑证明了
   "能跑通"不等于"抓对了" —— 自动校验只能发现"空值"，发现不了"截断值"。
   建议首次学习后在预览里高亮显示 `llm` 来源的字段，用户确认后才写进 `scrapers.json`。
