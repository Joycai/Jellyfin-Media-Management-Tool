# 04 · 刮削（Scrape）

来源：`04-Scrape.dc.html`。外壳一律以 [02](02-shell.md) 为准。

模态通用：遮罩 `rgba(4,5,12,.5–.55)` + blur 8–10；
面板 r18 · `rgba(17,19,32,.94)` + 描边 white 10%
· `0 40px 100px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,255,255,.08)`。

## 4.1 配置对话框（宽 680）

### 头部
`padding 18 22 14`，底部 1px white 6%，gap 12：
- 34×34 · r9 图标，`linear-gradient(135deg,#5fd3bc,#5b8dff)`
  + `0 4px 12px rgba(95,211,188,.3), inset 0 1px 0 rgba(255,255,255,.3)`。
- 标题 15/600 white 95%；副行 mono 11px white 50%（文件名，中间省略）。
- 右上关闭 26×26 · r7 · white 5%。

### 主体（`padding 18 22`，纵向 gap 16）

**来源**：段标签 10.5px / 600 / 0.06em white 50%；
段控 `padding 2` · r8 · white 5% + 描边 7%，段 h24 · `padding 0 12` · r6，
选中 `accent 22%` + 描边 35% + 文字 `#cfe0ff` 500。两段：`🔗 产品页 URL` / `⌕ 按文件名搜索站点`。

URL 输入：h42 · r10 · white 5%，聚焦态描边 `accent 50%` + `0 0 0 3px accent 12%`，mono 13px。

**识别到番号**卡：`padding 11 14` · r12 · `accent 7%` + 描边 `accent 16%`；
标签 11px white 55%，番号 mono 12/600 `#cfe0ff` 于 `accent 16%` · r5 胶囊内；
右侧搜索站点 chip h24 · `padding 0 10` · r6 · 描边 `accent 30%` · 文字 `#a4c0ff` 11px。

**对比 NFO**：h42 · r10 · white 5% + 描边 8%，`padding 0 6 0 14`；
路径 mono 11.5px white 80% 省略；右侧「浏览…」h30 · `padding 0 12` · r8 · white 7%。
下方提示 10.5px `#5fd3bc` + `✓`。

**AI 后端**（宽 230）+ **附加要求**（flex:1）：同为 h42 · r10 · white 5% + 描边 8%。
后端项含 20×20 · r6 品牌渐变缩写块 + 名称 12.5/500 + 6px 连通圆点 `#5fd3bc` + `▾`。
其下 10.5px white 40% / 1.6 说明文字。

**高级**折叠：r12 · white 3% + 描边 6%；头 `padding 11 14`，标题 11.5/600 white 75%，
右侧 `⌃` `#a4c0ff`。内容 `padding 0 14 14`，gap 10：
Cookie 行 h38 · r9 · white 4% + 描边 8%，右侧「从浏览器导入」h22 · `padding 0 9` · r6；
「📋 改为粘贴页面 HTML」11.5px `#a4c0ff`。

### 底部
`padding 14 22`，顶部 1px white 6%，底 white 2%：
左「✨ 直接询问模型」h34 · `padding 0 14` · r9 · 仅描边 white 10%；
右「取消」文字按钮 12.5px `#a4c0ff` + 主按钮「▶ 开始处理」h34 · `padding 0 18` · r9 渐变。

## 4.2 任务执行（宽 560）

- 头部同上但 32×32 图标、13.5px 标题、10.5px 副行，`padding 16 20 13`。
- 主体 `padding 26 24 22`，居中，gap 20。
- 转圈：44×44 · r50% · `border 3px rgba(95,211,188,.15)`，`border-top-color #5fd3bc`，0.9s linear 无限。
- 步骤卡：`width 100%` · `padding 14 16` · r14 · white 4% + 描边 7%，条目 gap 11：
  - 已完成 `✓` `#5fd3bc` + 文字 white 80% + 右侧 mono 10.5px white 40% 计量。
  - 进行中 `●` `#a4c0ff` + 文字 white 95%/500 + 4px 进度条（最大宽 150，r2，white 8% 槽，
    `linear-gradient(90deg,#5fd3bc,#5b8dff)`）+ 右侧 mono `12 / 33` `#a4c0ff`。
  - 未开始 `○` + 整行 opacity .45。
- 底部 URL：mono 10.5px white 45%，单行省略。
- 页脚 `padding 12 20`：左 mono 10.5px「已用 00:12 · 1,842 tokens」；
  右「取消」`#a4c0ff` + 禁用态按钮 h32 · r9 · white 5% · 文字 white 35%「处理中…」。

## 4.3 结果确认（近全屏，外边距 22，r18）

### 头部
`padding 16 24 13`，38×38 · r10 图标；标题 14.5/600 省略；
副行 11px white 50%：`18 个字段 · 33 张图片` · mono URL ·
配方来源 chip `padding 2 8` · r5 · `rgba(157,123,255,.14)` + 描边 25% + 文字 `#c9b8ff` 10px。

### 左栏 · 字段对比（`flex:1.2`，`padding 14 0 0 24`）

策略段控（三个 h28 · `padding 0 12` · r8）：`仅填补空白`（选中 `accent 16%` + 描边 30%
+ 文字 `#cfe0ff`）/ `全部替换` / `全部保留`；右侧 10.5px white 40%「8 项将写入」。

表格列 `84px 1fr 1fr 118px`，gap 12。表头 10px / 600 / 0.06em / 大写 white 45%，
`padding 12 24 8 0`，底部 1px white 6%。
行 `padding 10 0`，底部 1px white 4%；字段名 11.5/500 white 85%；
本地值 11px white 85%（空值 `—` white 30%）；抓取值 11px white 85% +
来源 chip `padding 1 6` · r4 · 9px：配方 `rgba(157,123,255,.14)`/`#c9b8ff`、
推导 `rgba(95,211,188,.12)`/`#8ee5d2`、LLM 用 AI 紫（同配方色）。
长文本两行截断（`line-clamp:2`，行高 1.5）。

操作段控：`padding 2` · r7 · white 5% + 描边 6%，两段 h20 · r5，
选中「保留」= white 10% + 文字 white 90%/600；选中「替换」= accent 渐变 + 白字 600
+ `inset 0 1px 0 rgba(255,255,255,.3)`。

底部提示行 10.5px white 40%，右对齐「还有 N 个字段 · 向下滚动」。

### 右栏 · 图片素材（宽 452，左描边 1px white 6%，底 white 2%）

- 头 `padding 14 18 10`：标题 12/600 + mono 10.5px「6 / 33 已选」+ 右侧
  「全选」「清空」11px `#a4c0ff`。
- 说明 10px white 40%：`右键可标记为 Jellyfin 专用图片 · 其余按原文件名保存`。
- 网格 `repeat(3,1fr)`，gap 10，卡高 126 · r10。
  - 未选：描边 1px white 10%，opacity .85，底部渐变条 `padding 16 8 6`，
    `○ 未标记` 10.5px white 65% + mono 9px 文件名 white 50%。
  - 已选：描边 `1.5px rgba(95,211,188,.6)` + `0 0 0 3px rgba(95,211,188,.12)`，
    `✓ 角色名` 10.5px `#5fd3bc` 600 + mono 9px 目标文件名。
- 底部渐隐条 h36：`linear-gradient(transparent, rgba(17,19,32,.95))` + 10px 提示。

**图片角色右键菜单**（宽 186 · r12 · `rgba(24,26,44,.98)` · `padding 5`）：
分组标题 `padding 6 10 4` · 9.5px / 600 / 0.06em white 40%「标记为 JELLYFIN 图片」；
项 `padding 7 10` · r8 · gap 8，图标列 14，名称 11.5px，
右侧目标文件名 mono 9px；当前项底 `accent 20%`。
项：海报 `poster.jpg` / 背景 `fanart.jpg` / 封面 `folder.jpg` / 缩略图 `thumb.jpg`
— 分隔线 — `✓ 按原名保存`（右侧原文件名）/ `− 取消选择`。

> 实现映射：菜单项即 `ImageRole`，右侧文件名即 `ImageRole.stem` + 扩展名。
> 设计稿写死了 poster/fanart/folder/thumb 四项，实际以 `ImageRole` 枚举为准，
> **每个角色只出现一次**（两角色映射到同一 Jellyfin 类型会互相覆盖）。

### 页脚
`padding 14 24 16`，顶部 1px white 6%，底 white 2%，纵向 gap 11：
- 第一行两个只读字段（`目标文件夹` flex:1.5 / `NFO 文件名` flex:1），
  标签 9.5px / 600 / 0.06em white 45%，值框 h34 · r9 · white 5% + 描边 8% · mono 10.5px。
- 第二行：16×16 · r5 accent 渐变勾选框 + 11.5px「记录撤销信息（写入前备份被替换的 NFO）」；
  右侧「上一步」white 65% / 「取消」`#a4c0ff` /
  主按钮 h36 · `padding 0 20` · r10 ·
  `linear-gradient(180deg, rgba(95,211,188,.95), rgba(58,168,133,.9))`
  + 描边 white 20% + `inset 0 1px 0 rgba(255,255,255,.4), 0 4px 14px rgba(95,211,188,.35)`，
  文字 `#04211a` 12.5/700「💾 写入 N 字段 + M 图片」。
