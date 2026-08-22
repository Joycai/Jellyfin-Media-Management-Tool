# 动画改进计划

由 `improve-animations` 审计生成(commit 1699a41,2026-08-22)。每份计划自包含,可交给任意执行代理(包括低能力模型)独立完成。

| 编号 | 标题 | 严重度 | 状态 |
| --- | --- | --- | --- |
| [001](001-speed-up-context-menus.md) | 加快右键菜单的打开动画 | HIGH | DONE |
| [002](002-glass-dialog-entrance.md) | 玻璃对话框统一"缩放+淡入"入场 | HIGH | DONE |
| [003](003-desktop-page-transitions.md) | 桌面风格页面转场取代安卓 Zoom | MEDIUM | DONE |
| [004](004-scrape-panel-stage-resize.md) | 刮削面板阶段切换的尺寸瞬移 | MEDIUM | DONE(带偏离,见计划内说明) |
| [005](005-smooth-progress-bars.md) | 进度条/置信度条数值跳变平滑 | LOW | DONE |
| [006](006-glass-segmented-transition.md) | GlassSegmented 选中态过渡 | LOW | DONE |
| [007](007-hover-checkbox-fade.md) | 悬停勾选框淡入淡出 | LOW | DONE |

## 推荐执行顺序

001 → 002 → 003 → 004(按杠杆率:改动量递增,影响面递减)。

## 依赖关系

- 四份计划互相独立,可并行执行。
- 002 与 004 同处 scrape_panel.dart 附近(002 改 `showScrapePanel` 的路由,004 改面板内部),若同时执行注意合并冲突,逻辑上无依赖。

## 审计中记录但未立项的低优先级项

- 全应用未读取 `MediaQuery.disableAnimations`(系统减少动效开关);目前动画均为 300ms 内的轻量过渡,风险低,留作后续。(其余三项已分别立项为 005/006/007 并完成。)

## 审定为"正确、勿动"的现状

- 文件行悬停/选中高亮不带动画——高频交互,瞬时反馈是对的。
- Files/Library/Tasks 分区切换瞬时完成——同上。
- 缩略图加载 180ms 淡入(file_thumbnail.dart:97)、日志跟尾滚动 180ms easeOut(organize_progress_screen.dart:75)——用途明确、时长合理。
- Onboarding 步骤转场(onboarding_screen.dart:97–150)——首次运行场景,允许更慢更有仪式感。
