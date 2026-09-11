# 本地小模型优化与 Agent 化改造计划

> 状态：**决策已确认（2026-09-10）；预设参数表已按官方出处填入（2026-09-10 调研）。**
> 本文件是后续几个 PR 的实施依据；每个阶段可独立交付、独立回退。
> 架构规范参照 `ai-agent-architecture`（07 runtime / 08 工具注册与写入安全 / 10 工作区与上下文 / 03 推理 / 05 工具协议 / 12 路线图）。

---

## 0. 现状与证据

### 0.1 实测数据（LM Studio，`qwen3.8-27b-uncensored`，IQ3_XXS，加载上下文 104,704）

| 请求 | 耗时 | 生成 token | 备注 |
|---|---|---|---|
| hello（连接测试） | 1–5 s | 71–74 | 其中 **61–64 是思考** |
| 整理 30 个文件 | 88 s | 5,964 | JSON 本体约 2,500，**一半以上是思考** |
| 整理 60 个文件 | 122 s | 9,022 | 超过旧 120 s 上限（已由 #51 流式修复） |
| `response_format: json_object` | — | — | LM Studio 400：只接受 `json_schema` / `text` |

结论：慢和"绕圈子"主要来自三件事——**思考 token 过多**、**温度 0.2 远低于官方推荐**（Qwen 官方明确警告低温/贪心解码会导致无限重复）、**输出与文件数成正比**（小模型写几十条几乎相同的 action 时容易漂移和重复）。

### 0.2 app 内所有 LLM 调用

| # | 任务 | 入口 | 调用形态 | 输入规模 | 输出 | 主要问题 |
|---|---|---|---|---|---|---|
| 1 | 整理 | `AiService.analyzeFolder` | 单发；有上下文预算时按 token 分批（#49） | ≤400 个文件的列表 | **每个文件一条 action** | 输出 O(文件数)、重复性强；一批失败整批重来；进度不可见 |
| 2 | 学习刮削规则 | `RecipeLearner.learn` | 单发，最多 2 次 | HTML 骨架 ≤60 KB（按窗口裁剪） | recipe JSON | 骨架大；裁剪可能恰好丢掉关键区块；自检只能在整份提交后做 |
| 3 | LLM 直接提取 | `DirectExtractor.extract` | 单发 | 页面文本 ≤40,000 字符 + 图片清单 | 字段 JSON | 日文页面 token 多；一次输出全部字段 |
| 4 | 连接测试 | `AiConnectionCheck.run` | 单发 hello | — | — | 不检测工具调用能力 |
| 5 | 上限探测 | `detectLimits` | 无生成 | — | — | — |

不调用 LLM 的：批量刷新 `rescrapeAll`、保存图片、NFO 写入、应用整理计划。

共同问题：**全部是"一次性丢进去"的单发调用**，无工具调用、无中间结果、失败即全部重来，本地模型的上下文与输出上限随输入规模线性逼近。

---

## 1. 贯穿三个阶段的硬约束

1. **写盘闸门不变。** 整理仍然只经 `OrganizePreviewDialog` → `ApplyController` → `applyOrganizeAction`；刮削仍然只经预览 → `MetadataWriter`。Agent 工具**全部是只读或"草稿写"（写内存/工作区）**，永远不直接改用户的媒体库。因此本应用的 agent **不需要 L2 审批队列**——人审仍然发生在现有预览对话框里。
2. **确定性的事交给代码，模型只做判断。** 文件名 token 解析、Jellyfin 路径拼装、字幕跟随视频、扩展名分类由代码完成；模型只回答"这组文件是什么剧/电影、第几季、年份多少"。
3. **runtime 只做循环，策略在 preset。** 工具执行一律查注册表分发，runtime 里没有 `switch(toolName)`。
4. **协议完整性。** 每个 tool_call 必有配对回复；取消到达时剩余调用补 `[not run]` 桩后再抛；一次性提示发出即撤。
5. **小模型友好。** 单次工具结果限幅 + 分页；单轮只让模型写短结构；上下文不随文件数增长；**思考默认关闭**（D2）。
6. **最小公倍数发送 + 错误驱动降级；静默失败必须主动验证。** 非标准字段只在有值时发，400 点名该字段就去掉并记住（与现有 `response_format` / `stream_options` 降级同一机制）。但"被静默忽略"不会报错（如 Ollama `/v1` 忽略 `top_k`、LM Studio `/v1` 忽略 `reasoning_effort`），这类只能靠响应里的证据（reasoning token 是否为 0）或 UI 说明处理。
7. **工具调用是硬性前提（D4）。** 不支持工具调用的模型**不能运行** Agent 任务：连接测试检测并记录能力，设置页标明，整理/刮削入口禁用并说明原因。**不保留单发回退**——Agent 路径上线后，对应的单发管线随之删除。

非目标：子代理间通信、并行编排、上下文压缩式长会话（本应用没有聊天会话）、引入代码生成库。

---

## 阶段一：采样参数、模型预设与思考开关（对应"第 1 步"）

### 1.1 目标
为本地小模型提供正确的采样参数；对常见模型家族内置官方推荐值，用户可逐项覆盖；思考默认关闭。

### 1.2 数据模型
- `AiConfig` / `AiServiceProfile` 新增可空字段：`topP`、`topK`、`minP`、`presencePenalty`、`repeatPenalty`；`temperature` 改为可空。**空 = 跟随预设**。
- 新增 `thinkingEnabled: bool`，**默认 false**（D2）。
- 连接测试时记录 `serverKind`（`lmStudio` / `ollama` / `llamaCpp` / `vllm` / `openAi` / `google` / `unknown`，复用 `detectLimits` 已经识别出的来源），用于选择关思考的字段和 UI 说明。
- 新增纯数据表 `lib/services/ai/sampling_presets.dart`：
  ```dart
  class SamplingValues {
    final double? temperature, topP, minP, presencePenalty, repeatPenalty;
    final int? topK;
  }

  class SamplingPreset {
    final String id;                    // 'qwen3.8'
    final String label;                 // UI 显示名（专有名词，不本地化）
    final RegExp match;                 // 按模型 id 匹配，不区分大小写，任意位置
    final SamplingValues nonThinking;   // 思考关闭（默认）时使用
    final SamplingValues? thinking;     // 思考开启时使用；null = 与 nonThinking 相同
    final ThinkingControl thinkingControl;  // 见 1.4
    final String source;                // 官方出处 URL，UI 可点开
    final String? note;                 // 例如"需要模型卡中的 system prompt"
  }
  ```
- **匹配顺序敏感**：预设表是有序列表，第一个命中即采用（顺序见 1.3）。微调版（`-uncensored`、`-abliterated`、量化后缀）按其基座家族匹配，这是启发式，用户可覆盖。
- 生效值 = 用户覆盖 ?? 预设值（按 `thinkingEnabled` 选 `thinking` / `nonThinking`）?? 旧行为（温度 0.2，其余不发）。解析函数纯函数、可单测。
- **显式发送**：预设给出的每个字段都显式写进请求体，**包括 `min_p: 0`、`presence_penalty: 0`、`repeat_penalty: 1.0` 这类"中性值"**——服务端会用自己的默认补缺（llama.cpp：`top_k 40`、`min_p 0.05`、`repeat_penalty 1.1`；Ollama `/v1`：缺省时把 `temperature` / `top_p` 强制为 1.0），不发就等于没有预设。预设没给出的字段不发。
- **迁移（D1，已确认）**：旧档案里存的 `temperature: 0.2`（旧默认值）读取时视为**未自定义**；其他温度值视为用户覆盖、保留。

### 1.3 预设表

记号：`T` temperature · `P` top_p · `K` top_k · `minP` · `pres` presence_penalty · `rep` repeat_penalty。"gen_config" 表示该值只出现在 `generation_config.json`，模型卡正文没有推荐语。表格自上而下即匹配顺序。

| # | 家族 | 匹配（模型 id） | 思考关（默认） | 思考开 | 关思考 | 出处 / 说明 |
|---|---|---|---|---|---|---|
| 1 | Qwen3.8 | `qwen3\.8` | T0.7 P0.8 K20 minP0 pres1.5 rep1.0 | T1.0 P0.95 K20 minP0 pres0 rep1.0 | 模板开关 | [Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B)；默认开启思考；另有 `reasoning_effort` low/medium/xhigh；官方不支持 `/no_think` |
| 2 | Qwen3.6 | `qwen3\.6` | T0.7 P0.8 K20 minP0 pres1.5 rep1.0 | T1.0 P0.95 K20 minP0 pres0 rep1.0 | 模板开关 | [Qwen3.6-27B](https://huggingface.co/Qwen/Qwen3.6-27B)；思考模式 presence 为 0，与 3.5 不同 |
| 3 | Qwen3.5 | `qwen3\.5` | T0.7 P0.8 K20 minP0 pres1.5 rep1.0 | T1.0 P0.95 K20 minP0 pres1.5 rep1.0 | 模板开关 | [Qwen3.5-27B](https://huggingface.co/Qwen/Qwen3.5-27B)；默认开启思考 |
| 4 | Qwen3-Next Instruct | `qwen3-next.*instruct` | T0.7 P0.8 K20 minP0 | — | 无思考 | [Qwen3-Next-80B-A3B-Instruct](https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct)（Thinking 版未取得官方值，不内置） |
| 5 | Qwen3 Thinking-2507 | `qwen3-.*thinking-2507` | — | T0.6 P0.95 K20 minP0 | **无法关闭** | [30B-A3B-Thinking-2507](https://huggingface.co/Qwen/Qwen3-30B-A3B-Thinking-2507)；输出可能只有 `</think>` 没有开头标签 |
| 6 | Qwen3 Instruct-2507 | `qwen3-.*instruct-2507` | T0.7 P0.8 K20 minP0 | — | 无思考 | [30B-A3B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507) |
| 7 | DeepSeek-R1-0528-Qwen3 | `deepseek-r1-0528-qwen3` | 同 #10 | 同 #10 | 同 #10 | [R1-0528](https://huggingface.co/deepseek-ai/DeepSeek-R1-0528)："can be run in the same manner as Qwen3-8B" |
| 8 | DeepSeek-R1 及蒸馏 | `deepseek-r1` | — | T0.6 P0.95 | **无法关闭** | [DeepSeek-R1](https://huggingface.co/deepseek-ai/DeepSeek-R1)：0.5–0.7 以避免无限重复；须排在所有 `qwen` 规则之前 |
| 9 | QwQ | `qwq` | — | T0.6 P0.95 K20 minP0 | **无法关闭** | [QwQ-32B](https://huggingface.co/Qwen/QwQ-32B)（K 官方给 20–40，取 20） |
| 10 | Qwen3（混合思考） | `qwen3` | T0.7 P0.8 K20 minP0 | T0.6 P0.95 K20 minP0 | `/no_think` 或模板开关 | [Qwen3-8B](https://huggingface.co/Qwen/Qwen3-8B)："DO NOT use greedy decoding"；presence 0–2 可选（[GGUF 卡](https://huggingface.co/Qwen/Qwen3-8B-GGUF)建议量化模型用 1.5，预设不内置，留给用户） |
| 11 | Sakura-GalTransl v3 | `galtransl` | T0.3 P0.8 | — | 无思考 | [Sakura-GalTransl-7B-v3.7](https://huggingface.co/SakuraLLM/Sakura-GalTransl-7B-v3.7) |
| 12 | SakuraLLM v0.9 / v1.0 | `sakura.*v(0\.9\|1\.0)` | T0.1 P0.3 rep1.0 | — | 无思考 | [SakuraLLM](https://github.com/SakuraLLM/SakuraLLM)；输出退化时可加 frequency_penalty 0.1–0.2（不内置） |
| 13 | Qwen2.5-Coder | `qwen2\.5-coder` | T0.7 P0.8 K20 rep1.1 | — | 无思考 | gen_config（[7B](https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct/blob/main/generation_config.json)） |
| 14 | Qwen2.5 | `qwen2\.5` | T0.7 P0.8 K20 rep1.05 | — | 无思考 | gen_config（[7B](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct/blob/main/generation_config.json)） |
| 15 | Gemma 4 | `gemma-?4` | T1.0 P0.95 K64 | 同左 | 默认关（system prompt 首部 `<\|think\|>` 才开启） | [Gemma 4 官方卡](https://ai.google.dev/gemma/docs/core/model_card_4)："standardized sampling configuration across all use cases" |
| 16 | Gemma 3 / 3n | `gemma-?3` | T1.0 P0.95 K64 | — | 无思考 | gen_config（官方仓库需登录，读自 unsloth 镜像）+ [官方员工回复](https://huggingface.co/google/gemma-3-12b-it/discussions/25) |
| 17 | gpt-oss | `gpt-oss` | 以 `reasoning_effort: low` 代替关闭 | T1.0 P1.0 | **无法关闭** | [gpt-oss README](https://github.com/openai/gpt-oss/blob/main/README.md) |
| 18 | Phi-4-reasoning | `phi-4.*reasoning` | — | T0.8 P0.95 K50 | **无法关闭** | [Phi-4-reasoning](https://huggingface.co/microsoft/Phi-4-reasoning)："must use"；另需模型卡 system prompt（note 提示） |
| 19 | Magistral Small | `magistral` | — | T0.7 P0.95 | 推理模型 | [Magistral-Small-2509](https://huggingface.co/mistralai/Magistral-Small-2509)；另需模型卡 system prompt |
| 20 | Mistral Small 3.1 / 3.2 | `mistral-small-3\.[12]` | T0.15 | — | 无思考 | [3.2 卡](https://huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506) |
| 21 | Mistral Nemo | `mistral-nemo` | T0.3 | — | 无思考 | [Nemo 卡](https://huggingface.co/mistralai/Mistral-Nemo-Instruct-2407)："requires smaller temperatures" |
| 22 | Llama 3.1 / 3.2 / 3.3 | `llama-?3\.[123]` | T0.6 P0.9 | — | 无思考 | gen_config（官方仓库需登录，读自 unsloth 镜像） |
| 23 | GLM-4.7-Flash | `glm-4\.7-flash` | T1.0 P0.95 | 同左 | 模板开关 | [GLM-4.7-Flash](https://huggingface.co/zai-org/GLM-4.7-Flash)（agentic 场景卡上另给 T0.7 P1.0，暂不内置） |
| 24 | GLM-4.6 | `glm-4\.6` | T1.0 | 同左 | 模板开关 | [GLM-4.6](https://huggingface.co/zai-org/GLM-4.6)（top_p/top_k 只针对代码评测，不内置） |

**刻意不内置**（无官方值或未取得原文）：Phi-4（非 reasoning）、Sakura-14B-Qwen3-v1.5、GLM-4.5-Air、GLM-5.x、Qwen3-Next Thinking、DeepSeek-V3（仅有托管 API 的温度换算，无本地建议）、Qwen3.5 instruct 的"推理任务"档（官方卡片与搜索摘要冲突）。未命中任何预设的模型（如 `spark-x2.5-4b`）显示"未识别模型家族，使用服务端默认"。

预设数据文件的每一行在代码注释里保留出处 URL；新增家族必须附官方出处。

### 1.4 请求层

**采样字段：**

| 字段 | LM Studio `/v1` | Ollama `/v1` | llama.cpp | vLLM | OpenAI 官方 |
|---|---|---|---|---|---|
| `top_p` / `presence_penalty` | ✓ | ✓ | ✓ | ✓ | ✓（推理模型 400） |
| `top_k` | ✓ | **静默忽略** | ✓ | ✓ | **400** |
| `min_p` | 文档未列出（待实测） | **静默忽略** | ✓ | ✓ | **400** |
| `repeat_penalty` | ✓ | **静默忽略** | ✓ | 忽略并记日志 | **400** |

- 预设字段显式发送（见 1.2）；用户覆盖同样发送。
- **400 降级**：错误文本点名某字段（`Unrecognized request argument supplied: top_k`、`Unsupported parameter: 'temperature'`）→ 去掉该字段重试，按 endpoint + model 记住。覆盖 OpenAI 官方的非标准字段与推理模型拒收 `temperature` / `top_p` / `presence_penalty` 两种情况。
- **Ollama**：`serverKind == ollama` 时设置页提示"Ollama 的 OpenAI 兼容接口会忽略 top_k / min_p / repeat_penalty，需在 Modelfile 中设置"。
- **Google**：Gemini `generationConfig` 对 `topK` / 惩罚项的支持未核实——不内置 Gemini 预设，只发送用户显式填写的值，依赖 400 降级。

**思考开关（D2，默认关闭）：**

`ThinkingControl` 描述"家族能不能关、怎么关"，与 `serverKind` 组合决定实际发什么：

| 服务端 | 关闭思考的方式（按优先级尝试，均以响应证据判定） |
|---|---|
| llama.cpp（需 `--jinja`） | `chat_template_kwargs: {"enable_thinking": false}`；`reasoning_effort: "none"` |
| vLLM | `chat_template_kwargs: {"enable_thinking": false}`；`reasoning_effort: "none"` |
| Ollama `/v1` | `reasoning_effort: "none"` |
| LM Studio `/v1` | **已实测（见 1.6）：`reasoning_effort: "none"` 有效，`chat_template_kwargs.enable_thinking=false` 与 `/no_think` 均无效。** 这与 [#988](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/988) 记录的"0.3.25 忽略 `reasoning_effort`"相反——该问题应已修复，或与版本 / 模型有关。**顺序仍不写死**：按上表逐个发、以"回复里是否还有推理"判定，命中后按 endpoint + model 记住；候选 ④（原生 `/api/v1/chat` 的 `reasoning: "off"`）没用上 |
| 其他 / 未知 | 家族声明了模板开关时发 `chat_template_kwargs`；否则不发 |

- **必须验证关闭是否真的生效**（静默失败）：连接测试在思考关闭时检查响应的 `reasoning_content` / `completion_tokens_details.reasoning_tokens`；仍在思考 → 设置页显示"思考未能关闭：请在 LM Studio 的模型设置中关闭 Enable Thinking"，任务照常运行，不伪装成功。验证结果按 endpoint + model 缓存。
- **无法关闭的家族**（DeepSeek-R1、QwQ、Qwen3 Thinking-2507、Phi-4-reasoning、Magistral）：开关置灰并说明"此模型只能以思考模式运行"，使用思考模式参数。gpt-oss 以 `reasoning_effort: low` 代替关闭。
- 用户手动打开思考 → 走该家族的"思考开"参数，不发任何关闭字段。
- 服务端 400 点名开关字段 → 去掉并记住，按上表尝试下一个候选。

### 1.5 UI（设置 → AI 服务详情页）
- 新增"采样参数"区：显示匹配到的预设名与出处链接；温度、top_p、top_k、min_p、presence penalty、repeat penalty 为数字输入框，**占位符显示当前模式下的预设值**，输入即覆盖；"恢复推荐值"按钮清空覆盖。
- 新增"思考模式"开关，默认关；切换时占位符随之切换为对应模式的预设值。开关旁显示验证状态：已确认关闭 / 未能关闭（附操作指引）/ 此模型只能思考 / 未测试。
- 预设 `note`（如"需要模型卡中的 system prompt"）显示为提示。
- `serverKind == ollama` 时显示字段被忽略的提示。
- 未匹配任何预设时显示"未识别模型家族，使用服务端默认"。
- 温度滑块改为数字框（滑块无法表达"跟随预设"）。
- 所有文案同时加入 `app_en.arb` / `app_zh.arb`。

### 1.6 验证
- 单测：预设匹配**顺序**（`qwen3.8-27b-uncensored` → Qwen3.8、`deepseek-r1-distill-qwen-14b` → DeepSeek-R1、`deepseek-r1-0528-qwen3-8b` → Qwen3、`sakura-14b-qwen2.5-v1.0` → Sakura、`qwen2.5-coder-7b` → Qwen2.5-Coder）、覆盖优先级、思考模式切换选参、中性值显式发送、旧档案迁移、400 降级、关思考候选依次降级（`MockClient`）。
- **LM Studio 实测**（2026-09-11，LM Studio + `qwen3.8-27b-uncensored` IQ3_XXS，加载上下文 32000 / 上限 262144）：
  1. **采样字段全部被接受**：`temperature` / `top_p` / `top_k` / `min_p` / `presence_penalty` / `repeat_penalty` 一起发，200，无一被 400 点名。
  2. **关思考候选**：① `chat_template_kwargs.enable_thinking=false` **无效**（仍有 18 个推理 token）；② `reasoning_effort: "none"` **有效**（`reasoning_content` 为空、`reasoning_tokens` 为 0）；③ `/no_think` **无效**。降级阶梯因此落在 ②，与文档原先的假设相反（见 1.4）。
  3. **工具调用可用**（D4 的硬门槛）：非流式 `finish_reason: tool_calls`、参数为合法 JSON；流式下第一个 delta 带 `index`/`id`/`name`，第二个只带 `arguments`，正是按 index 累积所处理的形状。`/api/v0/models` 也报告 `capabilities: ["tool_use"]`。
  4. **整理 agent 实跑**（6 文件 / 2 组，合成文件名）：2 轮、4896 token、约 10 秒；分组、字幕跟随剧集与语言标签、`poster.jpg` 标 needsReview 均符合预期。另发现模型会把 `Frieren` 补全成正式全名，已收紧提示词修正（另见对应 PR）。
  5. **待做**：同一个 30 文件夹的 A / B / C 对比（耗时、completion / reasoning token、解析成功率、是否出现重复段落），以及 GUI 侧的取消续跑与预览修正回写。

**交付：PR 1，同时版本升至 0.20.0+16（D5）。**

---

## 阶段二：任务梳理与 Agent 循环（对应"第 2 步"）

### 2.1 各任务 Agent 化后的形态

#### 整理（收益最大，优先）
**代码先做确定性预处理：**
1. 扫描目录（沿用 ≤400 上限与 dotfile 规则）。
2. 文件名 token 解析（新写 `lib/services/organize/filename_parser.dart`，纯函数；现有代码中没有集号/季号解析，只有 `rename_service.dart` 的 `Season NN` 目录正则）：集号（`- 01`、`E01`、`第01话`、`[01]`）、季号（`S2`、`Season 2`、`第二季`）、年份、分辨率、字幕组、语言标签、扩展名类别。
3. **分组**：去掉集号/分辨率/字幕组后的"系列键" + 父目录，得到若干组；字幕、图片、nfo 按基名关联到视频。

**模型只对"组"做判断（工具循环）：**

| 工具 | 权限 | 作用 |
|---|---|---|
| `list_groups(page)` | read | 组摘要：组 id、文件数、3 个样本文件名、解析出的集号范围与置信信号；分页 |
| `list_group_files(group_id, page)` | read | 组内文件名与解析结果；分页 |
| `read_existing_nfo(group_id)` | read | 组内已有 NFO 的标题/年份（复用 `NfoReader`） |
| `submit_group(group_id, decision)` | 草稿写 | `{mediaType, title, year?, season?, episodeOffset?, confidence, note}`；参数 schema 即输出 schema；校验失败返回下一步指引 |
| `split_group(group_id, file_ids, reason)` | 草稿写 | 分组算法错了时让模型拆组 |
| `mark_unsure(group_id, reason)` | 草稿写 | 无法判断 → 这些文件在预览中标为 needsReview |

**代码收尾**：按决定用 Jellyfin 规则函数生成每个文件的 `OrganizeAction`（沿用预览里已有的字幕跟随规则，`organize_preview_dialog.dart`），叠加用户历史覆盖（见 3.2 写回），进入现有 `OrganizePreviewDialog`。

效果：模型输出从 **O(文件数)** 降为 **O(组数)**；一部 26 集的番剧从 26 条 action 变成 1 次 `submit_group`。

**单发管线移除（D4）**：Agent 整理上线后删除 `AiPrompt` 的单发提示词、`batchEntries`、`OrganizePlan.fromAiJson` / `merge` 等仅服务于单发路径的代码及其测试。

#### 学习刮削规则
| 工具 | 作用 |
|---|---|
| `page_outline()` | 页面主要区块树（带节点 id、标签、class、文本长度），不含全文 |
| `query(selector)` | 匹配数 + 前 N 个节点的截断文本 |
| `inspect(node_id, page)` | 子树骨架分页 |
| `test_recipe(recipe)` | 运行 `RecipeApplier`，返回各字段抽取结果与**长度**（折叠/展开两份简介在这里一眼可见） |
| `submit_recipe(recipe)` | 提交，仍然只作为候选交给预览由用户决定是否保存 |

60 KB 骨架不再一次塞入；自检从"提交后才知道"变成模型可迭代。上线后删除 `RecipeLearner` 的单发提示词路径（D4）。

#### LLM 直接提取
`page_outline` / `read_section(node_id, page)` / `list_images(page)` / `submit_fields(partial)`（可多次提交、按字段合并）。图片仍然只能从 `list_images` 的编号里选。上线后删除单发 `DirectExtractor` 路径（D4）。

#### 连接测试与能力门槛（D4）
- 连接测试在 hello 之外增加**工具调用能力探测**：带一个无副作用的测试工具发请求，检查是否返回合法 `tool_calls`。
- 结果缓存到 profile（`supportsTools` + 探测时间）；endpoint / model 变化时清空，需要重新测试。
- `supportsTools != true` 时：设置页显示"此模型不支持工具调用，无法用于整理与刮削"；整理按钮与刮削面板的 LLM 相关按钮禁用并给出同样的原因。
- 从未测试过的 profile：首次运行 Agent 任务前自动探测一次。

### 2.2 Agent runtime（Dart 实现）

```
lib/services/agent/
  agent_runtime.dart      runAgent：轮循环、取消补桩、一次性提示撤回、trimHistory
  agent_preset.dart       TaskPreset { id, tools, maxRounds, finishPolicy }
  tool_registry.dart      enum ToolId；RegisteredTool { definition, access, execute }
  tool_context.dart       ToolContext：只放可选通道（工作区、取消、进度回调）
  agent_events.dart       sealed AgentEvent：round-start / tool-step / reasoning / truncated / done
lib/services/ai/
  （扩展）AiProvider.chat({messages, tools, toolChoice, cancelToken, onChunk})
```

- **Provider 层**：新增流式 `chat`，返回 text / toolCalls / reasoning / usage / finishReason。OpenAI SSE 的 `tool_calls` **按 index 累积**（id 也可能分片）；Gemini `functionCall` 整块到达、自造 id。采样参数与思考开关沿用阶段一的解析结果。
- **不变量**（逐条写单测）：本轮无工具调用即完成；每个工具调用前检查取消；取消时补桩后再抛；强制收尾轮撤工具 + 临时提示发出即撤；trimHistory 只替换旧工具结果的 content、保留消息壳；带 tool_calls 的 assistant 消息原样保存思考回传字段（`reasoning_content` 原名奉还）。
- **不依赖强制 `tool_choice`**：部分服务端在开启思考时只接受 `auto|none`。提交靠"无工具调用即完成 + 校验未提交的组"。
- **错误全部回给模型**：执行器不 throw，错误文本写成下一步指引（如"组 7 不存在，先调用 list_groups"）。
- **进度可见**：`AgentEvent` → `TaskService`，任务卡片显示"第 3/12 组"、已用 token、当前工具。
- **测试替身**：`ScriptedToolProvider`（按脚本返回 tool_calls / 文本），不依赖真实模型即可测完整循环。

**交付：PR 2（Provider 层 chat + tools + 能力探测与门槛）、PR 3（runtime + 注册表 + 事件）、PR 4（整理 Agent 化 + 文件名解析 + 移除单发整理）、PR 6（刮削 Agent 化 + 移除单发刮削）。**

---

## 阶段三：海量数据——中间结果缓存 + 分批（对应"第 3 步"）

### 3.1 分批驱动：每批一个短会话，而不是一个超长会话
外层由**代码**编排：每批 K 个组，开一个全新会话（system + 本批任务 + 全局约定摘要，共 2–3 条消息），跑工具循环直到本批组全部提交或标记；结果落盘；再开下一批。**上下文长度与文件总数无关**，本地模型窗口天然安全。

- K 由 `TokenBudget` + 探测/填写的上下文窗口计算；工具结果限幅（单次 ≤约 1,500 token，分页）。
- **全局一致性**：已确定的"约定表"（规范剧名、年份、根目录）作为每批 seed 注入，有预算上限；超出时提供 `find_decided(query)` 工具查询，而不是全部塞进上下文。
- trimHistory 作为批内兜底。

### 3.2 任务工作区（中间结果缓存）
```
<appSupport>/agent/
  tasks/<taskId>/
    task.json            机器状态：输入指纹、分组表、每组状态（pending/decided/unsure/failed）、token 用量
    decisions/<groupId>.json
    notes/               （刮削等任务的中间结论）
  overrides.json         用户在预览中的修改（跨任务，D3）
```
- **输入指纹** = 路径 + 大小 + mtime 的哈希。重新整理同一文件夹时，指纹未变的组**直接复用已缓存决定**；取消或失败后再次运行从断点继续。
- **写回（D3，已确认）**：
  - 用户在 `OrganizePreviewDialog` 中改过的目标路径（`OrganizeAction.userEdited`），在用户点击应用时写入 `overrides.json`，键为文件指纹。
  - 下次整理时，指纹命中的文件**直接使用用户的目标路径**（置信度 1、标记为用户修改），不再交给模型。
  - 若同一组内被修改的文件都指向同一个新的标题文件夹，同步更新该组的缓存决定（剧名/年份），使组内其余文件与后续新集保持一致。
  - 取消预览不写回（与"取消即不改动"的语义一致）。
- 写入串行化；损坏文件读取返回 null 按"未决定 / 无覆盖"处理，绝不因缓存损坏阻塞整理。
- 保留策略：任务目录与撤销清单一致，7 天或最多 20 个，已完成的优先清理；`overrides.json` 按条目最后使用时间清理（如 180 天）。

### 3.3 失败隔离与报告
- 单批失败自动重试 1 次；仍失败则该批的组标记 failed，其余批继续。
- 结束时按 CLAUDE.md 约定报告**计数**（成功 N 组 / 需人工 M 组 / 失败 K 组），失败组的文件在预览中以 needsReview 呈现。

**交付：PR 5（工作区 + 分批编排 + 断点续跑 + 预览写回）。**

---

## 交付顺序总览

| PR | 内容 | 依赖 | 用户可见变化 |
|---|---|---|---|
| 1 | 采样参数 + 模型预设（24 个家族）+ 思考开关（默认关，含生效验证）+ 版本 0.20.0+16 | — | 设置页采样参数区与思考开关；小模型更快更稳 |
| 2 | Provider 层流式 `chat` + 工具调用 + 能力探测与门槛 | — | 连接测试显示是否支持工具；不支持的模型无法运行 AI 任务 |
| 3 | Agent runtime + 注册表 + 事件 | 2 | 无 |
| 4 | 整理 Agent 化：文件名解析、分组、组级决策、任务进度；移除单发整理 | 3 | 整理大幅提速、进度可见 |
| 5 | 工作区缓存 + 分批编排 + 断点续跑 + 预览修改写回 | 4 | 海量文件夹可用、可续跑、记住用户修改 |
| 6 | 刮削规则学习 / 直接提取 Agent 化；移除单发刮削 | 3 | 刮削对小模型更可靠 |

每个 PR 都跑 CI 三件套（`dart format --set-exit-if-changed`、`flutter analyze --fatal-infos`、`flutter test`），并在 LM Studio 上做一次真实回归。

---

## 已确认决策

| # | 问题 | 决定 |
|---|---|---|
| D1 | 旧档案 `temperature: 0.2` 是否视为未自定义 | **是**，读取时视为未定义，跟随预设 |
| D2 | 思考模式 | **默认关闭**，用户在设置里手动打开才启用 |
| D3 | 预览中用户的修改是否回写缓存 | **写回**（按文件指纹；整组一致修改时同步更新组决定） |
| D4 | 模型不支持工具调用 | **直接不能运行**，不保留单发回退 |
| D5 | 版本 | PR 1 升至 **0.20.0+16** |

## 风险

- **~~LM Studio `/v1` 可能无法关闭思考~~（已实测解决）**：`reasoning_effort: "none"` 有效，模板开关与 `/no_think` 无效（1.6）。机制保持不变——逐个候选发、以响应里是否还有推理判定、按 endpoint + model 记住；万一某个版本三种都不行，仍如实提示用户去 LM Studio 的模型设置里关闭，不伪装成功。
- **微调版与基座行为不同**（`-uncensored` 等）：按基座家族匹配只是启发式；设置页显示匹配结果，用户可覆盖。
- **小模型工具调用格式不稳**（参数 JSON 非法、调用不存在的工具）：错误回给模型重试；同一批连续失败达阈值 → 该批标记 failed 并在任务卡片提示"模型工具调用不稳定，建议换模型或开启思考"。无单发回退（D4）。
- **分组算法误分**：提供 `split_group`；预览仍是最终闸门。
- **思考默认关闭后准确率下降**：由 1.6 实测量化；准确率明显下降的家族，在预设里标注建议开启思考。
- **思考模型的回传义务**：带 tool_calls 的 assistant 消息原样保存思考字段，避免个别服务端 400。
- **写回的覆盖值过期**：文件被外部重命名或内容变化 → 指纹不再命中，覆盖自然失效，不会误用。
- **LM Studio 模型自动卸载**：首次请求触发加载可能很慢，已由流式首事件 10 分钟超时覆盖；实测前需确认模型已加载。
- **预设数据的出处质量**：Gemma 3 / Llama 的值读自 unsloth 镜像（官方仓库需登录），未与原件逐字节比对；Qwen2.5 / Llama 仅有 gen_config 无正文推荐。
