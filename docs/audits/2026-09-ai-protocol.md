# AI 协议实现审查（2026-09-25）

审查对象：`lib/services/ai/` 的四个协议适配器、SSE 读取、重试、连接测试，以及
`lib/services/agent/agent_runtime.dart` 的工具循环，基线提交 `f6ee959`。
范围只含**文本与图片识别**（多模态输入）；出图、视频、语音识别不在本项目的能力里，不审。

依据：ai-agent-architecture 知识库（下文「KB」，引用写成 `篇 §节` 或 `坑 N`）。证据等级沿用 KB 的记法：

| 记法 | 含义 |
|---|---|
| 【实测 日期】 | KB 里真发过请求、看过响应的事实，可据此判错 |
| 【文档 日期】 | 官方文档口径，项目不一致时写「待核实」 |
| 【实现】 | 某个参考实现这样做，KB 没独立复核报文 |
| **已复现** | 本次审查用 `MockClient` 驱动本项目的真实 provider 代码跑出了现象（临时测试，已删除；复现方法写在各条里，修复时应落成正式测试） |

这是一份**记录**：它描述的是 `f6ee959` 时的代码。修复一条就在 [问题清单](#问题清单) 的「状态」列写上提交号，不改写正文——正文是修复的理由。
各条怎么修、按什么顺序提交，见配套的 [修复方案与执行计划](2026-09-ai-protocol-plan.md)；那里的方案对照代码后对本文的「建议」有四处细化，理由写在它的变更记录里。

---

## 结论

整体完成度高，KB 列出的大部分常见坑已经防住。已做对、修复时**不要回退**的部分：

- ③ 请求键一律 camelCase（坑 111）；key 走 `x-goog-api-key` 头，不走 `?key=`（02 §5）。
- ① 无 key 不发 `Authorization`；`/v1` 只补在纯域名上（02 §4–5）。
- ① `choices:[]` 的 usage 末块单独读（坑 108）；`content` 为 part 数组时也读（02 §3.2）；空串调用 id 按缺失处理（坑 106）；`base_resp` 与 SSE 体内 `error` 都当失败（坑 6）；`content_filter` / `sensitive` / `network_error` 抛错（06 §2）。
- ③ finishReason 走白名单，`MISSING_THOUGHT_SIGNATURE` 等请求缺陷不读成短答（06 §2 第 4 条）；思考 token 计入输出（06 §1）。
- ④ usage 三桶相加（坑 18）；未知类型的块整块留存（02 §3.2）；空参数工具调用得 `{}`。
- 回传物走 `ProviderTurn`，按协议 + 模型 id 绑定，换模型就重建（03 §5、坑 3）；DeepSeek 式 `reasoning_content` 只挂在带工具调用的轮次上（03 §5 规则 1）。
- ② `store:false`、工具显式 `strict:false`（02 §7.1）；没有 `encrypted_content` 的 reasoning 条目不回传。
- 每个工具调用都有配对结果，取消时补桩（05 §4）。
- 图片一律内联 base64 / data URL（02 §1 表后：整台中转站可移植的只有这一种）。

需要修的有 13 条，其中 7 条是**不会响**的（静默错误）。最该先修的是 [A1](#a1)：改动小，而且它把网络故障永久写成模型能力。

---

## 覆盖矩阵

✅ 已接 · ⚠ 部分 · ❌ 缺失 · — 不适用。格子里的编号指向下面的问题。

| 族 / 平台 | 请求与消息 | 流式 | 地址与鉴权 | 思考 | 结构化输出 | 工具 | 错误与 usage | 图片输入 |
|---|---|---|---|---|---|---|---|---|
| ① Chat Completions | ✅ | ⚠ A5 | ✅ | ⚠ A2 | ✅ 仅连接测试使用 | ⚠ A12 | ⚠ A1、A9 | ✅ |
| ② Responses | ⚠ A4 | ⚠ A11 | ✅ | ❌ A3 | ✅ | ✅ | ⚠ A1、A9；回显比对未做（06 §4.1） | ✅ |
| ③ Gemini | ✅ | ✅ | ⚠ A10 | ⚠ 待核实 V1 | ✅ | ✅ | ⚠ A1 | ✅ |
| ④ Anthropic | ✅ | ⚠ A11 | ⚠ A10 | ⚠ A6、A13 | — | ✅ | ⚠ A1 | ✅ |
| 智谱 ① | | | | ❌ A8 | | | | |
| 火山方舟 ① | | | | ❌ A2 | | | | |
| 全部 | 生成请求的重试 ⚠ A7 | | | | | | | |

---

## 问题清单

| # | 严重度 | 一句话 | 复现 | 状态 |
|---|---|---|---|---|
| [A1](#a1) | 1 静默 | 429 / 5xx / 401 / 402 被记成「模型不支持工具」并持久化 | 已复现 | `91bb83a` |
| [A2](#a2) | 1 静默 | 火山方舟 2.1 的 `encrypted_content` 不留存、不回传 | — | `1b72751` |
| [A3](#a3) | 1 静默 | ② 关思考不发任何字段，照想照计费 | — | `c8d6e12`、`097ccba` |
| [A4](#a4) | 1 静默 | ② 无 system 消息时不发 `instructions`，中转站注入数千 token | 已复现 | `f1d743e` |
| [A5](#a5) | 1 静默 | ① 同一 delta 两个推理字段都非空时拼接两遍 | 已复现 | `46e960b` |
| [A6](#a6) | 1 静默 | ④ 没有「关思考」字段，默认开思考的镜像关不掉 | — | `3d4edd4`、`097ccba` |
| [A7](#a7) | 1 静默 | 生成请求遇 504 / 408 会重发，可能重复计费 | — | `10f1d24` |
| [A8](#a8) | 2 会响 | 智谱 glm-5.3 每个请求都 400，且不学习 | 已复现 | `68a94a6`、`097ccba` |
| [A9](#a9) | 2 会响 | 400 学习只读 message，不读 `error.param` | 已复现（文案待核实） | `e048b26`、`097ccba` |
| [A10](#a10) | 2 会响 | 粘贴完整端点地址后路径拼错；错误信息不带 URL | 已复现 | `f1fc1a4` |
| [A11](#a11) | 2 会响 | 缺终止事件、坏 SSE 事件都让整条请求失败 | — | 乙 · `21b3070` |
| [A12](#a12) | 2 会响 | 背靠背拼接的多个 JSON 参数被判非法 | — | `ff77e74`、`097ccba` |
| [A13](#a13) | 4 结构 | ④ 思考固定 `enabled + budget_tokens`、不带 `display`；被拒后静默关思考 | — | `a42d0c5`、`097ccba` |

严重度按 KB 00 §4：1 静默错误（数据坏、钱算错、功能悄悄失效）> 2 会响的错误 > 3 宣称支持实际缺失 > 4 会让下次扩展出错的结构问题。

---

### A1

**429 / 5xx / 401 / 402 被记成「模型不支持工具」，并写进配置**

- 位置：四个适配器对非 2xx 状态一律抛普通 `AiException`——
  [openai_provider.dart:335](../../lib/services/ai/openai_provider.dart)、
  [openai_responses_provider.dart:210](../../lib/services/ai/openai_responses_provider.dart)、
  [anthropic_provider.dart:202](../../lib/services/ai/anthropic_provider.dart)、
  [google_genai_provider.dart:246](../../lib/services/ai/google_genai_provider.dart)。
  `AiConnectionCheck.probeTools`（[connection_check.dart:282](../../lib/services/ai/connection_check.dart)）把任何 `AiException` 判为 `ToolProbe.unsupported`，
  `AiService.ensureTools`（[ai_service.dart:164](../../lib/services/ai/ai_service.dart)）经 `onToolSupport` 写进配置。
- 依据：06 §3「被限流的请求绝不能被记录成证据」；坑 112（402 欠费）【实测 2026-09-05】。
- 现象：一个从没测过的模型第一次跑整理时撞上 503 或 429：`withRetry` 重试 3 次后返回该状态，provider 抛 `AiException`，
  探测判 `unsupported`，整理按钮与刮削面板的 LLM 按钮从此禁用，提示「This model does not call tools」，直到用户手动重跑连接测试。
  401（key 错）、402（欠费）、403 同样。`ai_provider.dart:131` 的注释说限流、欠费属于 `AiNetworkException`，代码里没有这条映射。
- 为什么测试没抓到：`chat_tools_test.dart` 的「a transport failure is inconclusive」用的假 provider 直接抛 `AiNetworkException`，没经过真实适配器的状态码路径。
- 复现：`OpenAiProvider` + `MockClient` 恒回 `503 {"error":{"message":"busy"}}`，调 `AiConnectionCheck.probeTools` → `ToolProbe.unsupported`，共发 3 次请求。429 相同。
- 建议：
  1. 适配器把 401 / 402 / 403 / 408 / 429 / 5xx 抛成 `AiNetworkException`（或带 `statusCode` 的异常，由探测按码判定）；
  2. `probeTools` 只把「400 / 404 / 422 且文案点名 tool / function」和「两次都用散文回答」当定论（与 `refusesTools` 同一判据）；
  3. 测试：真实适配器 + `MockClient`，分别回 429、503、401、402，断言 `inconclusive` 且 `onToolSupport` 没被调用。

### A2

**火山方舟豆包 2.1 的 `encrypted_content` 不留存、不回传**

- 位置：流解析只读 `reasoning_content` / `reasoning`（[openai_provider.dart:656](../../lib/services/ai/openai_provider.dart)）；回传只写这两个字段（[openai_provider.dart:519](../../lib/services/ai/openai_provider.dart)）；非流式同（`_parseCompletion`）。
- 依据：03 §3.2「思考摘要与加密原文」、坑 133【文档 2026-09；实测 2026-09-23】。
- 现象：2.1 系（及 2.0-lite-260428 起）的 `reasoning_content` 只是**摘要**，原始思维链加密在 `delta.encrypted_content`（整串落在某一个 delta 上）。
  只回摘要不报错，模型改在摘要上推理，厂商原话「推理效果下降」。功能用例照样全过。项目的 `volcengine` 平台配置正好走 ① 路线。
- 建议：流解析把 `encrypted_content` 按到达顺序拼接留存，不显示；工具轮的 assistant 消息把它与 `reasoning_content` 一起回传（摘要为空时只回密文）；
  载体与 `ProviderTurn` 同一约定，绑定产出它的模型 id，换模型剥离。`ReasoningPassback` 需要加一个可选的密文字段，或改走 `ProviderTurn`。

### A3

**② Responses 关思考时不发任何字段，GPT-5.5/5.6 默认 `medium`、Grok 默认 `high`，照想照计费**

- 位置：[openai_responses_provider.dart:258](../../lib/services/ai/openai_responses_provider.dart)——只在 `thinkingEnabled` 时发 `reasoning:{effort:"medium"}`，关时什么都不发。
- 依据：03 §7.1【实测 2026-09】：off → `reasoning:{effort:"none"}`；各模型默认值不同（5.4 `none`，5.5/5.6 `medium`，Grok 4.5/4.6 `high`）。
- 现象：「思考默认关」在这条路线上不成立。连接测试的 `reasoned` 会显示模型在思考，但 `thinkingOffPending` 从不置位，也没有下一种关法可试，用户只看到「关不掉」。
- 代码注释的理由（「none、minimal、low 各在某处被拒」）是真的，但拒绝是会响的 400，已有的「按名字学习被拒字段」机制接得住。
- 建议：关时发 `reasoning:{effort:"none"}`；被 400 点名 `reasoning` 时照现有机制去掉并记住（Grok 4.5/4.6 会走这条，它们本来就关不掉）。
  经中转站的 GPT 会把 `none` 改写成 `medium`（03 §7.4【实测 2026-09-24】）——代码救不了，写进说明；将来做回显比对（06 §4.1）时能报出来。

### A4

**② 无 system 消息时不发 `instructions`，中转站会自己注入几千 token 的系统提示**

- 位置：[openai_responses_provider.dart:267](../../lib/services/ai/openai_responses_provider.dart) `if (instructions.isNotEmpty) 'instructions': …`。
  触发点：识帧请求 [frame_vision.dart:50](../../lib/services/ai/frame_vision.dart) 只有一条 `UserMessage`。
- 依据：02 §7.1 规则 2【实测 2026-09】：中转站发现 `instructions` 缺失会注入自己的系统提示，一次 4.4K–9K token。
- 现象：每次识帧多付几千输入 token，且注入的提示会改变模型的回答方式。
- 复现：`OpenAiResponsesProvider.previewRequest(messages: [UserMessage('frames')])` → body 不含 `instructions` 键。
- 建议：`instructions` 恒发，没有 system 消息时发空串；测试钉住「无 system 消息时 body 仍有 `instructions: ""`」。

### A5

**① 同一个 delta 里 `reasoning_content` 与 `reasoning` 都非空时，两段都拼进推理文本**

- 位置：[openai_provider.dart:658](../../lib/services/ai/openai_provider.dart) 对 `_reasoningFields` 逐个写入，没有在第一个非空处停下。
- 依据：03 §4、坑 107【实测 2026-09-14】：按候选表逐个试，取**第一个非空字符串**连同字段名。
- 复现：SSE 一帧 `{"delta":{"reasoning_content":"abc","reasoning":"abc"}}` 加一个工具调用 → 回传的 `ReasoningPassback` 是 `(field: reasoning_content, text: abcabc)`。
- 影响：回传文本翻倍，多付 token，模型读到重复的推理。哪些服务端会两个字段同时填非空，KB 未记录——触发面**待核实**，但写法与 KB 规则不符，修复代价很小。
- 建议：每个 delta 里取第一个非空字段后 `break`；测试钉住上面的复现。

### A6

**④ 路线没有「关思考」字段：默认开思考的 Anthropic 形镜像关不掉**

- 位置：[anthropic_provider.dart:263](../../lib/services/ai/anthropic_provider.dart) 关时不发 `thinking`；`RouteSpec.thinkingDialect` 只有 ① 适配器读，④ 路线（[platform_profiles.dart:138–229](../../lib/services/ai/platform_profiles.dart) 里 DeepSeek、百炼、智谱、MiniMax 的 ④）无处声明。
- 依据：03 §3.2【实测 2026-09-18】：火山方舟 ④ 默认在想，「Claude 式的 enabled / 什么都不发 = 关不掉」，要一个 `adaptive / disabled` 开关类目。
  反例：MiniMax-M3 的 ④ 默认关、glm-4.7 的 ④ 默认不想（03 §3、§3.1）——所以这件事必须按路线声明，不能对 ④ 一刀切发 `disabled`（官方 Claude 上 `disabled` 会被部分模型 400，03 §2）。
- 范围：内置配置里没有火山的 ④；经 relay / custom 能接到。百炼、DeepSeek 的 ④ 默认值 KB 未覆盖，**待核实**。
- 建议：让 ④ 适配器读路线的 `thinkingDialect`，声明了开关方言的路线关时发 `thinking:{type:"disabled"}`；未声明的路线保持字节不变。

### A7

**生成请求遇 504 / 408 会重发，上游可能还在跑第一次**

- 位置：[ai_http.dart:23](../../lib/services/ai/ai_http.dart) `_retryableStatuses = {408, 429, 502, 503, 504, 529}`，生成请求也走这张表（`retryTimeouts:false` 只管客户端超时）。
- 依据：06 §3「主聊天路径不重试」【实现】；本项目 CLAUDE.md：「a timed-out generation is never retried (the server is still running it)」。
- 现象：504 是网关等上游超时，408 是请求超时——两者都意味着上游可能仍在生成、仍在计费。重发等于再开一次同样的生成。
- 建议：生成类 POST 只对 429 / 502 / 503 / 529 重试；探测类请求可以保留全表。

### A8

**智谱 glm-5.3 系列：每个请求都 400，而且不会学习**

- 位置：智谱 ① 路线声明 `ThinkingDialect.thinkingType`（[platform_profiles.dart:174](../../lib/services/ai/platform_profiles.dart)），思考关时恒发 `thinking:{type:"disabled"}`；
  `_namesField`（[openai_provider.dart:550](../../lib/services/ai/openai_provider.dart)）要求文案里出现 `thinking` 才算点名。
- 依据：03 §3.1、坑 94【实测 2026-09-19】：5.3 代关不掉思考，`disabled` 回 400，文案是「该模型始终思考，不支持关闭思考」，不含字段名。
- 现象：思考默认关，所以 glm-5.3 / 5.3-flash / 5.3-flashx 在默认设置下完全不可用，每个请求一次 400 后直接失败。
- 复现：`platform: 'zhipu'`、模型 `glm-5.3`，`MockClient` 回 400 `{"error":{"code":"1210","message":"该模型始终思考，不支持关闭思考"}}` → 只发 1 次请求，抛 `HTTP 400: 该模型始终思考，不支持关闭思考`。
- 建议：发了 dialect 字段且思考为关时遇到 400，去掉该字段重试一次并记住（与 `rejectedFields` 同一机制）；或者把「始终思考 / 不支持关闭」这类措辞加进识别。
  注意 KB 06 §2：智谱这句文案**覆盖 5.3 代所有非法思考参数**，所以识别它时只动思考字段，不做别的推断。

### A9

**400 学习只读错误 message，不读 `error.param`**

- 位置：[ai_http.dart:121](../../lib/services/ai/ai_http.dart) `describeError` 只取 `error.message`；三处学习逻辑都在这个字符串上找字段名。② 恒发 `include:["reasoning.encrypted_content"]`（[openai_responses_provider.dart:259](../../lib/services/ai/openai_responses_provider.dart)）。
- 现象：OpenAI 系的 400 把出错字段放在结构化的 `param` 里，message 未必提它的名字。用「非推理模型拒收 `include`」的文案复现（`message: "Encrypted content is not supported with this model."`, `param: "include"`）：只发 1 次，直接失败，不学习——该路线上每个请求都会失败。
- 证据：这条文案 KB 未收录，**待核实**（验证：官方 key 对 `gpt-4.1` 发一次带 `include` 的 ② 请求，零输出成本）。结构问题本身不依赖这条文案：`param` 是比子串匹配更可靠的判据。
- 建议：`describeError` 同时返回 `param`；学习时 `param` 命中可选字段优先，子串匹配作后备。

### A10

**粘贴完整端点地址后路径拼错；错误信息不带实际 URL**

- 位置：④ [anthropic_provider.dart:66](../../lib/services/ai/anthropic_provider.dart) 只认「以 `/v1` 结尾」；③ [google_genai_provider.dart:93](../../lib/services/ai/google_genai_provider.dart) 只认「含 `/v1`」，不剥末尾 `/models`。
- 依据：02 §4、坑 16：`anthropicRoot` 先剥 `/messages` 再剥 `/v1`，接受根地址、根+`/v1`、完整 curl 端点三种形状；③ 剥末尾 `/models`。06 §2：错误信息一律带实际请求的 URL。
- 复现：endpoint `https://api.anthropic.com/v1/messages` → 请求打到 `https://api.anthropic.com/v1/messages/v1/messages`。
- 现象：404，而 `describeError` 只给 `HTTP 404`，用户看不到拼出来的地址。
- 建议：④ 先剥 `/messages`、③ 先剥 `/models` 再按现有规则；非 2xx 错误附上去掉查询串的请求 URL（`ApiLog` 已有去查询串的写法）。

### A11

**缺终止事件、坏 SSE 事件都让整条请求失败**

- 位置：② [openai_responses_provider.dart:389](../../lib/services/ai/openai_responses_provider.dart)、④ [anthropic_provider.dart:428](../../lib/services/ai/anthropic_provider.dart) 没有 `response.completed` / `message_stop` 就抛错；
  [sse.dart:65](../../lib/services/ai/sse.dart) 与 ③ 的 `_events` 遇到解析不了的 `data:` 就抛错（① 的 `_read` 反而跳过坏行）。
- 依据：02 §3.1、§7.2【实现】：坏行忽略；流可能不带终止事件就结束，flush 后照常收尾，代价是 usage 记 0、结束原因缺失。
- 分析：项目有意取更严的立场（注释：被丢的那一帧可能正是工具调用或终止事件），这是会响的错误，不是静默的。代价是遇到这类中转站时**每次**都失败，而不是偶尔少一段。
- 状态「待决定」：可选的折中是——已收到完整的 `output_item.done` / `content_block_stop`（且有工具调用或文本）时照常收尾并标 `finishReason: null`，只有什么都没收到时才抛错；① 与 ② ③ ④ 对坏行的处理统一成一种。

### A12

**背靠背拼接的多个 JSON 参数被判非法**

- 位置：`ToolCall.decodedArguments`（[chat.dart:137](../../lib/services/ai/chat.dart)）对 `{}{"id":1}` 返回 null，`AgentRuntime` 回给模型「arguments were not a JSON object」。
- 依据：05 §3、坑 105【实测 2026-08-08，经中转的 Claude 后端】：先吐一个空对象占位，再给真参数。
- 现象：比 KB 描述的情形好（不是以空参数静默执行），但中转站每轮都这样发时，连续三轮失败就以 `erratic` 结束，用户看到的是「模型不会用工具」。
- 建议：解析失败时按括号深度（跳过字符串内的括号与转义）切出顶层对象，左到右合并；切不出两个以上对象才判非法。测试钉住 `{}{"id":1}` → `{"id":1}`。

### A13

**④ 思考固定写成 `enabled + budget_tokens`、不带 `display`；被拒后静默关思考**

- 位置：[anthropic_provider.dart:263](../../lib/services/ai/anthropic_provider.dart)；`refusesThinking`（[:227](../../lib/services/ai/anthropic_provider.dart)）命中后把 `thinking` 记进 `rejectedFields`（`ai_learned.json`，30 天）。
- 依据：03 §3【文档】：Claude 4.6+ 用 `adaptive`，`extended`（`enabled + budget_tokens`）属于 ≤4.5；两者都要显式发 `display:"summarized"`，当前代默认 `omitted`（坑 4：省延迟不省钱）。MiniMax-M3 的 ④ 只收 `adaptive | disabled`（03 §3 `switch`）。
- 现象：
  - `display` 缺失对本应用影响小：不显示思考文本，`reasoned` 按块类型判断不受影响，回传的签名照样在。
  - 风险在另一头：某端点若拒收 `enabled`，这条路线的 `thinking` 被记成被拒，用户打开的思考就此静默失效 30 天，直到重跑连接测试。
- 建议：与 A6 一起做——④ 路线的思考写法按路线 / 模型声明（`adaptive` / `extended` / 开关），不从一个固定写法猜；`adaptive` 与 `extended` 都带 `display:"summarized"`。

---

## 待核实

KB 证据不足或未覆盖，不据此判错；列出最便宜的验证方法。

| # | 问题 | 验证 |
|---|---|---|
| V1 | ③ 关思考发的是 `thinkingLevel: "low"`（小写，[google_genai_provider.dart:327](../../lib/services/ai/google_genai_provider.dart)），KB 03 §2 写的是全大写 `LOW`。若被拒，阶梯会一路退到不发 `thinkingConfig`，即默认最高档 | 对 gemini-3 发一次小写、一次大写，看是否 400、`thoughtsTokenCount` 是否相同 |
| V2 | `repeat_penalty` 是 llama.cpp / LM Studio 的名字，vLLM 叫 `repetition_penalty`。Qwen2.5 预设带非中性值 1.05 / 1.1，在 vLLM 上可能被静默忽略 | 对 vLLM 发 `repeat_penalty: 2.0` 与 `repetition_penalty: 2.0` 各一次，比输出 |
| V3 | MiniMax ① 的多轮工具调用是否要求把 `<think>` 内容原样回传（项目把它切掉了，KB 03 §6 的规则是不回传） | 查 MiniMax 文档的 interleaved thinking 一节，再用两轮工具调用对比 |
| V4 | 百炼、DeepSeek 的 ④ 面默认开不开思考（决定 A6 的实际范围） | 不带 `thinking` 发一次，看有没有 thinking 块 |
| V5 | A9 用到的 OpenAI 文案 | 见 A9 |

## 项目里有、KB 没有的事实（供写回 KB）

均为【实现】——代码注释或测试里记录，KB 未收录：

- LM Studio 拒收 `response_format: json_object`：`'response_format.type' must be 'json_schema' or 'text'`，且错误体是裸字符串 `{"error": "…"}`；vLLM 的错误体是 `{"message": …}`，FastAPI 系是 `{"detail": …}`（`ai_http.dart`、`openai_provider.dart`）。
- OpenRouter 在第一个事件之前发 `: OPENROUTER PROCESSING` 保活注释（`sse.dart`）。
- Ollama 的 `/v1` 不把 `chat_template_kwargs` 传给模板；缺 `temperature` / `top_p` 时强制 1.0。llama.cpp 默认 `min_p 0.05`（`openai_provider.dart`）。
- 智谱对 `chat_template_kwargs` 照收不读（`thinking_dialect.dart`）。
- Qwen3 Thinking-2507 会省略开头的 `<think>`，只留 `</think>`；Gemma 4 靠 system prompt 开头的 `<|think|>` 开启思考；gpt-oss 关不掉思考，最低 `low`（`openai_provider.dart`）。

---

## 修复顺序建议

1. **A1**——小改动，止住「一次网络抖动 = 整理按钮永久禁用」。
2. **A8、A4、A3**——各是一处条件，默认设置下就会踩到。
3. **A2、A6 + A13**——需要扩展回传载体与 ④ 的路线声明，一起设计。
4. **A5、A7、A9、A10、A12**——小而独立，可以各自一个提交。
5. **A11**——先决定立场再改。

每条修复都在 `test/` 的镜像路径下加一个经过**真实适配器**的测试（复现写法见各条），并在上面的清单里填状态。
