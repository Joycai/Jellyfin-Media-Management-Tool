# AI 功能架构规格（供移植到其他 Flutter/Dart 项目）

> 本文档面向 Claude Code：目标是让实施者**不回读本仓库源码**即可在一个新的 Flutter/Dart 项目中复刻本项目的 AI 子系统。每一节都附源文件路径，标注"可原样复制"或"需适配"。
>
> 范围：① AI provider 与模型管理；② "Agent" 工作流（本项目为 **plan-then-execute** 架构，非多轮 tool-calling loop，见第二部分开头的说明）。

---

## 0. 总览与设计原则

### 分层架构

```
┌─────────────────────────────────────────────────────────┐
│ UI 层                                                    │
│  ai_services_screen.dart（provider 管理，双栏）           │
│  ai_assistant_panel.dart / organize_preview_dialog.dart  │
│  organize_progress_screen.dart（apply 进度）              │
├─────────────────────────────────────────────────────────┤
│ 编排层（ChangeNotifier，经 provider 包注入）              │
│  AiProfilesService  —— profile 列表 + 激活选择 + 持久化   │
│  AiService          —— 运行时：调模型、解析计划、统计      │
│  TaskService        —— 后台任务簿记（analyze / apply）    │
│  ApplyController    —— 本地执行循环（每次 apply 一个实例） │
├─────────────────────────────────────────────────────────┤
│ 领域层（纯 Dart，可单测）                                 │
│  AiPrompt（prompt 构建）  OrganizePlan（输出解析）        │
│  applyOrganizeAction()（落盘原语）  PathSafety            │
│  HistoryService（undo manifest）                          │
├─────────────────────────────────────────────────────────┤
│ 传输层（零领域知识，只管 HTTP 和 wire format）            │
│  AiProvider 抽象  OpenAiProvider  GoogleGenAiProvider     │
│  AiHttp（重试）  AiCancelToken（socket 级取消）           │
└─────────────────────────────────────────────────────────┘
```

### 核心设计原则

1. **Plan-then-execute，不是 ReAct/tool loop。** 模型只被调用一次，产出结构化 JSON 计划；执行完全由本地确定性代码完成。好处：可审计（用户在预览里看到并可编辑全部动作）、成本低（一次请求）、安全（模型永远碰不到文件系统）。
2. **Provider 按 wire protocol 抽象，不按厂商。** `AiProviderType.openAi` 覆盖一切 OpenAI 兼容端点（OpenAI / Azure / LocalAI / Ollama / 各类中转）；`googleGenAi` 覆盖 Google Generative Language API。新厂商只有在 wire format 不同（如 Anthropic Messages API）时才需要新增枚举值。
3. **非流式、强制 JSON mode。** 单次补全，120 s 超时，OpenAI 侧 `response_format: {type: json_object}`，Google 侧 `responseMimeType: application/json`。UI 的"进度感"来自任务状态和本地 apply 循环，不来自 token 流。
4. **一切文件系统写操作可审计、可撤销、被限制在 baseDir 内。** 三层防线：prompt 规则（不许发明文件）→ 解析容错 + 置信度门槛 → 执行期 `PathSafety` + 拒绝覆盖 + undo manifest。
5. **传输层与领域层严格分离。** Provider 只返回 `AiResponse{text, promptTokens, completionTokens}`；把文本解析成领域对象是上层（`AiService`）的事。

### 外部依赖

| 包 | 用途 | 使用位置 |
|---|---|---|
| `http` | HTTP 客户端 | 传输层 |
| `path_provider` | app-support 目录（持久化位置） | `AiProfilesService`、`HistoryService` |
| `path` | 路径操作（禁止字符串拼接） | 全部 |
| `provider` | `ChangeNotifier` 注入 | `main.dart` 接线 |
| `file` | 可注入文件系统抽象（`LocalFileSystem` / `MemoryFileSystem`） | `organize_service.dart`、`HistoryService`、测试 |

---

## 第一部分：AI Provider 与模型管理

### 1.1 移植文件清单

| 源文件 | 内容 | 移植方式 |
|---|---|---|
| `lib/services/ai/ai_provider.dart` | `AiProviderType`、`AiConfig`、`AiResponse`、`AiException`、抽象 `AiProvider` | **可原样复制**（无外部依赖，仅 import cancel token） |
| `lib/services/ai/ai_http.dart` | 共享 client + 重试 | **可原样复制** |
| `lib/services/ai/ai_cancel_token.dart` | 取消令牌 | **可原样复制** |
| `lib/services/ai/openai_provider.dart` | OpenAI 兼容实现 | **可原样复制** |
| `lib/services/ai/google_genai_provider.dart` | Google 实现 | **可原样复制** |
| `lib/models/ai_service_profile.dart` | 持久化 profile 模型 | **可原样复制**（依赖 `newId()`） |
| `lib/utils/ids.dart` | `newId()` 唯一 id 生成 | **可原样复制** |
| `lib/services/ai_profiles_service.dart` | profile 列表管理 + 持久化 | 基本可复制；legacy 迁移逻辑（`config.json`）在新项目中可删 |
| `lib/services/ai_service.dart` | 运行时编排 | **需适配**：`analyzeFolder()` 等领域方法按新项目业务替换，保留 config/status/统计骨架 |
| `lib/widgets/settings/ai_services_screen.dart` | 管理 UI（双栏） | **需适配**：l10n key、主题；结构可整体照搬 |

### 1.2 数据模型

两个类，职责不同：`AiServiceProfile` 是**持久化实体**（有 id/name，可多份），`AiConfig` 是**运行时连接配置**（无 id，单份，provider 消费）。桥接方法 `profile.toAiConfig()`。

```dart
enum AiProviderType { openAi, googleGenAi }
// id 序列化：openAi -> 'openai'，googleGenAi -> 'google'
// fromId(String?) 未知值一律回落 openAi

class AiServiceProfile {
  final String id;            // newId() 生成
  final String name;          // 显示名
  final AiProviderType provider;
  final String endpoint;      // API 根，如 https://api.openai.com/v1
  final String apiKey;
  final String model;         // 自由文本，不从 /models 拉取
  final double temperature;   // 默认 0.2

  bool get isComplete;        // endpoint / apiKey / model 三者非空
  AiConfig toAiConfig();
  // copyWith：id 不可替换（身份不变）
}

class AiConfig {
  // 同上字段，去掉 id 和 name
  static const empty = AiConfig(...);  // 全空字符串哨兵：
  // isComplete == false，保证未配置时不会误打真实端点。
  // 编辑器默认值（api.openai.com / gpt-4o-mini）放在
  // AiServiceProfile.create() 里，不放在 empty 里。
}

class AiResponse {
  final String text;
  final int promptTokens;
  final int completionTokens;
  int get totalTokens;
}

class AiException implements Exception {
  final String message;   // 可直接进 UI 的人话
}
```

JSON 序列化统一 **snake_case** key：

```json
{ "id": "...", "name": "OpenAI", "provider": "openai",
  "endpoint": "https://api.openai.com/v1", "api_key": "sk-...",
  "model": "gpt-4o-mini", "temperature": 0.2 }
```

`fromJson` 每个字段都有回落值（缺 id → `newId()`，缺 provider → openAi，缺 temperature → 0.2），保证旧配置文件永不崩。

`AiServiceProfile.create({provider, name})` 提供新建默认值：
- openAi → endpoint `https://api.openai.com/v1`，model `gpt-4o-mini`
- googleGenAi → endpoint `https://generativelanguage.googleapis.com`，model `gemini-2.0-flash`

### 1.3 Provider 抽象与实现

```dart
abstract class AiProvider {
  AiConfig get config;

  /// 单次 JSON-mode 补全。失败抛 AiException；
  /// 飞行中被取消抛 AiCancelled。
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  });

  /// 零 token 的凭证/连通性探针。
  Future<bool> testConnection();
}
```

**OpenAiProvider**（`lib/services/ai/openai_provider.dart`）：

- URL 归一化：去尾部 `/`；若末尾不是 `/v1` 且 URL 不含 `/v1/` 则补 `/v1`。
- `POST {base}/chat/completions`，headers：`Content-Type: application/json` + `Authorization: Bearer <apiKey>`。
- 请求体：

```json
{ "model": "<model>",
  "response_format": {"type": "json_object"},
  "temperature": 0.2,
  "messages": [
    {"role": "system", "content": "<systemPrompt>"},
    {"role": "user",   "content": "<userPrompt>"} ] }
```

- 响应解析：`choices[0].message.content`（缺失/空 → 抛 `'Empty response from model.'`）；usage 取 `usage.prompt_tokens` / `usage.completion_tokens`。注意用 `utf8.decode(res.bodyBytes)` 而非 `res.body`（中文安全）。
- 错误信息提取：非 2xx 时取 `body.error.message` 组成 `'HTTP <code>: <msg>'`，取不到则 `'HTTP <code>'`。
- `testConnection()`：`GET {base}/models`，15 s 超时，2xx 即通过。**只作探针，不解析模型列表**。

**GoogleGenAiProvider**（`lib/services/ai/google_genai_provider.dart`）：

- URL 归一化：不含 `/v1` 则补 `/v1beta`。
- `POST {base}/models/<model>:generateContent?key=<apiKey>`（**API key 在 query string，无 auth header**）。
- 请求体：

```json
{ "systemInstruction": {"parts": [{"text": "<systemPrompt>"}]},
  "contents": [{"role": "user", "parts": [{"text": "<userPrompt>"}]}],
  "generationConfig": {"temperature": 0.2,
                       "responseMimeType": "application/json"} }
```

- 响应解析：`candidates[0].content.parts[0].text`；usage 取 `usageMetadata.promptTokenCount` / `candidatesTokenCount`。
- `testConnection()`：`GET {base}/models?key=...`，额外校验 body 里有 `models` 数组。

两者共同的约定：补全 120 s/次超时；网络异常且 token 已取消 → 抛 `AiCancelled`（而非网络错误）；其余传输错误 → `AiException('Network error: $e')`。

### 1.4 重试与取消（`ai_http.dart` / `ai_cancel_token.dart`）

```dart
class AiHttp {
  static final http.Client client;  // 进程级共享，连接复用，永不 close
  static const _retryableStatuses = {408, 429, 502, 503, 504};

  static Future<http.Response> withRetry(
    Future<http.Response> Function() send, {
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(milliseconds: 500),
    AiCancelToken? cancelToken,
  });
  // 指数退避（×2）；TimeoutException/SocketException 也重试；
  // 尊重整数秒的 Retry-After 头；每次尝试前和退避后检查取消。
  // 4xx 认证/校验错误不重试，原样返回让 UI 显示真实错误。
}

class AiCancelled implements Exception {}  // 语义："用户停止"，不是失败

class AiCancelToken {
  bool get isCancelled;
  http.Client get client;   // 懒建的私有 client
  void throwIfCancelled();
  void cancel();            // close 私有 client → 立即拆 socket 中断在飞请求
  void dispose();
}
```

关键机制：**可取消的请求走 token 私有的 `http.Client`**（而非共享池），`cancel()` 直接关闭它使在飞 I/O 立即失败——这是纯 `http` 包下实现"硬取消"的手法。

### 1.5 多 profile 管理与激活（`ai_profiles_service.dart`）

```dart
class AiProfilesService extends ChangeNotifier {
  List<AiServiceProfile> get services;   // 只读视图
  String? get activeId;
  AiServiceProfile? get active;   // activeId 匹配失败时回落第一个；空列表→null
  AiConfig get aiConfig;          // active?.toAiConfig() ?? AiConfig.empty

  Future<void> init();            // 加载 ai_profiles.json
  Future<AiServiceProfile> add(AiServiceProfile p);  // 追加并自动设为 active
  Future<void> update(AiServiceProfile p);           // 按 id 替换
  Future<void> delete(String id); // 删的是 active 则回落到剩余第一个
  Future<void> setActive(String id);
}
```

**持久化**：`getApplicationSupportDirectory()/ai_profiles.json`，250 ms 防抖写盘（`dispose()` 时 flush 未落盘的修改）。文件结构：

```json
{ "ai_services": [ { ...AiServiceProfile JSON... } ],
  "active_ai_service": "<id>" }
```

**为什么单独一个文件**（而不并入主设置 `config.json`）：编辑 AI profile 不应重写主题配置；反过来拖一个主题滑块也不应反复重写含 API key 的文件。两个服务用同一套 250 ms 防抖模式。

**注意**：API key 是**明文 JSON** 存储。新项目若有更高安全要求，此处是替换成 keychain/凭据管理器的接缝（`AiProfilesService` 的读写两处）。

### 1.6 运行时编排骨架（`ai_service.dart` 中与 provider 管理相关的部分）

```dart
enum ConnectionStatus { unknown, testing, connected, error }

class AiService extends ChangeNotifier {
  AiConfig get config;
  ConnectionStatus get status;
  String? get statusMessage;
  bool get isConfigured;   // config.isComplete

  // 用量统计（供 UI 仪表卡）：
  // lastTokens / totalTokens / requestCount / avgLatencyMs
  // recentLatencies —— 最近 12 次延迟滑窗，供 sparkline

  AiProvider _buildProvider() => switch (_config.provider) {
    AiProviderType.googleGenAi => GoogleGenAiProvider(_config),
    AiProviderType.openAi => OpenAiProvider(_config),
  };

  void updateConfig(AiConfig config);
  // 规则：provider/endpoint/apiKey/model 任一变化 → status 重置 unknown
  //      （temperature 变化不重置）；内容没变则 no-op；
  //      因为会在 build() 期间被调用，通知用 addPostFrameCallback
  //      延后到帧末（_notifySafely），避免 setState-during-build。

  Future<bool> testConnection();  // testing → connected/error + message
}
```

**配置单向流**：`AiProfilesService.aiConfig` → `AiService.updateConfig()`。四个触发点：app 启动（`main.dart`）、onboarding 完成、设置页每次 rebuild（`context.watch<AiProfilesService>()` 后 `read<AiService>().updateConfig(...)`）、激活 profile 被编辑时。

**`main.dart` 接线与 init 顺序**（新项目照抄这个顺序）：

```dart
final aiProfiles = AiProfilesService();
await aiProfiles.init();          // ① 先于 SettingsService（若有 legacy 迁移）
final settings = SettingsService();
await settings.init();            // ②
final ai = AiService();
ai.updateConfig(aiProfiles.aiConfig);  // ③ 播种运行时配置
runApp(MultiProvider(providers: [
  ChangeNotifierProvider.value(value: aiProfiles),
  ChangeNotifierProvider.value(value: settings),
  ChangeNotifierProvider.value(value: ai),
  ...
], child: const App()));
```

### 1.7 管理 UI（`lib/widgets/settings/ai_services_screen.dart`）

双栏布局（左列表 360 px + 右详情），嵌入设置页：

- **左栏**：每个 profile 一张卡（provider 徽标、名称、host、状态徽标 Active/Standby/Offline——`!isComplete` 显示 Offline、model chip、协议 chip）；底部虚线框"添加端点"按钮 → `AiServiceProfile.create()` + `profiles.add()`（add 自动激活）。
- **右栏**（以 profile id 为 Key）：协议分段控件（OpenAI / Google）、显示名、Base URL、API key（默认遮挡 + 显隐切换）、默认模型（**自由文本输入**，无下拉）、temperature 滑块（0–2，20 档）、删除（带确认对话框）、测试按钮、用量卡（tokens/请求数/平均延迟 + sparkline，仅激活 profile 实时更新）。
- **自动保存**：每次字段变更即 `copyWith` → `profiles.update()`；若正是激活 profile，同时 `aiService.updateConfig(updated.toAiConfig())`。没有 Save 按钮。
- **测试连接**：先持久化，再用当前字段值构造临时 `AiConfig` 直接实例化对应 provider 调 `testConnection()`，SnackBar 报结果。

所有文案走 l10n（`app_en.arb` / `app_zh.arb`），移植时这是主要适配工作量。

### 1.8 新增 provider（如 Anthropic）的改动点清单

wire format 不同才需要新枚举值。全部 switch 点：

1. `ai_provider.dart`：`AiProviderType` 加值 + `AiProviderTypeX.id/fromId`
2. 新建 `anthropic_provider.dart` 实现 `AiProvider`（复用 `AiHttp.withRetry` 和 cancel token 模式）
3. `ai_service.dart` 的 `_buildProvider()` switch
4. `ai_service_profile.dart` 的 `create()` 默认 endpoint/model
5. `ai_services_screen.dart`：协议分段控件、provider 徽标 `_badge()`、测试按钮的 provider 实例化 switch
6. l10n：协议显示名两个 arb 各加一条

### 1.9 已知取舍（移植时的决策点）

| 现状 | 理由 / 替代方案 |
|---|---|
| API key 明文 JSON | 桌面本地工具的简化；可换 keychain |
| 无流式 | 输出是一次性 JSON 计划，流式无意义；改对话式 UI 才需要 |
| 模型名自由输入，不拉取 `/models` | 兼容任意中转端点（很多不实现 /models 列表）；`/models` 只当探针 |
| 温度默认 0.2 | 结构化输出要求稳定性 |

---

## 第二部分："Agent" 工作流 —— Plan-then-Execute 架构

### 2.0 与 tool-calling loop 的关系（先读这段）

本项目**没有** tools 数组、没有 function calling、没有多轮消息累积。它把"agent"拆成了三段流水线：

```
① 收集上下文（本地遍历文件夹 → JSON 文件清单）
        ↓
② 单次 LLM 补全（system prompt 定义输出 schema → 模型返回 OrganizePlan JSON）
        ↓
   人工确认门（预览对话框：可编辑、可跳过冲突项）
        ↓
③ 本地 apply 循环（ApplyController 逐条执行 move/rename，模型不参与）
```

模型的"工具"被压缩成**一种输出格式**：`OrganizeAction {source, target, kind, confidence, note}`，语义上等价于唯一的原语工具 "move/rename 一个文件"（建目录是执行时的副作用；全项目不存在删除操作，undo 也是反向 move）。列目录不是工具——是本地预先做好喂给模型的上下文。

选择这个架构而非 ReAct loop 的理由：任务本质是"一批文件的重命名规划"，一次性全量输入/全量输出正好；执行前用户可以整体审计和编辑计划；单次请求成本和延迟最低；模型与文件系统之间有硬隔离。

### 2.1 移植文件清单

| 源文件 | 内容 | 移植方式 |
|---|---|---|
| `lib/services/ai/ai_prompt.dart` | `MediaEntryInput`、`AiPrompt`（system/user prompt 构建，纯静态） | **需适配**：prompt 内容按新项目领域重写，结构照搬 |
| `lib/models/organize_plan.dart` | `OrganizePlan` / `OrganizeAction` / `ActionStatus` + 容错解析 | 结构可复制，字段按新领域调整 |
| `lib/services/organize_service.dart` | `applyOrganizeAction()` 落盘原语 + 注入 FS | **可原样复制**（若新项目也做文件操作） |
| `lib/services/path_safety.dart` | `PathSafety.isWithin()` | **可原样复制** |
| `lib/services/apply_controller.dart` | apply 循环 + pause/stop + 节流通知 | **可原样复制** |
| `lib/services/history_service.dart` | undo manifest 记录与回滚 | **可原样复制** |
| `lib/services/task_service.dart` | 后台任务簿记 | 需适配任务类型 |
| `lib/widgets/ai/ai_assistant_panel.dart` | 计划展示 + Preview 入口 | 需适配 |
| `lib/widgets/ai/organize_preview_dialog.dart` | 预览/编辑/确认对话框 | 需适配 |
| `lib/widgets/ai/organize_progress_screen.dart` | apply 进度屏 | 需适配 |
| `test/helpers/fs.dart` | 内存文件系统测试工厂（POSIX + Windows 风格） | **可原样复制** |

### 2.2 阶段 ①：上下文收集（`AiService._collectEntries`）

- `Directory(baseDir).list(recursive: true, followLinks: false)` 异步流式遍历。
- **硬上限 400 个文件**（防 prompt 爆炸；超限静默截断）。
- 跳过 `.` 开头的隐藏文件。
- 支持 `onlyPaths` 子集：文件本身或任一祖先目录在选中集合里才纳入（即"选中文件夹 = 选中其全部内容"）。
- 每个文件产出一条 `MediaEntryInput{relativePath, sizeBytes, kind}`；`kind` 是本地按扩展名打的粗分类标签（Video/Subtitle/Image/…，来自 `FileLabelService`）——**给模型省一步猜测**。
- 每轮迭代 `cancelToken?.throwIfCancelled()`。

> `relativePath` 有一条关键不变量（源码注释原话）：模型会把它**原样回显**为 action 的 `source`，所以必须精确 round-trip。移植时保持这条约束。

### 2.3 阶段 ②：单次补全与 prompt 设计（`ai_prompt.dart`）

**System prompt** 的四段式结构（新项目照此模板重写领域内容）：

1. 角色与任务一句话（"You are a media-library organizer for Jellyfin… then return a JSON plan."）
2. 领域规则（Jellyfin 命名约定：Movies/TV/字幕/海报/nfo/Extras 的路径模板）
3. 硬性 Rules（防幻觉护栏）：
   - `Use the exact "source" string you were given for each file; do not invent files.`
   - target 必须是相对路径、正斜杠
   - 推断不出的元数据不许编造，降低 confidence 并写 note
   - `Output ONLY a single JSON object, no markdown fences or prose.`
4. **精确的输出 shape 示例**（内联一个完整 JSON 例子）：

```json
{
  "mediaType": "movie | series | music | mixed | unknown",
  "targetRoot": "Movies",
  "reasoning": ["short step", "short step"],
  "actions": [
    { "source": "Dune.Part.Two.2024.2160p.mkv",
      "target": "Movies/Dune Part Two (2024)/Dune Part Two (2024).mkv",
      "kind": "video | subtitle | image | metadata | audio | extra | other",
      "confidence": 0.96,
      "note": "Detected film, matched year 2024" }
  ]
}
```

**User prompt** = 指令句 + 可选的用户 hint 强断言 + 缩进美化的 JSON payload：

```
Organize this folder into a Jellyfin-conform structure.
[若用户指定类型] The user has confirmed this folder is a MOVIE — set "mediaType"
to "movie" and use the Movies/ target root. Do not classify any item as an episode.
[若用户给标题] The user says the title is "X" — trust that over filename guesswork, …
{
  "folder": "<文件夹名>",
  "userMediaType": "movie",        // 可选
  "userTitleHint": "Dune",         // 可选
  "files": [ {"source": "...", "kind": "Video", "size": 123456}, ... ]
}
```

设计要点：用户 hint 同时出现在**自然语言断言**和**结构化字段**两处，双保险。`AiPrompt` 是纯静态类，无任何 IO——可脱离 provider 单测。

**消息组装恒定 2 条**（system + user），无历史。调用点（`AiService.analyzeFolder`）：

```dart
final response = await _buildProvider().complete(
  systemPrompt: AiPrompt.systemPrompt,
  userPrompt: AiPrompt.buildUserPrompt(...),
  cancelToken: cancelToken,
);
cancelToken?.throwIfCancelled();   // 响应已到但用户已取消 → 仍视为取消
final plan = OrganizePlan.fromAiJson(response.text, ...);
_currentPlan = plan;   // ChangeNotifier → 面板渲染
// finally: cancelToken?.dispose(); _isAnalyzing = false; notify
```

同时记录延迟（滑窗 12 个）与 token 用量到统计字段。

### 2.4 输出解析与容错（`organize_plan.dart`）

```dart
enum ActionStatus { pending, needsReview, userEdited, applied, error /* … */ }

class OrganizeAction {
  final String source;
  String target;            // 故意可变：用户在预览里可就地编辑
  final String kind;
  final double confidence;  // clamp 到 [0,1]
  final String note;
  ActionStatus status;
  String? error;
}

class OrganizePlan {
  final String mediaType;
  final String targetRoot;
  final List<String> reasoning;   // 模型自述步骤，UI 以勾选样式展示
  final List<OrganizeAction> actions;
  final int promptTokens, completionTokens;

  factory OrganizePlan.fromAiJson(String raw, {...});
}
```

容错策略（全部照搬）：

1. **`_extractJsonObject(raw)`**：取首个 `{` 到最后一个 `}` 之间的子串再 `jsonDecode`——容忍模型违规输出 markdown 围栏或前后缀 prose；找不到抛 `FormatException`。
2. **confidence 归一化**：数字 > 1 视为百分数除以 100；字符串尝试 parse；最终 clamp [0,1]。
3. **丢弃无效行**：source 或 target 为空的 action 直接扔掉。
4. **置信度门槛**：`confidence < 0.6` → 初始 `ActionStatus.needsReview`（apply 默认跳过，除非用户在预览中 resolve 或编辑），否则 `pending`。

### 2.5 人工确认门（预览层）

- 面板按钮文案刻意是 **"Preview" 而非 "Apply"**（源码注释明说）——它只打开确认对话框，永不直接落盘。
- `organize_preview_dialog.dart` 内容：Before/After 树状 diff + 逐行列表 diff；moves/renames/conflicts 计数；平均置信度；总字节数。needsReview 行 amber 高亮，存在 conflict 时默认进列表视图。
- **计划就地可编辑**：点行改 `action.target`（`userEdited = true`，同时把 needsReview 提回 pending）；或一键接受低置信度提案。设计原则（源码注释）："editing the plan in memory keeps every filesystem write behind ApplyController"——编辑只动内存，写盘只有一个出口。
- Footer 复选框"记录撤销历史"（默认开）；返回 `({bool apply, bool backup})`。
- 确认后构造 `ApplyController(plan, baseDir, backup, totalBytes, history)` 交 `TaskService.startApply()`，并 `ai.clearPlan()`。

### 2.6 阶段 ③：本地 apply 循环（`apply_controller.dart`）

这是全项目唯一真正的 "loop"，纯本地：

```dart
class ApplyController extends ChangeNotifier {
  // 对外：fraction / speedBytesPerSec / eta / done / failed / skipped
  //       / queued / log(List<LogEntry>) / status
  Future<void> start();   // 幂等（_started 防重入：进度屏和 TaskService 都会调）
  void pause(); void resume(); void stop();
}
```

循环体：

```dart
for (final a in plan.actions) {
  if (_stopRequested) break;
  while (_pauseGate != null) { await _pauseGate!.future; }  // Completer 暂停门
  if (_stopRequested) break;
  if (a.status == ActionStatus.needsReview) { _skipped++; continue; }
  if (a.status != ActionStatus.pending) continue;
  final outcome = await applyOrganizeAction(a, baseDir: baseDir);
  // 成功 → _done++、累计字节、_moves.add({from, to})、log(moved)
  // 失败 → _failed++、log(failed, error) —— 单条失败不终止批次
}
if (backup && _moves.isNotEmpty) await history.record(moves: _moves, ...);
_status = _stopRequested ? ApplyStatus.stopped : ApplyStatus.done;
```

工程细节（照搬）：

- **通知节流**：`_scheduleNotify()` 50 ms 合并（万条任务 ~20 fps 而非两万次 rebuild）；用户操作与终态用 `_notifyNow()` 立即刷。
- **节奏控制**：小批量（≤60 条）每条 delay 40 ms、≤200 条 12 ms——同卷 rename 快到进度条闪没，故意放慢让用户"看得见"。
- **stop 与 pause 交互**：stop 先放行 pause 门再让循环 fall through。
- 日志用语义化枚举 `LogEntry{kind: started|moved|skipped|failed|finished|stopped, ...}`，渲染时才转文案 → 日志可 l10n。

### 2.7 落盘原语与安全（`organize_service.dart` / `path_safety.dart`）

```dart
Future<MoveOutcome> applyOrganizeAction(
  OrganizeAction action, {
  required String baseDir,
  FileSystem fs = const LocalFileSystem(),   // package:file 注入
}) async {
  final path = fs.path;   // ⚠️ 必须用注入 FS 自带的 path context
  final sourcePath = path.normalize(path.join(baseDir, action.source));
  final targetPath = path.normalize(path.join(baseDir, action.target));
  if (!PathSafety.isWithin(baseDir, sourcePath, context: path) ||
      !PathSafety.isWithin(baseDir, targetPath, context: path)) {
    throw FileSystemException('Path escapes base directory', targetPath);
  }
  await fs.directory(path.dirname(targetPath)).create(recursive: true);
  await _moveFile(sourceFile, targetPath, fs);
}
```

安全规则（全部照搬）：

- **`PathSafety.isWithin`**：normalize + absolute 后做包含判断。源码注释明确其防御对象：*AI 生成的计划或被篡改的 undo manifest 通过 `..`/绝对路径逃出用户选择的目录*。
- **拒绝覆盖**已存在目标（大小写-only 改名除外）。
- `_moveFile`：优先 `rename`；跨卷回退 copy+delete；copy 后删源失败会清掉半成品目标，避免静默产生重复文件。
- source == target 直接标 applied；source 不存在报错。每条独立 try/catch，结果写回 `action.status/error`。

**注入式文件系统的教训**（commit 48aaa32）：路径解析必须走 `fs.path`（注入 FS 自带的 `p.Context`）而不是全局 `package:path`，`PathSafety.isWithin` 也要接受 `context` 参数——否则 POSIX 风格的内存文件系统在 Windows 宿主上会被按 Windows 规则解析，测试全挂。测试侧 `test/helpers/fs.dart` 提供 `newMemoryFs()`（POSIX，预建 `/work`）和 `newWindowsMemoryFs()`（预建 `C:\work`）两个工厂。

> 已知不一致：读路径（`_collectEntries` 等）仍直接用 `dart:io`，注入只覆盖写路径（apply/undo）。新项目可顺手统一。

### 2.8 Undo（`history_service.dart`）

- backup 开启时，apply 结束把 `_moves` 写成 manifest：`<app-support>/undo/op-<timestamp>.json`，保留 7 天。
- `undo()`：**反向遍历**（后建的先回滚，子目录先清空）逐条 target→source rename；同样过 `PathSafety.isWithin`；**部分成功时重写 manifest 只保留未回滚条目**，可反复重试。

### 2.9 后台任务与取消语义（`task_service.dart`）

- 两类任务：**analyze**（持 `AiCancelToken`，可取消，完成后 summary 形如 `"22 · 1.2k tok"`）与 **apply**（持 `ApplyController`，实时进度、pause/stop）。`runningCount` 驱动 tab 徽标。
- 触发路径：`home_screen._organize()` 校验 `ai.isConfigured` → 弹 hint 对话框（媒体类型 movie/series/auto + 标题，可空）→ `tasks.startAnalyze(...)` fire-and-forget，SnackBar 告知已开始。
- **取消检查点共三处**：目录遍历中、HTTP 重试循环前后（含退避期间）、响应到达与计划入库之间。
- **`AiCancelled` 归类为 stopped 而非 failed**——"用户主动停止"不是错误，UI 不飘红。

### 2.10 安全模型总结（三层）

| 层 | 机制 |
|---|---|
| Prompt | 不许发明文件、target 必须相对路径、不确定就降 confidence |
| 解析 | JSON 抽取容错、confidence 归一化、空行丢弃、< 0.6 → needsReview 默认跳过 |
| 执行 | `PathSafety` 圈禁 baseDir、拒绝覆盖、原子 move + 跨卷清理、undo manifest |

---

## 第三部分：演进为真 tool-calling loop 的接缝

若新项目需要多轮 agent（模型中途请求更多信息、逐步执行），现有代码的改造点：

1. **`AiProvider.complete()`** → 扩展为接受 `List<Message>` + `List<ToolSchema>`，返回含 `tool_calls` 的响应。OpenAI/Google 的 wire format 差异仍封在各自 provider 内。`AiHttp`、`AiCancelToken` 无需改动。
2. **`AiService.analyzeFolder()`** → 改为消息累积循环：解析 `tool_calls` → 执行 → 把 tool result 追加进 messages → 再请求，加 max-iterations 上限。现有的取消检查点模式（每轮循环 + 请求前后）直接沿用。
3. **`applyOrganizeAction()` 天然就是 "move" 工具的执行器**——已具备注入 FS、路径安全、拒绝覆盖。把它包一层 JSON-schema 工具定义即可。`_collectEntries` 同理可包成 "list_files" 工具。
4. **保留 preview 确认层作为 human-in-the-loop 门**：破坏性工具（move）不在循环内直接执行，而是累积成计划，循环结束后仍走预览→确认→`ApplyController`。这样 tool loop 只做"侦察与规划"，写盘出口不变。

---

## 附录：移植检查清单（按依赖顺序）

**第 1 步 — 传输层**（无内部依赖，可原样复制）：
- [ ] `lib/utils/ids.dart`
- [ ] `lib/services/ai/ai_cancel_token.dart`
- [ ] `lib/services/ai/ai_http.dart`
- [ ] `lib/services/ai/ai_provider.dart`
- [ ] `lib/services/ai/openai_provider.dart`、`google_genai_provider.dart`
- [ ] pubspec：`http`

**第 2 步 — Profile 管理**：
- [ ] `lib/models/ai_service_profile.dart`
- [ ] `lib/services/ai_profiles_service.dart`（删掉 legacy `config.json` 迁移分支）
- [ ] pubspec：`path_provider`、`provider`

**第 3 步 — 运行时编排**：
- [ ] `AiService` 骨架：config/status/统计 + `_buildProvider()` + `updateConfig()` + `testConnection()`
- [ ] 按新项目领域替换 `analyzeFolder()`：自己的上下文收集 + 自己的 `AiPrompt`（沿用四段式 system prompt 模板与"精确 JSON shape 示例"手法）+ 自己的 plan 模型（沿用 `fromAiJson` 容错三件套：JSON 抽取、数值归一化、置信度门槛）
- [ ] `main.dart` 接线：profiles.init() → aiService.updateConfig(profiles.aiConfig) → MultiProvider

**第 4 步 — 执行与安全**（若新项目也操作文件系统）：
- [ ] `lib/services/path_safety.dart`、`organize_service.dart`、`apply_controller.dart`、`history_service.dart`
- [ ] pubspec：`file`、`path`；测试复制 `test/helpers/fs.dart`

**第 5 步 — UI**：
- [ ] `ai_services_screen.dart`（provider 管理，适配 l10n/主题）
- [ ] 预览对话框 + 进度屏 + 任务页（按新领域重做内容，保留 Preview→确认→Apply 链路）
- [ ] 两个 arb 文件补齐全部 AI 相关 key

**验证**：
- [ ] 单测 `AiPrompt`（纯静态）与 plan 解析（喂带 markdown 围栏的脏输出）
- [ ] 用 `newMemoryFs()` / `newWindowsMemoryFs()` 测执行层（路径逃逸、拒绝覆盖、跨卷回退）
- [ ] 真机验证：配置 profile → testConnection → 完整 analyze→preview→apply→undo 链路
