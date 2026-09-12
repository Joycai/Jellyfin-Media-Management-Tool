# 03 · 浏览与详情（Browse）

来源：`03-Browse.dc.html`。

> **外壳冲突裁决**：本页画板仍画着拆分前的旧外壳（28px 系统标题栏 + 50px 应用工具条、
> 侧栏 236–240）。[02 程序外壳](02-shell.md) 是更晚的选型结论（方案 A 统一 48px 顶栏、
> 侧栏 244、右面板 352）。**外壳一律以 02 为准**，本页只取主内容区（列表面板、网格、
> 详情、空状态、右键菜单）的规格。

## 3.1 主界面（Files 分区）

### 面包屑 + 动作条

- 面包屑：mono 12px，非当前段 white 50%，分隔符 `›` white 30%，当前段 white 90% / 500。
- 右侧动作：次级按钮「视图」h30 · r8 · white 6% + 描边 8%；
  主按钮「✨ AI 整理全部」h30 · r8 · `linear-gradient(180deg, accent .95, accent .75)`
  + 描边 white 20% + `inset 0 1px 0 rgba(255,255,255,.35)` + `0 4px 12px accent 40%`。
- 面包屑与列表面板间距 18。

### 文件列表面板

外框：`flex:1` · r16 · white 5% · blur 40 saturate 180 · 描边 white 8%
· `inset 0 1px 0 rgba(255,255,255,.12), 0 12px 36px rgba(0,0,0,.25)`。

列网格：`32px 1.6fr 0.7fr 0.6fr 1fr 120px`，gap 14。

| 列 | 内容 |
|---|---|
| 32 | 类型图标 22×22 · r5（视频橙渐变 / 剧集青渐变 / 图片紫渐变 / 字幕 white 8% / 元数据 `{ }` / 未知 琥珀描边 `?`） |
| 名称 | 主行 13px white 95%；副行 11px mono white 45%（相对目录），需确认时副行改琥珀 `⚠ 需要人工确认` |
| 类型 | 12px white 75% |
| 大小 | 12px mono white 65% |
| AI 建议 | 12px `#a4c0ff`（`→ 目标路径`）；低置信改琥珀 |
| 置信度 | 46×5 · r3 进度条（white 8% 槽）+ 11px mono 百分比，右对齐 |

- 表头：`padding 12 18`，10.5px / 600 / 0.06em / 大写，white 45%，底部 1px white 6%。
- 行区：`padding 6 8`，行 `padding 14 10`，r10，行间距 2。
- 选中行：`accent 10%` + 描边 `accent 20%`。
- 置信度渐变：高 `linear-gradient(90deg,#5fd3bc,#5b8dff)` + 文字 `#5fd3bc`；
  低 `linear-gradient(90deg,#ff9a6c,#ffd166)` + 文字 `#ffd166`。
- 面板底部状态条：`padding 10 18`，顶部 1px white 6%，11px white 55%，
  左「已选 N 项 · 共 M 项 · 总计 X GB」，右侧 6px 语义圆点 + 状态文案。

### 侧边栏内容（Files）

分组：`收藏` / `最近` / `位置`，分组标题 10px / 600 / 0.08em / white 40%，`padding 0 10 6`。
行：`padding 7 10` · r8 · gap 10，图标 13px（非选中 opacity .7），
文字 13px white 75%，右侧计数 10px mono white 40%。
选中行：`accent 18%` + 描边 `accent 25%` + `inset 0 1px 0 rgba(255,255,255,.08)`，文字白 500/600。

底部固定 AI 状态卡：`padding 12` · r14 · white 4% + 描边 white 8%
· `inset 0 1px 0 rgba(255,255,255,.08)`；8px 状态圆点（已连接 `#5fd3bc` + `0 0 8px` 辉光）
+ 11px 状态文字 + mono 模型名 + 10px 统计行。

### 右侧 AI 面板

宽 352（02 骨架值），内距 18，纵向 gap 14。

- 头部：26×26 · r7 品牌渐变图标 `✨` + 标题 13/600 + 副标题 10px white 50%。
- 「思考过程」卡：`padding 14` · r14 · `accent 8%` + 描边 `accent 18%`；
  标签 10px / 600 / 0.06em `rgba(164,192,255,.85)`；条目 11.5px / 1.55，
  已完成 `✓` `#5fd3bc`，进行中 `●` `#a4c0ff` + 文字 white 60%。
- 「建议目标」卡：`padding 14` · r14 · white 4% + 描边 white 8%；
  标签同上但 white 50%；树形 mono 11px / 1.7，逐层缩进 10，叶子 `#a4c0ff`。
- 操作行：主按钮 `flex:1` h34 · r9 渐变；次级「编辑」h34 · r9 · white 6% + 描边 8%。
- 底部用量条：`padding 10 12` · r10 · white 3%，左 11px white 50%，右 mono 11px white 80%。

## 3.2 媒体库网格 / 详情（Library 分区 · 占位）

> 现有应用没有 Library 能力（`_ComingSoon` 占位）。按设计稿实现**视觉骨架 + 占位数据说明**，
> 真实数据接入计入 backlog。

### 网格页

- 页头：面包屑 11.5px white 50%，主标题 28/700/-0.02em，右侧统计 13px mono white 50%。
- 右上：排序下拉 h30 · r8；视图切换段控 `padding 3` · r8 · white 5%，段 26×24 · r5，
  选中 white 10%；主按钮「＋ 导入」h30 · r8 渐变。
- 过滤 chips：`padding 5 12` · r7；选中 `accent 18%` + 描边 30% + 文字 `#a4c0ff` 600；
  警示 chip `rgba(255,138,91,.12)` + 描边 28% + 文字 `#ffb47a`。
- 海报网格：`repeat(6, 1fr)`，gap `18px 14px`；卡片 `aspect-ratio 2/3` · r11 ·
  描边 white 6–8% · `0 6px 20px rgba(0,0,0,.3), inset 0 1px 0 rgba(255,255,255,.08)`。
- 卡内浮层：底部 `padding 10 10 8` 的 `linear-gradient(180deg, transparent, rgba(0,0,0,.85))`，
  标题 11.5/700 白，副行 9.5px white 65%；右上评分角标 `padding 2 6` · r5 · 黑 50% + blur 8；
  左上 `NEW` 角标 `accent 80%` · 8.5px / 700 / 0.04em。

### 剧集详情页

- 顶部 380px 背景图区（backdrop），其上返回按钮 26×26 · r8 与面包屑。
- 主区 `grid-template-columns: 230px 1fr`，gap 28。海报 `2/3` · r14。
- 标题 34px / 700；元信息行 gap 10；类型 chips `padding 3 9` · r6。
- 概览段落行高 1.55，最大宽 680。
- 统计条：`padding 12 14` · r13，四格（FILES / SIZE / SUBTITLES / PATH），
  标签 10px 大写，主值 16px。
- 季 Tab：`padding 4 12` · r? 段控；剧集表列 `32px 100px 1fr 70px 90px 80px`，
  行高 46，缩略图 100×?，状态角标 `padding 3 8` · r5。

## 3.3 空状态与右键菜单

### 拖入空状态

- 居中虚线框 680 × 340，`border:2px dashed accent 55%`，r20，
  `radial-gradient(at 50% 50%, accent 15%, transparent 70%)`
  + `0 0 80px accent 30%, inset 0 0 60px accent 8%`。
- 文件夹图标 100×80（下层 100×66 · r`10 14 14 14` 品牌渐变 + 描边 white 18%
  + `0 12px 40px accent 40%`；上层书签 46×14 · r`8 8 0 0`）；中间 28px `⬇`。
- 主标题 24/700/-0.01em；说明 13px white 60%，最大宽 420，行高 1.5。
- 分隔「或」：两侧 60×1 分隔线 + 11px white 45%。
- 两个按钮 h34 · r9：`📁 选择文件夹`（white 8% + 描边 14%）、
  `🌐 连接 NAS`（white 6% + 描边 10%，**未实现 → backlog，占位禁用**）。

### 文件右键菜单

宽 250 · r12 · `rgba(24,26,44,.97)` + blur 24 · 描边 white 12%
· `0 24px 60px rgba(0,0,0,.6), inset 0 1px 0 rgba(255,255,255,.08)` · `padding 5`。

菜单项 `padding 8 10` · r8 · gap 10，图标列 16 居中，文字 12px white 88%，
右侧快捷键 9.5px mono white 35%。
高亮项 `accent 20%` + 描边 25% + 白字 500，并可带 16×16 · r4 渐变图标。
分隔线 1px white 8%，`margin 5 8`。危险项文字 `#ff8a80`，快捷键 `rgba(255,138,128,.5)`。

顺序：预览 `Space` / 刮削元数据… `⌘E` / AI 整理此文件 — 重命名 `F2` /
在系统文件管理器中显示 / 属性 `⌘I` — 删除 `Del`。
