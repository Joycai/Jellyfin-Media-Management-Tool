# AI 协议修复方案与执行计划（2026-09）

对应审查：[2026-09-ai-protocol.md](2026-09-ai-protocol.md)（下文「审查」，问题编号 A1–A13、V1–V5 沿用它的）。
基线提交 `f6ee959`；下文的 `文件:行` 都指这个提交。

审查是**记录**，这份是**计划**：
- 执行中发现方案不对，就在这里改，并在文末 [变更记录](#变更记录) 写一行。
- 进度不记在这里。每修完一条，在审查的「状态」列填提交号。

KB 引用写法同审查：`篇 §节`、`坑 N`。证据等级沿用 KB 的记法。

---

## 目录

- [总览：提交序列](#总览提交序列)
- [通用约定](#通用约定)
- 各步方案：
  - [第 1 步 · A1](#第-1-步--a1失败的请求不是工具能力的结论)
  - [第 2 步 · A8](#第-2-步--a8学会模型关不掉思考)
  - [第 3 步 · A4](#第-3-步--a4responses-恒发-instructions)
  - [第 4 步 · A3](#第-4-步--a3responses-关思考时发-effort-none)
  - [第 5 步 · A2](#第-5-步--a2回传火山方舟的-encrypted_content)
  - [第 6 步 · A13](#第-6-步--a13messages-的思考写法按模型形态带回退)
  - [第 7 步 · A6](#第-7-步--a6messages-路线可声明思考开关)
  - [第 8–12 步 · A5 A7 A9 A10 A12](#第-812-步小而独立的五条)
  - [第 13 步 · A11（选乙）](#第-13-步--a11选乙)
- [待核实项：验证后怎么动](#待核实项验证后怎么动)
- [写回 KB（不改代码）](#写回-kb不改代码)
- [验收清单](#验收清单)
- [变更记录](#变更记录)

---

## 总览：提交序列

13 步，每步一个提交；5 个 PR，按顺序合并。

| 步 | 问题 | 提交标题（草案） | 主要改动 | 测试文件 | 同提交要改的规则文档 | 依赖 |
|---|---|---|---|---|---|---|
| 1 | A1 | `fix(ai): a failed request is never a verdict on tools` | `ai_http.dart`、四个适配器的非 2xx 分支、`connection_check.dart` | 新 `ai_http_test.dart`、`connection_check_test.dart` | CLAUDE.md「three outcomes」一句；organize-pipeline.md §probe | — |
| 2 | A8 | `fix(ai): learn when a model cannot turn reasoning off` | `openai_provider.dart`、`ai_capability_matrix.dart`、两份 ARB | `openai_provider_test.dart`、`ai_capability_matrix_test.dart` | organize-pipeline.md「Reasoning is off by default」段 | — |
| 3 | A4 | `fix(ai): always send Responses instructions` | `openai_responses_provider.dart` | `openai_responses_provider_test.dart` | 无（文档本来就这么写，代码对齐文档） | — |
| 4 | A3 | `fix(ai): ask the Responses API for no reasoning` | `openai_responses_provider.dart`、`ai_capability_matrix.dart`、两份 ARB | 同上、`ai_capability_matrix_test.dart` | organize-pipeline.md §Channels「One exception…」整句重写 | 3 |
| 5 | A2 | `fix(ai): pass back Volcengine's encrypted reasoning` | `chat.dart`、`openai_provider.dart`、`agent_runtime.dart`（估算） | `openai_provider_test.dart`、`chat_tools_test.dart`、`agent_runtime_test.dart` | organize-pipeline.md「Pass-back is one carrier」 | — |
| 6 | A13 | `fix(ai): Messages thinking in the model's own form` | `anthropic_provider.dart`、`thinking_dialect.dart`、`ai_diagnostics_page.dart`、两份 ARB | `anthropic_provider_test.dart`、`ai_diagnostics_page_test.dart` | organize-pipeline.md §Channels 的 Anthropic 句 | — |
| 7 | A6 | `feat(ai): a Messages route can declare a thinking switch` | `platform_profiles.dart`、`anthropic_provider.dart`、`ai_capability_matrix.dart` | `anthropic_provider_test.dart`、`platform_profiles_test.dart`、`ai_capability_matrix_test.dart` | 同上 | 6 |
| 8 | A5 | `fix(ai): one reasoning field per delta` | `openai_provider.dart` | `openai_provider_test.dart` | — | — |
| 9 | A7 | `fix(ai): never resend a generation after 408 or 504` | `ai_http.dart` | `ai_http_test.dart` | CLAUDE.md「a timed-out generation is never retried」一句 | 1（同一测试文件） |
| 10 | A9 | `fix(ai): learn a refused field from error.param` | `ai_http.dart`、`openai_provider.dart`、`openai_responses_provider.dart` | `ai_http_test.dart`、两个适配器测试 | — | 1 |
| 11 | A10 | `fix(ai): accept a full Messages/Gemini endpoint URL` | `anthropic_provider.dart`、`google_genai_provider.dart`、`ai_http.dart`、`api_log.dart` | 两个适配器测试、`ai_http_test.dart` | CLAUDE.md「/v1 is appended only…」补一句 | 1 |
| 12 | A12 | `fix(ai): read back-to-back JSON tool arguments` | `chat.dart`、`openai_provider.dart` | 新 `chat_test.dart`、`openai_provider_test.dart` | — | — |
| 13 | A11 | `fix(ai): finish a stream whose items all arrived whole` | `sse.dart`、`openai_responses_provider.dart`、`anthropic_provider.dart`、`google_genai_provider.dart` | `sse_test.dart` 等 | organize-pipeline.md §Channels「fails on a malformed event」 | — |

PR 划分：

| PR | 步 | 主题 | 为什么这样分 |
|---|---|---|---|
| PR-1 | 1 | 止住「一次网络抖动 = 整理按钮永久禁用」 | 最急，改动最小，单独能合 |
| PR-2 | 2、3、4 | 默认设置下就会踩到的三处 | 都是一处条件，都在 ① / ② 的请求构造 |
| PR-3 | 5、6、7 | 回传载体与 ④ 的思考声明 | 需要一起评审的结构改动 |
| PR-4 | 8–12 | 小而独立 | 各自一个提交，可以任意顺序 |
| PR-5 | 13 | SSE 容错立场 | 已定：乙 |

---

## 通用约定

适用于每一步：

1. **测试走真实适配器。**
   - 用 `MockClient`（`package:http/testing.dart`）驱动真实的 provider，不用假 provider 直接抛异常。审查的 A1 就是因为测试绕过了真实的状态码路径才漏掉的。
   - 每步的「测试」小节写的是**必须新增**的用例。改动过的现有断言单独列出。
2. **重试不睡觉。**
   - `AiHttp.withRetry` 的退避是真实的 `Future.delayed`（首次 500 ms）。
   - 模拟 429 / 5xx 时，在响应头带上 `retry-after: 0`，`_retryAfter` 就会给 0 秒，测试不会多等 1.5 秒。
3. **先让测试失败。**
   - 每条新测试先在未修改的代码上跑一次，确认它失败，并且失败的原因正是审查描述的现象，然后再改代码。
   - 这一步的目的是验证测试确实钉住了问题（见记忆 subagent-review-loops：要对测试做变异检验）。
4. **规则变了，同提交改文档。** CLAUDE.md 的一句话规则与 `docs/architecture/organize-pipeline.md` 的长文一起改（CLAUDE.md 开头的约定）。上表「同提交要改的规则文档」列出了每步涉及的地方。
5. **`ai_learned.json` 不升版本。**
   - 新学到的东西只往现有的两个集合里加新名字：`thinkingOffTried` 和 `rejectedFields`。
   - 旧版本读到不认识的名字会忽略：`rejected.contains(key)` 只按请求字段名匹配，不认识的名字匹配不到任何字段。所以文件可以双向兼容。
   - 本计划新增的名字：

     | 名字 | 所在集合 | 哪条路线 | 哪一步 |
     |---|---|---|---|
     | `dialect` | `thinkingOffTried` | ① | 第 2 步 |
     | `effortNone` | `thinkingOffTried` | ② | 第 4 步 |
     | `thinking:adaptive`、`thinking:enabled` | `rejectedFields` | ④ | 第 6 步 |

   - 路线键里带协议，所以 ② 的 `effortNone` 和 ① 阶梯里同名的那一项不会互相串。
6. **提交前三件套：** `dart format .`、`flutter analyze --fatal-infos`、`flutter test`。
7. **新用户文案两份 ARB 都加**，并跑 `flutter gen-l10n`。本计划新增的键：

   | 键 | 哪一步 |
   |---|---|
   | `aiCellAlwaysReasons` | 第 2 步 |
   | `aiCellProtocolSwitch` | 第 4 步 |
   | `aiStepThinkingOn`、`aiStepThinkingNotOn` | 第 6 步 |

8. **修完填状态。** 在审查的问题清单里，把「未修」改成提交号。审查正文不动。

---

## 第 1 步 · A1：失败的请求不是工具能力的结论

**现状**
- 四个适配器对非 2xx 一律 `throw AiException(error)`：
  [openai_provider.dart:335](../../lib/services/ai/openai_provider.dart)、
  [openai_responses_provider.dart:210](../../lib/services/ai/openai_responses_provider.dart)、
  [anthropic_provider.dart:202](../../lib/services/ai/anthropic_provider.dart)、
  [google_genai_provider.dart:246](../../lib/services/ai/google_genai_provider.dart)。
- `probeTools` 在 [connection_check.dart:282](../../lib/services/ai/connection_check.dart) 把任何非网络的 `AiException` 都判成 `unsupported`。
- 同一文件里，`run()`（:157）已经用 `refusesTools` 区分「拒收工具」和「别的失败」，`probeTools` 没用。两处判据不一致，就是这个 bug 的根。

**方案：两处都改，各管一层**

1. **判据**（真正修 bug 的一处）。`probeTools` 的 `on AiException catch (e)` 分支改成与 `run()` 同一判据：

   ```dart
   } on AiException catch (e) {
     // Only a 400/422 that names tools answers the question; a 404, a
     // model still loading, an account problem does not.
     if (refusesTools(e.message)) {
       return (outcome: ToolProbe.unsupported, error: e.message);
     }
     lastError = e.message;
     break; // Asking again gets the same answer.
   }
   ```

   - `break`：非网络、又不是拒收工具的错误（404 模型名错、400 别的字段），第二次问答案也一样，不必再花一次请求。
   - 「两次都用散文回答 → `unsupported`」保持不变（`lastError == null` 分支）。
2. **分类**（让异常类型说实话）。`AiHttp` 增加一个构造函数：

   ```dart
   /// The exception for a non-2xx reply. Auth, billing, rate limits and the
   /// server's own failures settle nothing about the model, so they are
   /// [AiNetworkException]s; anything else is the request being refused.
   static AiException statusError(int status, String message) =>
       status == 401 || status == 402 || status == 403 ||
               status == 408 || status == 429 || status >= 500
           ? AiNetworkException(message)
           : AiException(message);
   ```

   - 四个适配器的那一行改成 `throw AiHttp.statusError(res.statusCode, error);`。
   - 同时更新 `AiNetworkException` 的文档注释（[ai_provider.dart:131](../../lib/services/ai/ai_provider.dart)），把 key 无效 / 无权限也写进「settles nothing about the model」。

**为什么两处都要**
- 只改 1：探测修好了，但 `AiNetworkException` 的语义仍是「网络」，别处将来按类型判断时会再踩一次。
- 只改 2：404 和「400 但与工具无关」仍会被探测判成 `unsupported`。

**影响面**
- 已确认只有 `connection_check.dart` 在 catch `AiNetworkException`，:155 和 :278 两处。
- `run()` 里 401 / 503 原本就会走 rethrow，行为不变。
- `ensureTools` 拿到 `inconclusive` 后抛 `AiNetworkException(probe.error)`，UI 显示的是真实原因，比如 `HTTP 402: 余额不足`，不再是「This model does not call tools」。

**测试**
- `connection_check_test.dart` 新增 group「probeTools through a real adapter」：
  - `OpenAiProvider` + `MockClient`，状态码分别取 429、503、401、402，响应头带 `retry-after: 0` → 结果为 `inconclusive`，`error` 以 `HTTP <码>` 开头。
  - 400 `{"error":{"message":"tools is not supported for this model"}}` → `unsupported`。
  - 404 `model not found` → `inconclusive`，并且只发 1 次请求（钉住 `break`）。
  - 用 `AnthropicProvider` 回 529 → `inconclusive`（覆盖第二个适配器）。
- 新建 `test/services/ai/ai_http_test.dart`（`lib/services/ai/ai_http.dart` 的镜像路径），加一张表测 `statusError`：
  - 400、404、422 → `AiException`，且**不是** `AiNetworkException`。
  - 401、402、403、408、429、500、503、529 → `AiNetworkException`。
- 现有 `chat_tools_test.dart:362`「a transport failure is inconclusive」保留，它测的是 `ensureTools` 不记录结论的那一半。

**文档**
- CLAUDE.md 的「The probe has **three** outcomes — a transport failure is `inconclusive`…」改成：
  「transport failure, an account or rate-limit status, or a server error is `inconclusive`; only a 400/422 naming tools, or prose twice, is `unsupported`」。
- organize-pipeline.md 第 42 行那段同步改。

**回退风险**
- 很低。唯一的行为变化是：以前错判成 `unsupported` 的情况，现在变成报错。
- 如果某个服务端拒收工具时回的是 404、而且文案点名 tool，`refusesTools` 要求 400/422，会判成 `inconclusive`。代价是用户看到原始错误，不会写错配置，可以接受。

---

## 第 2 步 · A8：学会「模型关不掉思考」

**现状**
- 智谱 ① 路线声明了 `ThinkingDialect.thinkingType`（[platform_profiles.dart:174](../../lib/services/ai/platform_profiles.dart)）。思考关时，`_compose` 恒发 `thinking:{type:"disabled"}`（[openai_provider.dart:372–387](../../lib/services/ai/openai_provider.dart)）。
- 400 分支靠 `_namesField(detail, 'thinking')` 识别（:550），它要求文案里出现 `thinking` 这个词。
- glm-5.3 的文案是「该模型始终思考，不支持关闭思考」（03 §3.1 表，【实测 2026-09-19】），不含字段名，所以直接抛错，而且每个请求都这样。

**方案**
1. 新增判据：

   ```dart
   /// A refusal to stop reasoning that does not name the field — Zhipu's
   /// 5.3 generation answers every thinking parameter it will not take with
   /// "该模型始终思考，不支持关闭思考" (03 §3.1).
   static bool _refusesThinkingOff(String detail) => RegExp(
     '始终思考|不支持关闭|无法关闭|不能关闭|'
     'cannot be (disabled|turned off)|always (thinks|reasons)',
   ).hasMatch(detail);
   ```

   - 故意**不含** `mandatory`：这个词在「messages is mandatory」一类无关文案里也会出现。现有 `_namesField` 里用它时，要求文案同时点名字段，这里不点名，所以不能用。
   - KB 06 §2 提醒过：智谱这句文案覆盖 5.3 代**所有**非法思考参数。所以命中后只动思考字段，不做别的推断。
2. 记在 `thinkingOffTried`，**不记在** `rejectedFields`：
   - 在 `_exchange` 的 400/422 分支里、`refused` 查找之后插入（放在之前，「thinking cannot be disabled」这类点名字段的文案会被它截走，违反下面第 3 点）：

     ```dart
     if (dialectOff && _refusesThinkingOff(detail)) {
       learn((b) => b.copyWith(
         thinkingOffTried: {...b.thinkingOffTried, LearnedBehaviour.dialectOff},
       ));
       continue;
     }
     ```

   - `dialectOff` 表示这次请求带了方言的「关」字段：方言不为空，且 `!sampling.thinking`，且 `thinkingOffTried` 里还没有 `'dialect'`。
   - `LearnedBehaviour.dialectOff = 'dialect'`。阶梯项没有叫这个名字的；但路线键里没有平台，改过平台的渠道会同时留着两种记录，所以能力矩阵数阶梯步数时不算它。
   - 为什么不放进 `rejectedFields`：放进去之后，用户打开思考时，`thinking:{type:"enabled"}` 也会被剥掉。对 5.3 无害（它反正始终在想），但对「偶尔 400 的其他模型」就是静默关思考，正是 A13 那一类错误。
   - `_compose` 增加参数 `bool dialectOffRefused`：为 true 且思考关时，不放 `dialectField`；思考开时照发。
   - `previewRequest`（:431）也要传这个参数，保证预览与实际请求一致。
3. 已有路径不变：文案**点名**了字段（`"thinking" is mandatory`），仍由 `_namesField` 处理、记进 `rejectedFields`。这是现有行为，不在本步范围。

**能力矩阵**
- 在 [ai_capability_matrix.dart:299](../../lib/widgets/settings/ai_capability_matrix.dart) 的 dialect 分支前加一个判断：`learned?.thinkingOffTried.contains('dialect') == true` 时返回 `(state: unavailable, text: l10n.aiCellAlwaysReasons)`。
- 文案：en「this model always reasons」，zh「该模型始终思考」。

**测试**
- `openai_provider_test.dart` 新增用例，配置为 `platform: 'zhipu'`、`glm-5.3`、思考关：
  - Mock 第一次回 400 `{"error":{"code":"1210","message":"该模型始终思考，不支持关闭思考"}}`，第二次回正常流。
  - 断言：共 2 次请求；第 2 次 body 没有 `thinking`；`learned.thinkingOffTried` 含 `dialect`；再调一次 `chat` 只发 1 次请求、body 没有 `thinking`。
  - 同一配置、思考开：body 有 `thinking:{type:"enabled"}`，说明「开」没有被连带剥掉。
- 反例：400 文案是「messages 参数非法」→ 只发 1 次请求，抛 `AiException`，什么也没学到。
- `ai_capability_matrix_test.dart`：learned 含 `dialect` 时，该格为 `unavailable`。

**文档**
- organize-pipeline.md 第 35 行那段末尾补一句：
  「a model that cannot stop reasoning (Zhipu's 5.3 generation refuses the switch without naming it) is remembered per route, and the switch is left off for it」。

---

## 第 3 步 · A4：Responses 恒发 `instructions`

**现状**
- [openai_responses_provider.dart:267](../../lib/services/ai/openai_responses_provider.dart) 写的是 `if (instructions.isNotEmpty) 'instructions': …`。
- 识帧请求（[frame_vision.dart:50](../../lib/services/ai/frame_vision.dart)）只有一条 `UserMessage`，于是 body 里没有 `instructions`。
- organize-pipeline.md 第 66 行本来就写着「`instructions` every time」，是代码与文档不一致。

**方案**
- 改成 `'instructions': instructions,`，没有 system 消息时发空串。依据 02 §7.1 规则 2【实测 2026-09】，以及 01 §9.2「网关的 `instructions` 护栏」。
- 顺手把 `_payload` 里这一行的注释写上原因：中转站发现 `instructions` 缺失时会注入自己的系统提示，每次 4.4K–9K token。

**测试**
- `openai_responses_provider_test.dart`：`previewRequest(messages: [UserMessage('frames')])` 的 body 里 `instructions` 为 `''`。
- 现有断言 `expect(body['instructions'], 'rules')`（:75）不受影响。

**风险**
- 如果某个中转站拒收空串 `instructions`，那是会响的 400。`instructions` 不是可选字段，不进学习。
- 这种情况出现时再按 V 类待核实处理。KB 没有记录这类站点。

---

## 第 4 步 · A3：Responses 关思考时发 effort none

**现状**
- [openai_responses_provider.dart:255–258](../../lib/services/ai/openai_responses_provider.dart) 只在思考开时发 `reasoning:{effort:"medium"}`，关时什么都不发，由模型用自己的默认值（GPT-5.5/5.6 是 `medium`，Grok 是 `high`，03 §7.1【实测 2026-09】）。
- organize-pipeline.md 第 66 行把这一点写成了明文例外；能力矩阵 [ai_capability_matrix.dart:296](../../lib/widgets/settings/ai_capability_matrix.dart) 显示「模型默认」。

**方案**
1. 思考关、`reasoning` 不在 `rejectedFields`、`thinkingOffTried` 里没有 `effortNone` 时，发 `reasoning:{effort:"none"}`。思考开时照旧发 `medium`。
2. 400 学习分两种（[:192–209](../../lib/services/ai/openai_responses_provider.dart)）：
   - **思考关**时点名 `reasoning` → 记 `thinkingOffTried += {'effortNone'}`，重发时不带 `reasoning`，也就是回到今天的行为。
   - **思考开**时点名 `reasoning` → 仍然进 `rejectedFields`，表示模型根本没有推理，这是现有行为。
   - 分开记的原因同第 2 步：「关」被拒，不代表「开」也会被拒。Grok 4.5/4.6 就会走前一条，它们本来就关不掉。
3. `_payload` 增加参数 `offRefused`。`previewRequest` 从 `learned.thinkingOffTried` 取值后传入。
4. 能力矩阵的 Responses 分支改成：
   - learned 含 `effortNone` → `(unavailable, aiCellModelDefault)`；
   - 否则 → `(unmeasured, aiCellProtocolSwitch('reasoning.effort'))`。新键 en「{field} · protocol field」，zh「{field} · 协议字段」。
   - 状态用 `unmeasured` 而不是 `works`：经中转站的 GPT 会把 `none` 静默改写成 `medium`（03 §7.4【实测 2026-09-24】），发了不等于关掉。真正的判据是连接测试里的 `reasoned`：诊断页已有「模型仍在推理」一步（[ai_diagnostics_page.dart:299](../../lib/widgets/settings/ai_diagnostics_page.dart)），不需要新 UI。
5. 不做阶梯（比如 `none` 被拒后再试 `minimal`）：
   - KB 03 §7.1 的表只证实了 `none` 的覆盖面。
   - 加一级就是多一种付费试探。
   - 有实测再加，作为数据行扩展。

**测试**（`openai_responses_provider_test.dart`）
- 思考关：body 的 `reasoning` 为 `{effort:"none"}`；思考开：为 `{effort:"medium"}`。
- 思考关，Mock 第一次回 400 `{"error":{"message":"Unsupported value: 'reasoning.effort' does not support 'none'","param":"reasoning.effort"}}`：
  - 共发 2 次，第 2 次 body 没有 `reasoning`；
  - `learned.thinkingOffTried` 含 `effortNone`，`rejectedFields` **不含** `reasoning`；
  - 之后同一路线思考开时，body 仍有 `{effort:"medium"}`。
- `ai_capability_matrix_test.dart:64` 的断言改为检查新文案；另加一条 learned 含 `effortNone` → `unavailable`。

**文档**
- organize-pipeline.md 第 66 行「One exception to "reasoning off by default"…the capability matrix says so.」整句换成：
  「With thinking off it sends `reasoning: {effort: "none"}`; a route that refuses it is remembered and left at the model's default, and a relay that rewrites `none` shows up as reasoning in the connection test.」
- 代码 :255 的注释同步改。

---

## 第 5 步 · A2：回传火山方舟的 `encrypted_content`

**现状**
- ① 的流解析只读 `reasoning_content` / `reasoning`（[openai_provider.dart:658](../../lib/services/ai/openai_provider.dart)），非流式同样（:763）。
- 回传只写 `reasoning.field: reasoning.text`（:519）。
- KB 03 §3.2【实测 2026-09-23】：
  - 2.1 系的 `reasoning_content` 只是摘要，原文加密放在 `delta.encrypted_content`。
  - 工具轮要把两者**一起**带回，`encrypted_content` 优先；摘要为空时只回密文。

**载体的选择**

两个候选：

| 方案 | 做法 | 结论 |
|---|---|---|
| A | 用 `ProviderTurn` 装密文 | 不选 |
| B | 扩展 `ReasoningPassback` | **采用** |

- 为什么不选 A：`TokenBudget.estimate`（[agent_runtime.dart:416](../../lib/services/agent/agent_runtime.dart)）遇到带 `raw` 的助手消息，**只按 `raw.parts` 估算**。① 的 `raw` 里只有一段密文，估算会漏掉正文、工具调用和摘要，历史裁剪就会低估。
- 为什么 B 更好：`ReasoningPassback` 本来就是 ① 的回传载体，挂载规则（只在有工具调用的轮次上）一模一样。
- 模型绑定：
  - `ReasoningPassback` 今天就不绑模型 id，A2 不改变这一点。
  - 理由：① 的历史只活在一次 `AgentRuntime` 运行里，而一次运行只用一个配置（整理的批次重试也是同一配置），不存在跨模型回传。
  - 将来如果出现跨模型的历史（续跑、换模型重试），再给 `ReasoningPassback` 与 `reasoning_content` 一起加 `model` 字段，届时按 KB 原则 3 剥离。这个判断写进 `chat.dart` 的注释。

**方案**
1. `chat.dart`：

   ```dart
   /// Reasoning kept with the turn that produced it, under the field name the
   /// server used. [encrypted] is Volcengine's encrypted chain of thought
   /// (`encrypted_content`, 03 §3.2): never shown, sent back beside the
   /// summary, and alone when the summary is empty.
   typedef ReasoningPassback = ({String field, String text, String? encrypted});
   ```

2. 流解析（:656 起）：
   - 每个 delta 里，如果 `delta['encrypted_content']` 是非空字符串，就追加到一个新的 `StringBuffer encrypted`（按到达顺序拼接，03 §3.2）。
   - 收尾时：`reasoningField != null || encrypted.isNotEmpty` 就构造 passback；只有密文时 `field` 取 `'reasoning_content'`、`text` 取 `''`。
   - 密文非空也算 `reasoned`。
3. 非流式 `_parseCompletion`（:763）：同样读 `message['encrypted_content']`。
4. 回传 `_wire`（:519）：

   ```dart
   if (toolCalls.isNotEmpty && reasoning != null) ...{
     if (reasoning.text.isNotEmpty || reasoning.encrypted == null)
       reasoning.field: reasoning.text,
     'encrypted_content': ?reasoning.encrypted,
   },
   ```

5. `TokenBudget.estimate` **不算** `encrypted`：`agent_runtime.dart` 的 `_opaque` 已经把 `encrypted_content`、签名这类不透明串排除在估算外（预算裁不动它们，算进去只会多裁工具结果），这里保持同一口径。
6. `ApiLog` 不用改：密文与 ② 的 `encrypted_content` 同样处理——超过 2048 字符的只留前 200 字符加长度，更短的原样记下。它不是凭据，日志也只在本机、默认关闭。

**测试**
- `openai_provider_test.dart`：
  - SSE 帧 `{"delta":{"reasoning_content":"\n","encrypted_content":"djEN…"}}`，接一个工具调用 → `result.reasoning` 为 `(field: reasoning_content, text: "\n", encrypted: "djEN…")`。
  - 把 `toMessage()` 放进历史再发一轮 → assistant 消息同时有 `reasoning_content` 和 `encrypted_content`。
  - 摘要为空、只有密文 → assistant 消息只有 `encrypted_content`。
  - 没有工具调用的轮次 → 两个字段都不带（`toMessage` 现有规则）。
- 现有用例改记录字面量，补 `encrypted: null`：`chat_tools_test.dart:103`、`:212`，`agent_runtime_test.dart:355`。

**文档**
- organize-pipeline.md「Pass-back is one carrier」段末补一句：
  「Chat Completions' reasoning passback (`ReasoningPassback`) also carries Volcengine's `encrypted_content`, sent back beside the summary on tool-call turns.」

---

## 第 6 步 · A13：Messages 的思考写法按模型形态，带回退

**现状**
- [anthropic_provider.dart:263–267](../../lib/services/ai/anthropic_provider.dart) 固定发 `{type:"enabled", budget_tokens: max(1024, maxTokens~/2)}`，不带 `display`。
- 被拒时，`refusesThinking`（:227）命中就把 `thinking` 整个记进 `rejectedFields`，30 天内思考都被静默剥掉。

**依据**（KB 03 §3 的方言表）

| 形态 | 发什么 | 适用 |
|---|---|---|
| `adaptive` | `{type:"adaptive", display:"summarized"}` | Claude 4.6+ |
| `extended` | `{type:"enabled", budget_tokens:N, display:"summarized"}` | 更早的模型 |
| `switch` | 开 `{type:"adaptive"}`，关 `{type:"disabled"}`，**不发 display** | 第 7 步用 |

- 缺省猜法：KB 建议 ④ 族乐观猜 `adaptive`，前提是「错的方式会响」（03 §3 缺省方言一段）。
- 「schema 没有的字段不发」：兼容层「忽略未知键」和「400 未知键」一样常见。

**方案**
1. **按模型选形态，数据化。** 在 `thinking_dialect.dart` 里加 `MessagesThinking` 和一张有序小表，写法与 `sampling_presets.dart` 一致：每行注明出处，越具体的行越靠前。

   ```dart
   /// The form a Messages request asks for thinking in (03 §3).
   enum MessagesThinking {
     /// `{type: adaptive}` — Claude 4.6 and later.
     adaptive,
     /// `{type: enabled, budget_tokens}` — earlier Claude, and the mirrors
     /// that document only this form.
     extended;

     /// Claude from 4.6 on (claude-<family>-4-6…, claude-<family>-5…) takes
     /// adaptive; everything else keeps extended, which is what every route
     /// sent before — so a mirror's bytes do not change.
     static MessagesThinking forModel(String model) => …;
   }
   ```

   - 按模型 id 判断的只有「代际」这一件事。这与 `sampling_presets` 按家族取预设是同一类数据，不属于厂商分支。
   - 非 Claude 的 id 一律 `extended`，也就是今天的字节。这里是有意**偏离** KB 的「缺省猜 adaptive」：这些镜像上的非 Claude 模型支不支持 `adaptive`，KB 没有证据；保持原样至少不会引入新的 400。
2. **`display` 只对官方主机发。**
   - `_official`（:71）为 true 且形态是 `adaptive` / `extended` 时，加 `display:"summarized"`。
   - 镜像和中转站不发，依据 KB 的「文档没写的不发」。审查里也说过，缺 `display` 对本应用影响小：`reasoned` 按块类型判断，签名照样在。
3. **被拒先换形态，再放弃。** 400/422 分支（:182–201）里 `thinking` 的处理改成三级：
   1. 预算类错误（文案同时含 `budget_tokens` 和 `max_tokens`）→ 保持现状，不当拒绝，照原样抛错。
   2. 文案含 `thinking`，且当前形态还没被拒过 → 记 `rejectedFields += {'thinking:<形态>'}`，下次换另一种形态重发。
      - 老模型收到 `adaptive` 的典型文案是「thinking.type: Input tag 'adaptive' … does not match … 'disabled', 'enabled'」，不在 `refusesThinking` 的正则里。所以这一级的判据是「点名 `thinking`」，而不是「拒绝措辞」。
   3. 两种形态都被拒过，或者原本就满足 `refusesThinking` 且另一形态已试过 → 记 `thinking`，也就是现有行为，表示模型确实不支持思考。
   - 形态选择：`forModel(model)` 得到首选；首选在 `rejectedFields` 里就用另一种；两种都在就不发 `thinking`。
4. **静默关思考要能被看见。** 诊断页（[ai_diagnostics_page.dart:299](../../lib/widgets/settings/ai_diagnostics_page.dart)）现在只在思考**关**时显示「模型仍在推理」。补上对称的一步：
   - 思考**开**时显示一步：`result.reasoned` 为真显示 `aiStepThinkingOn`「模型在推理」；为假显示 `aiStepThinkingNotOn`「请求了推理，但回复里没有」，`ok: null`（待定，不是失败：adaptive 与 Gemini 动态思考遇到连接测试这么小的请求可能不想）。
   - 这一步对四个协议族都有效，也能抓住中转站静默忽略 `thinking` 的情况（03 §3.3 表：翻译层后端不想）。

**测试**（`anthropic_provider_test.dart`）
- 现有断言 `:189` 的模型是 `claude-sonnet-5`，按新规则应得 `adaptive`：
  - 该用例的端点是 `thinking.example`，不是官方主机，所以断言改为 `{'type': 'adaptive'}`，不带 `display`；
  - 另加一条同配置、官方主机的用例，断言 `{'type':'adaptive','display':'summarized'}`。
- `forModel` 的表测：

  | 模型 id | 期望 |
  |---|---|
  | `claude-sonnet-4-5` | `extended` |
  | `claude-opus-4-6` | `adaptive` |
  | `claude-sonnet-5` | `adaptive` |
  | `glm-4.7` | `extended` |
  | `deepseek-v4` | `extended` |

- 回退：`claude-opus-4-6`，Mock 第一次回 400 `thinking.type: Input tag 'adaptive' found…` → 第 2 次 body 为 `{type:"enabled", budget_tokens:…}`，`rejectedFields` 含 `thinking:adaptive`、**不含** `thinking`。
- 两种都被拒 → 第 3 次请求不带 `thinking`，`rejectedFields` 含 `thinking`。
- 预算类错误 → 只发 1 次请求，照原样抛错。现有 `:493` 的用例保留。
- `ai_diagnostics_page_test.dart`：思考开且 `reasoned: false` 时，显示 `aiStepThinkingNotOn`。

**文档**
- organize-pipeline.md 第 66 行 Anthropic 部分补一句：
  「asks for thinking as `adaptive` on Claude 4.6+ and `enabled` + budget elsewhere, with `display: "summarized"` on Anthropic's own host only; a refused form is swapped for the other before thinking is given up.」

---

## 第 7 步 · A6：Messages 路线可声明思考开关

**现状**
- `RouteSpec.thinkingDialect` 只有 ① 适配器读（[platform_profiles.dart:26–38](../../lib/services/ai/platform_profiles.dart)）。
- ④ 在思考关时什么都不发。对默认开思考的镜像（火山方舟 ④，03 §3.2【实测 2026-09-18】），这等于关不掉。

**方案**
1. `RouteSpec` 增加字段 `final bool messagesThinkingSwitch;`（默认 false）。声明为 true 的 ④ 路线就是 KB 的 `switch` 方言：
   - 开：`{type:"adaptive"}`，不带 `display`；
   - 关：`{type:"disabled"}`。

   用 bool 而不是复用 `ThinkingDialect`：`ThinkingDialect.field()` 产出的是 ① 的字段形状（`thinkingType` 开时是 `enabled`、不带预算），套到 ④ 上会是错的字节。
2. 内置数据行：
   - **MiniMax ④ 设为 true**。依据 03 §3：MiniMax-M3 的 ④ 只收 `adaptive | disabled`，没有 `display`。今天发的是 `enabled + budget_tokens`，一旦被 400，第 6 步之前的代码就会把思考静默关掉 30 天，正是 A13 的风险。`source` 写 `【KB 03 §3】MiniMax-M3 /anthropic: adaptive | disabled`。
   - **火山方舟 ④ 不加内置行**：KB 01 §9.3 没有记 ④ 的路径。路径核实后作为数据行补上（见 V4）。
   - **DeepSeek、百炼、智谱的 ④ 不声明**：它们默认开不开思考是 V4 待核实。在核实前，它们照第 6 步走 `standard`，关时什么都不发。
3. `_payload`（[anthropic_provider.dart:242](../../lib/services/ai/anthropic_provider.dart)）：路线声明了开关、思考关、`thinking` 不在 `rejectedFields` 时，发 `thinking:{type:"disabled"}`。
   - 这时 `temperature` / `top_p` / `top_k` 照常发（思考并没有开）。
   - 开关路线的 `max_tokens` 不用抬到 2048：`adaptive` 不需要预算。
4. 能力矩阵（[ai_capability_matrix.dart:293](../../lib/widgets/settings/ai_capability_matrix.dart)）：④ 路线声明了开关 → `(works, aiCellSwitch('thinking'))`；否则保持 `aiCellDefaultOff`。

**测试**
- `platform_profiles_test.dart`：MiniMax 的 ④ 路线 `messagesThinkingSwitch` 为 true，其余内置 ④ 为 false。
- `anthropic_provider_test.dart`，`platform: 'minimax'`：
  - 思考关 → `thinking:{type:"disabled"}`，且有 `temperature`；
  - 思考开 → `{type:"adaptive"}`，没有 `display`，没有 `budget_tokens`。
- 未声明的路线思考关 → 没有 `thinking` 键。现有 `:172` 保持不变。
- `ai_capability_matrix_test.dart`：MiniMax ④ 的格显示 `thinking · 平台开关`。

**文档**
- organize-pipeline.md 第 35 行那段末尾补一句：
  「A Messages route whose platform thinks by default declares `messagesThinkingSwitch` and gets `thinking: {type: "disabled"}` when off.」

---

## 第 8–12 步：小而独立的五条

### 第 8 步 · A5：每个 delta 只取一个推理字段

- **改动**：[openai_provider.dart:658](../../lib/services/ai/openai_provider.dart) 的循环改成取第一个非空字段后 `break`。字段一旦锁定，优先读锁定的那个：

  ```dart
  for (final field in [?reasoningField, ..._reasoningFields]) {
    final piece = delta[field];
    if (piece is String && piece.isNotEmpty) {
      reasoningField ??= field;
      reasoningText.write(piece);
      break;
    }
  }
  ```

  列表里会有重复项，但命中后就 `break`，无害。
- **测试**：一帧 `{"delta":{"reasoning_content":"abc","reasoning":"abc"}}` 加一个工具调用 → `reasoning.text == 'abc'`。另一个用例：先锁定 `reasoning`，之后的帧同时带两个字段 → 只取 `reasoning` 的内容。

### 第 9 步 · A7：生成请求遇 408 / 504 不重发

- **现状**：只有四个适配器的生成 POST 调用 `withRetry`（已 grep 确认）。探测请求 `_probe` 不走它。所以直接收窄那张表就行，不需要区分调用方。
- **改动**：
  - [ai_http.dart:23](../../lib/services/ai/ai_http.dart) 改成 `_retryableStatuses = {429, 502, 503, 529}`。
  - 注释写明原因：408 和 504 表示上游可能还在生成、还在计费。
  - `withRetry` 的文档补一句「only for requests that are safe to send twice once refused」。
- **502 保留**：它是网关没拿到有效响应，比 504 更可能是在上游开始工作之前就失败了。KB 06 §3 没有给出更细的证据。
- **测试**（`ai_http_test.dart`）：`withRetry` 包一个计数的 `send`：
  - 504 → 调用 1 次、返回 504；408 同样；
  - 503 带 `retry-after: 0` → 调用 3 次。
- **文档**：CLAUDE.md「a timed-out generation is never retried」改成「a timed-out generation — a client timeout, 408 or 504 — is never retried」。organize-pipeline.md 第 15 行同步改。

### 第 10 步 · A9：从 `error.param` 学被拒字段

- **改动**：
  1. 在 `AiHttp` 里加 `static String? errorParam(http.Response res)`：读 `{"error":{"param":…}}` 的字符串，失败返回 null。`describeError` 不变。
  2. ① 和 ② 的非 2xx 分支先把响应读成 `http.Response` 保存下来，再分别取 `error` 文本和 `param`。
  3. 字段查找改成 `param` 优先、子串匹配作后备：

     ```dart
     bool paramNames(String? param, String field) =>
         param != null &&
         (param == field || param.startsWith('$field.') ||
             param.startsWith('$field['));
     final refused =
         candidates.where((f) => paramNames(param, f)).firstOrNull ??
         candidates.where((f) => _namesField(detail, f)).firstOrNull;
     ```

  4. ① 的 `max_completion_tokens` 判定和 JSON mode 判定保持在前（它们看的是文案），顺序不变。
- **范围**：④ 的错误体没有 `param`；③ 的错误在 `details[].fieldViolations`，KB 没有证据表明需要，所以都不改。
- **测试**：② 的 Mock 回 400 `{"error":{"message":"Encrypted content is not supported with this model.","param":"include"}}` → 第 2 次 body 没有 `include`，`rejectedFields` 含 `include`。① 用 `param: "top_k"`、文案不含字段名的用例 → `top_k` 被剥掉。
- **证据**：这条文案是审查的 V5，**待核实**。测试钉的是「`param` 优先」这个结构，不依赖文案真伪；测试注释里写明这条文案是构造的。

### 第 11 步 · A10：接受完整端点地址；错误带 URL

- **改动**：
  1. ④ `_base`（[anthropic_provider.dart:61](../../lib/services/ai/anthropic_provider.dart)）：去掉末尾斜杠后，先剥末尾的 `/messages`，再走现有的 `/v1` 规则（02 §4、坑 16 的 `anthropicRoot`）。
  2. ③ `_base`（[google_genai_provider.dart:88](../../lib/services/ai/google_genai_provider.dart)）：先剥 `RegExp(r'/models(/[^/]*)?$')`，这样粘贴 `…/v1beta/models` 或 `…/v1beta/models/gemini-3:generateContent` 都能用，再走现有的 `contains('/v1')` 规则。
  3. **错误带 URL，只在 404 / 405 时带。** 第 1 步的 `statusError` 增加可选参数 `Uri? url`，在 404 / 405 时往消息后追加 ` — POST <scheme://host:port/path>`。
     - 去掉查询串的写法从 [api_log.dart:87](../../lib/services/ai/api_log.dart) 抽成 `AiHttp.safeUrl(Uri)`，`ApiLog` 改为调用它。
     - URL 从 `res.request?.url` 取，`StreamedResponse` 带 request。
     - 为什么只在 404 / 405 时带：学习逻辑和 `refusesTools` 都在错误文案上做子串匹配。如果一个中转站的路径里有 `function` 或 `thinking` 这类词，带上 URL 会让这些匹配误判。404 / 405 正好是「地址错了」的状态码，也不进任何学习分支，`refusesTools` 要求 400/422。KB 06 §2 说「一律带 URL」，这里收窄了范围，理由如上。
- **测试**：
  - `anthropic_provider_test.dart:82` 那组加两个用例：`https://api.anthropic.com/v1/messages` 和 `…/apps/anthropic/v1/messages`，都命中 `…/v1/messages`。
  - `google_genai_provider_test.dart`：`…/v1beta/models` → `…/v1beta/models/<m>:streamGenerateContent`。
  - 404 的错误文案含路径、不含查询串。③ 的用例要断言文案里**没有** `key=`。③ 的 key 在请求头里，这里是双保险。
- **文档**：CLAUDE.md「`/v1` is appended only to a bare origin」后补一句「a pasted `/messages` or `/models…` endpoint is cut back to its root」。

### 第 12 步 · A12：背靠背拼接的 JSON 参数

- **改动**：
  1. `chat.dart` 加一个纯函数 `static Map<String, dynamic>? mergeConcatenated(String raw)`：
     - 按括号深度扫描，遇到字符串就跳过里面的括号和转义，切出顶层的 `{…}`；
     - 对象之间只允许空白；
     - 切出不少于 2 个对象、每个都能解码成 Map 时，从左到右合并返回，否则返回 null。
  2. `decodedArguments` 在 `FormatException` 时回退到它。
  3. ① 的 `_PendingCall.build`（[openai_provider.dart:1024](../../lib/services/ai/openai_provider.dart)）在参数整体解码失败、而合并成功时，用 `jsonEncode(merged)` 替换参数原文。
     - 原因：① 回传会把 `arguments` 原样带回，而坑 105 的来源正是「经中转的 Claude 后端」，中转站把它翻译回 ④ 时必须解析 JSON，拼接串会在下一轮 400。
     - `ToolCall.arguments` 的注释改成「as the model wrote them, or merged when it wrote several objects back to back」。
- **测试**：
  - 新建 `test/services/ai/chat_test.dart`（`chat.dart` 的镜像路径，目前没有这个文件）：

    | 输入 | 期望 |
    |---|---|
    | `{}{"id":1}` | `{"id":1}` |
    | `{"a":"}{"}{"b":2}`（字符串里有括号） | `{"a":"}{","b":2}` |
    | `{"a":1} x {"b":2}` | null |
    | `{"a":1}` | 原样返回 |

  - `openai_provider_test.dart`：流里的工具调用参数分两段 `{}` 和 `{"title":"Dune"}` → `call.arguments == '{"title":"Dune"}'`。

---

## 第 13 步 · A11（选乙）

**问题**：② 和 ④ 缺终止事件就整条失败；`Sse.read` 与 ③ 的 `_events` 遇到坏 `data:` 就整条失败；① 的 `_read` 却跳过坏行（:647）。项目有意取了更严的立场，这是会响的错误，但对这类中转站是**每次**都失败。

**选项**

| | 做法 | 代价 |
|---|---|---|
| 甲（维持） | 不改代码；只把 ① 统一成严格（坏行也抛），四族一致 | 这类中转站永远不可用 |
| 乙（**推荐**） | 坏行跳过并计数；缺终止事件时，只要已收到**完整**的项（② 的 `output_item.done`、④ 的每个 `content_block_stop`）且有文本或工具调用，就照常收尾，`finishReason: null`，并在 `ApiLog` 里记一笔 `incomplete_stream`；其余情况照旧抛 | 可能把「真被截断、只是恰好截在项边界」的回答当成完整回答。④ 的工具调用要等 `content_block_stop` 才算完整，截在调用中间的仍会抛 |
| 丙（全宽容） | KB 02 §3.1、§7.2【实现】的做法：坏行忽略，流一结束就 flush 收尾 | 静默错误的风险最大，与项目「宁响勿静」的一贯立场冲突 |

**推荐乙的理由**
- 它只在「收到的东西本身完整」时放行，放行的判据是协议里的结构事件，不是猜测。
- 被跳过的坏行如果恰好是工具调用，对应的 `output_item.done` / `content_block_stop` 也就不会出现，仍然会抛错，所以「丢的那一帧可能正是工具调用」这个顾虑依然被守住。

**执行要点**
- `Sse.read` 返回值加一个 `skipped` 计数，flush 里遇到 `FormatException` 就计数、不抛。
- ③ 的 `_events` 同样处理，并考虑直接改用 `Sse.read`（它的注释说两者规则相同，重复实现正是分歧的来源）。这可以作为本步的前置重构提交。
- ④ 的 `_Block` 加 `closed` 标记，在 `content_block_stop` 时置位。
- ② 用 `items` 是否非空、且每项都来自 `output_item.done` 来判断。它本来就只收 `done` 事件。
- 测试：
  - `sse_test.dart:43`「a malformed event is an error, never skipped」改成：坏行跳过，`skipped == 1`；
  - ② 和 ④ 各加两例：「完整项 + 无终止事件 → 成功，`finishReason` 为 null」「半个块 + 无终止事件 → 抛 `AiNetworkException`」。
- 文档：organize-pipeline.md 第 66 行「fails on a malformed event rather than skipping it」和「treats a stream without a terminal event as no answer」两处都要改。

**决定**：2026-09-25 选乙，见 [变更记录](#变更记录)。审查的状态列写「乙 + 提交号」。

---

## 待核实项：验证后怎么动

每项先按 KB 的付费实测纪律（06 §7）做最便宜的验证，结果写回 KB，再按下表动代码。

| # | 验证 | 结果 → 动作 |
|---|---|---|
| V1 | 对 gemini-3 各发一次 `thinkingLevel: "low"` 和 `"LOW"`，比较是否 400，以及 `thoughtsTokenCount` | 都收、token 相同 → 不改，在 KB 03 §2 注明大小写都收。小写 400 → 改成 `'LOW'`（[google_genai_provider.dart:327](../../lib/services/ai/google_genai_provider.dart)），加一条断言，一个提交。小写 200 但想得更多 → 同样改大写，这是静默错误，优先级升到第 2 批 |
| V2 | 对 vLLM 发 `repeat_penalty: 2.0` 和 `repetition_penalty: 2.0` 各一次，比较输出 | vLLM 只认后者 → 在 `ServerKind.vllm` 时改用 `repetition_penalty`（`_compose` 的 optional 按服务端种类选键名，数据写在 `sampling_presets` 旁）。两者都认 → 不改 |
| V3 | 读 MiniMax 文档的 interleaved thinking 一节，再用两轮工具调用对比「回传 `<think>`」和「不回传」 | 要求回传 → MiniMax ① 的 `<think>` 内容进 `ReasoningPassback`（以 `content` 内联的形式回传），并声明为 MiniMax ① 路线的数据。不要求 → 不改 |
| V4 | 不带 `thinking` 对百炼、DeepSeek、智谱的 ④ 各发一次，看有没有 thinking 块；同时查火山方舟 ④ 的路径 | 默认在想的 → 在 `platform_profiles.dart` 把该 ④ 路线的 `messagesThinkingSwitch` 设为 true（第 7 步的机制，纯数据改动），并先发一次 `disabled` 确认收。火山 ④ 路径查到 → 加内置路线行，开关设为 true |
| V5 | 官方 key 对 `gpt-4.1` 发一次带 `include` 的 ② 请求（零输出成本） | 第 10 步已按结构修复，不依赖结果。结果只用来把文案写回 KB，并把测试注释里的「构造的文案」改成实测 |

---

## 写回 KB（不改代码）

审查「项目里有、KB 没有的事实」一节的五条，都是【实现】级证据。按 KB「维护知识库」一节写回：

| 事实 | 写到哪里 |
|---|---|
| LM Studio 拒收 `json_object`；三种错误体形状 | 04 §结构化输出（① 行）；06 §错误 |
| OpenRouter 的保活注释 | 02 §3.1 |
| Ollama `/v1` 不传 `chat_template_kwargs`、缺采样值时强制 1.0；llama.cpp 默认 `min_p 0.05` | 03 §4（本地服务端）；01 §9 |
| 智谱对 `chat_template_kwargs` 照收不读 | 03 §3.1 |
| Qwen3 Thinking-2507 省略开头的 `<think>`；Gemma 4 的 `<|think|>`；gpt-oss 最低 `low` | 03 §6；11 追加坑（编号接着往下排） |

本计划执行中得到的新实测（V1–V5 的结果，以及第 2、4、6 步在真实服务上的首次运行）同样写回，并注明日期。

---

## 验收清单

全部完成时，下面每一项都应成立：

- [ ] 审查问题清单里 A1–A12 的状态都是提交号，A11 是「乙 + 提交号」。
- [ ] 真实适配器 + `MockClient` 回 429、503、401、402 时，`probeTools` 的结果是 `inconclusive`，`onToolSupport` 没被调用。
- [ ] 智谱 glm-5.3 在默认设置（思考关）下，第二个请求起可以正常使用。
- [ ] ② 的每个请求都有 `instructions`；思考关时有 `reasoning:{effort:"none"}`，除非该路线学到了被拒。
- [ ] 火山方舟 ① 的工具轮回传里带 `encrypted_content`。
- [ ] ④ 对 Claude 4.6+ 发 `adaptive`，官方主机带 `display`；形态被拒时先换形态；诊断页能显示「请求了推理但没想」。
- [ ] MiniMax ④ 关思考发 `disabled`、开思考发 `adaptive`。
- [ ] 408 / 504 不重发。
- [ ] `error.param` 能驱动学习。
- [ ] 粘贴完整的 ④ / ③ 端点地址可以直接用；404 的错误信息带路径、不带查询串。
- [ ] `{}{"id":1}` 能解析，且回传时已经是单个对象。
- [ ] CLAUDE.md 与 organize-pipeline.md 里本计划点到的每一句都已同步。
- [ ] `dart format --set-exit-if-changed .`、`flutter analyze --fatal-infos`、`flutter test` 全部通过。

---

## 变更记录

| 日期 | 改了什么 | 为什么 |
|---|---|---|
| 2026-09-25 | 初稿 | — |
| 2026-09-25 | 相对审查建议的四处细化：A2 载体不用 `ProviderTurn`、改为扩展 `ReasoningPassback`；A3 / A8 的「关」被拒记在 `thinkingOffTried` 而不是 `rejectedFields`；A10 的错误 URL 只在 404 / 405 时附加；A13 非 Claude 模型保持 `extended`，没有按 KB 缺省猜 `adaptive` | 对照代码后发现：`TokenBudget.estimate` 只按 `raw.parts` 估算；「关」被拒不代表「开」也被拒；错误文案上有子串学习，附加 URL 会误判；非 Claude 镜像的 `adaptive` 支持没有证据 |
| 2026-09-25 | A11 定为乙；13 步合成一个 PR，每个提交先由一个子代理审查并修掉问题，最后整体审查一次再开 PR | 用户决定。上面的 PR 划分仍是评审顺序：提交按步号排列 |
| 2026-09-25 | A8 的新判据挪到 `refused` 查找之后；`'dialect'` 成了常量 `LearnedBehaviour.dialectOff`；矩阵的阶梯计数不算它 | 放在之前会截走点名字段的文案，与第 3 点矛盾；路线键不含平台，同一集合里可能两种记录都有 |
| 2026-09-25 | A2 的历史估算不算密文 | 原方案要求算进去；执行时发现 `_opaque` 对所有不透明串（含 ② 的 `encrypted_content`）一律不算，理由写在那里，照同一口径 |
| 2026-09-25 | A13：诊断页「请求了推理但没有」记为待定（`ok: null`），不是失败；带 `redacted_thinking` / `signature` / `messages.N` 的 400 与模型 id 里的 `thinking` 不参与学习 | 审查发现：adaptive 可能对小请求不想，标红会误导；这几类 400 是会话本身的错，拿来换形态会把思考静默关掉 |
| 2026-09-25 | A6：开关路线开思考时 `max_tokens` 仍按 2048 下限抬高；被拒的 `adaptive` 不换成 `enabled` | 与第 6 步所有「开」的请求同一口径，下限无害；声明为开关的路线只收 `adaptive` / `disabled`，换成预算写法必然再被拒 |
| 2026-09-25 | A6：模型页的推理开关与「推理开关」一行、换路线对话框也读 `messagesThinkingSwitch`（`PlatformProfiles.switchFieldFor`） | 审查发现：没有采样预设的模型（如 MiniMax-M3）只在平台有开关时才能拨开关，原先只看 ① 的方言，`adaptive` 从界面上到不了，那一行还写着本地阶梯 |
| 2026-09-25 | A9：① 的 JSON mode 判定也读 `param`（`response_format`） | 原方案保持它只看文案；审查发现只在 `param` 里点名 `response_format` 的 400 会直接抛错，与 A9 是同一类问题。`max_completion_tokens` 仍只看文案：`param: "max_tokens"` 也可能只是数值超限 |
