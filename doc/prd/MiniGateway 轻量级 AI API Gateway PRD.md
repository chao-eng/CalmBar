# CalmBar AI 网关（轻量级 AI API Gateway）PRD

| 项目 | 内容 |
|------|------|
| **文档版本** | v2.5 |
| **状态** | 定稿（v2.4 基础上完成第三轮边界闭合评审回填：提交前暂存总量上限、统计与传输提交分离、previous_response_id 渠道映射、浏览器跨源防护、HTTP 层资源限制、incomplete 落库口径、URLSession 压缩验证，新增决议见 §7 Q-60 起） |
| **日期** | 2026-11-05 |
| **归属** | CalmBar 主 App 功能模块（代码位于 `app/Sources/CalmBar/`），完整接入 Feature / Command / Settings / 菜单栏面板体系；**不创建独立子项目** |
| **运行形态** | 随 CalmBar 主 App 进程运行，由 Feature 启停控制 HTTP 服务监听 `127.0.0.1:8317`；App 退出即网关停止，无独立进程、无后台守护 |
| **核心用户** | 本机开发者 / 任何 OpenAI 兼容客户端（SDK、CLI、脚本） |

---

## 0. 原始需求基线（追溯表）

> 本表确保所有设计可回溯到用户原始诉求。

| ID | 原始需求 | 拆解后产品含义 |
|----|----------|----------------|
| R-01 | 只保留 6 个模块的最小实现 | 砍掉管理后台、分布式、大而全；每个模块只做下表定义的最小行为 |
| R-02 | 兼容 OpenAI Chat Completions | 实现 `GET /v1/models`、`POST /v1/chat/completions`、`POST /v1/responses`（v2.3 新增）、`GET /health` 四个接口；客户端只改 API Base URL 即可接入 |
| R-03 | SSE 尽可能原样透传 | 实时转发、不缓存完整响应、SSE 事件内容不做语义修改（Raw Byte Forwarding + 旁路解析）；客户端断开时取消上游请求 |
| R-04 | Token 与速度统计（最重要功能） | 记录 TTFT、Input/Output Tokens、Generation Time、Output TPS、Total Time；usage 优先，估算兜底并标记来源；明确客户端可观察口径 |
| R-05 | 模型别名映射到多个渠道 | `models` → `channels` 配置驱动；渠道组数组顺序即尝试顺序；别名改写为上游实际模型名；记录实际使用渠道 |
| R-06 | 主渠道失败时切换备用渠道 | 按故障判定表切换，区分「未执行类安全切换」与「执行状态未知类风险切换」（记录 retry_reason）；仅提交点之前可透明切换；已输出内容后不拼接备用渠道；首个有效内容前暂存以保留切换机会 |
| R-07 | SQLite 保存每次请求统计 | 以用户原始 `requests` 表结构为基础扩展落库；第一版只需可查询，不做报表 |
| R-08 | 约 10 个 Swift 文件的目录结构 | 以 §6 文件清单为基线，允许按职责边界适当增加文件（v2.1 修订：职责清晰优先于文件数） |
| R-09 | 不追求功能大而全 | §2 Non-goals 明确排除项，评审时以此卡边界 |
| R-10 | 第一版仅 Chat Completions | 原 v1 边界；**v2.3 修订**：新增 Responses 透传（R-18），支持 Chat Completions 与 Responses 两种协议；仍不兼容 Anthropic API、Gemini 等其他协议，且不做协议互转 |
| R-11 | 不创建独立子项目，直接并入 CalmBar | 作为 CalmFeature 接入主 App：注册 FeatureID / Command，网关服务封装在 `Services/AIGateway/`，HTTP 服务随 App 进程启停；统计与配置由原生 UI 承载 |
| R-12 | 速率 / Token 统计展示 UI | 菜单栏面板新增独立分区 Tab：主体为速率折线图，默认展示近 10 分钟、每分钟一个数据点的 Output TPS，每条折线对应一个（渠道 + 模型）组合，支持按小时 / 按天切换时间窗口与粒度（FR-07）+ 独立窗口展示历史请求记录（FR-08） |
| R-13 | 渠道配置 UI | 偏好设置新增独立 Tab：模型别名与渠道 CRUD、api_key 掩码、顺序排序、网关开关与端口（FR-09） |
| R-14 | 账号达到用量限制时切换账号 | 识别上游用量耗尽类错误（quota 类 429 / 402 / 403 计费类），请求内切换下一渠道，并对该渠道标记跨请求冷却，冷却期内路由跳过（FR-05，决议 Q-24） |
| R-15 | 模块默认不启用，需要手动开启 | Feature 初始状态为 disabled：新装 / 重置后网关不监听端口、不随 App 启动自动开启；用户在偏好设置手动开启后状态持久化（FR-09，决议 Q-37） |
| R-16 | 渠道支持手动启用 / 禁用、测试连接与接口延迟 | 渠道级启用开关：禁用渠道不参与路由与故障切换；「测试连接」按钮发送探测请求并展示连接结果与接口延迟（FR-09，决议 Q-38） |
| R-17 | 部分渠道通过指定代理配置请求 | 渠道级可选代理（类型 / 主机 / 端口 / 可选认证）：配置后该渠道全部上游请求（含连接测试）经代理发出，未配置渠道直连（FR-09 / §5，决议 Q-39） |
| R-18 | 支持 OpenAI Responses 格式中转 | 新增 `POST /v1/responses`：透传转发至渠道 `<base_url>/responses`，旁路识别 delta 事件与 usage，统计口径与 Chat Completions 统一；不做协议互转（FR-01 ~ FR-04，决议 Q-40 / Q-41）。**v2.4 明确仅「创建接口透传兼容」**：查询 / 取消 / 输入项 / background / WebSocket 不在第一版（决议 Q-42）；携带 `previous_response_id` 的有状态请求按 response_id → 渠道映射路由、不跨渠道切换（**v2.5 修订为第一版实现映射表**，决议 Q-44 / Q-62） |

---

## 1. 产品概述

### 1.1 背景与问题

本机开发者在调用 LLM 时面临三个具体麻烦：

1. **想换上游就要改代码**。客户端写死一个 base URL，想在多个上游（官方 API、中转站、本地模型）之间切换，只能逐个改配置。
2. **想知道真实体感速度，但没有数据**。直连上游时，TTFT、输出吞吐这些"客户端可观察"的指标拿不到；SSE 块数不等于 Token 数，肉眼估 TPS 不可信。
3. **上游挂了只能手动重试**。DNS 解析失败、连接超时、上游 429/5xx，都需要人工换渠道重发。

现有开源网关（one-api 类）面向团队和多租户，自带管理后台、用户体系、容器部署，与本场景"一台 Mac、一个人、零运维"的需求不匹配。

### 1.2 产品契约

| 要素 | 定义 |
|------|------|
| **用户** | 本机开发者，以及其使用的任何 OpenAI 兼容客户端 |
| **核心任务** | 把客户端请求透明转发到可配置的渠道，并留下含 TTFT / TPS 的可查记录 |
| **触发** | 客户端向 `http://127.0.0.1:8317/v1` 发起 OpenAI Chat Completions 或 Responses 请求 |
| **完成证据** | 客户端拿到与直连上游语义一致的响应（SSE 事件流内容一致）；`requests` 表新增一条完整指标记录，且菜单栏面板「网关」分区与历史窗口立即可见该记录 |
| **恢复路径** | 主渠道故障时切换备用渠道：连接类故障保证客户端无感知；执行状态未知类故障允许切换但记录 retry_reason 与重复执行风险 |
| **信任边界** | 网关仅监听 127.0.0.1，凭据存本机 macOS Keychain（AppSettings 仅存引用，决议 Q-20），叠加 Host / Origin / Sec-Fetch-Site 校验（决议 Q-21 / Q-63），不引入任何远端依赖 |

### 1.3 产品目标（可观察结果）

| 目标 | 观察口径 |
|------|----------|
| 客户端零改造接入 | 仅修改 API Base URL 为 `http://127.0.0.1:8317/v1`，沿用原 OpenAI SDK 调用方式即可工作 |
| SSE 事件零篡改 | 逐事件对比网关与直连上游的 SSE 消息流：正常返回时事件内容完全一致（含 usage 帧、`[DONE]`），不丢弃、不新增、不修改任何事件；**不要求 HTTP Chunk 边界 / TCP 分片一致**（Raw Byte Forwarding + 旁路解析，见 FR-02） |
| 故障切换无感知 | 连接类故障（DNS / TCP / TLS）在提交点之前发生时，客户端收到某个可用渠道的正常响应且完全无感知；执行状态未知类故障（5xx 等）切换成功但落库记录 retry_reason |
| 指标可查可复算 | 每次请求终结后，SQLite 中可查到该请求的渠道、Token 数、TTFT、TPS 等字段，且可用公式复算 |
| 指标抬头可见 | 请求结束后无需打开任何工具：菜单栏面板「网关」分区的速率折线图即可看到各「渠道 · 模型」组合近 10 分钟（可切换近 10 小时 / 近 10 天）的输出速率趋势 |
| 配置即存即用 | 在偏好设置「AI 网关」Tab 完成模型与渠道配置后，无需重启 App，下一次请求即按新配置路由（决议 Q-11） |

---

## 2. 范围

### 2.1 最小完整旅程（P0）

1. 用户在偏好设置「AI 网关」Tab 启用网关（**默认关闭，首次需手动开启**，决议 Q-37），配置模型别名与渠道（FR-09）；
2. 网关服务随 Feature 启动，配置校验通过后 HTTP 服务在 CalmBar 进程内监听 8317；
3. 客户端只改 base URL，发起流式或非流式对话请求；
4. 网关路由 → 转发 → 透传，必要时故障切换；
5. 请求终结，指标写入 SQLite；菜单栏面板「网关」分区实时可见速率折线图与网关状态（FR-07），打开独立窗口可查全量历史（FR-08）。

最重要失败的恢复路径：主渠道连接失败 / 429 / 5xx → 透明切换备用渠道（详见 FR-05）。

### 2.2 明确不做（Non-goals）

- 不做 Web 管理后台、远程仪表盘、浏览器访问的任何界面；统计与配置 UI 全部由 CalmBar 原生界面承载（FR-07 ~ FR-09）；
- 不做分布式、集群、多实例、远程配置；
- 不做用户体系、多租户、计费、配额、API Key 池化轮询；
- 不兼容 Anthropic API、Gemini 等其他协议（支持 OpenAI **Chat Completions 与 Responses** 两种协议透传，v2.3）；**不做 Chat Completions ↔ Responses 协议互转**——客户端发哪种协议，上游就收到哪种协议（决议 Q-40）；Responses 仅支持**创建接口**透传，查询 / 取消 / 输入项 / background 模式 / WebSocket 不在第一版（决议 Q-42）；
- 不做请求改写：不注入参数、不改写 `stream_options`、不给 SSE 加料；
- 不做渠道主动健康探测、熔断、限流；跨请求渠道状态**仅限两种**：用量耗尽冷却标记（FR-05，Q-24）与 response_id → 渠道粘性映射（FR-04 规则 7，Q-62，v2.5 新增），其余故障每次请求都从渠道组头部重新尝试；
- 不做精确 Tokenizer 保证（估算 + usage 校准）；
- 不做请求重放、响应缓存、语义去重；
- 不做 JSON 配置导入 / 导出（决议 Q-12）；渠道级手动启停、连接测试与代理配置属第一版范围（v2.2 新增，决议 Q-38 / Q-39）。

> 注：本模块并入 CalmBar 主 App，`doc/design/CalmBar 新功能接入模板.md` 的 10 项准入原则**全部适用**，逐项落实见 §6.4 对照表。

---

## 3. 核心对象与术语（唯一定义处）

> 以下定义全文档唯一，各功能小节引用时不再重复。

### 3.1 对象定义

| 术语 | 定义 |
|------|------|
| **模型别名（model alias）** | 客户端请求体中 `model` 字段的值，由 AppSettings 渠道配置（§5）的 `models` 节定义。客户端永远只使用别名。 |
| **渠道（channel）** | 一个上游 OpenAI 兼容端点：`base_url` + `api_key`（Keychain 引用）+ 上游实际模型名。 |
| **尝试顺序** | 模型渠道组内数组的书写顺序即最终尝试顺序（第一权威，v2.1 起取代 priority 数值排序，决议 Q-22）；设置 UI 的拖拽 / 上下移直接修改数组顺序。 |
| **有效输出内容** | **Chat Completions**：SSE chunk 中 `choices[].delta` 的 `content`、`reasoning_content`、`tool_calls` 任一非空，或非流式响应体中的首个非空内容；仅含 `finish_reason`、仅含 usage、注释行/空行、role-only chunk 均不算。**Responses（v2.3 新增，v2.4 完善事件分级）**：按 §3.1.1 事件分级表判定——有效输出为携带增量内容的事件；非流式取响应体 `output` 数组中的首个非空文本 / 函数调用输出。 |
| **提交点（切换窗口）** | 网关向客户端写出第一个响应字节（含状态行 / 响应头）的时刻。**首个传输提交事件到达前，网关不得向客户端提交任何字节（包括 HTTP 响应头）**——上游 200 响应头本身不构成提交，仅被暂存（状态机见 FR-02 规则 6）。提交点之前可无代价透明换渠道；之后锁定当前渠道。**v2.5 关键修订（决议 Q-61）：「传输提交事件」与「统计有效输出」分离**——文本 / 推理 / 函数调用类有效输出、多模态增量事件（音频 / 图像 delta，携带实际输出数据）均触发传输提交，但多模态事件不触发 TTFT / TPS 统计打点；终止事件（`response.completed` 等）到达而从未提交过时，先提交全部暂存再按终止语义结束（保证纯多模态 / 无文本输出请求正常工作）。 |
| **执行状态未知（execution unknown）** | 上游已接收请求并可能已开始执行（产生计费 / 副作用）后才失败的故障类别，如 HTTP 5xx、发送后读取超时、首内容前连接中断、响应体超限。此类切换存在重复执行风险（FR-05）。 |
| **用量耗尽（quota exhausted）** | 上游返回的用量/计费受限错误：429 且错误信息含 quota / billing 类特征（如 `insufficient_quota`、`quota_exceeded`），或 402 / 403 计费类错误。区别于瞬时限流（429 但无 quota 特征，如 rate limit / concurrency）。 |
| **暂存** | 流式请求下，网关在首个传输提交事件之前不向客户端写出任何字节（**含响应头**），将其缓冲在内存中；一旦切换成功，被丢弃的暂存内容属于失败尝试，不参与转发。**提交前暂存总量上限默认 8 MB（v2.5 新增，决议 Q-60）**——单事件 1 MB 上限（FR-02 规则 2）只约束单个事件，总量上限约束整个提交前缓冲区，达限处理见 FR-02 规则 9。暂存不等于缓存完整响应（§FR-02）。 |

#### 3.1.1 Responses 事件分级表（canonical，决议 Q-43 / Q-59；v2.5 修订统计与传输分离，决议 Q-61 / Q-65）

| 事件 | 级别 | 网关行为 |
|------|------|----------|
| `response.output_text.delta` / `response.reasoning_text.delta` / `response.function_call_arguments.delta` | 有效输出 | 触发 TTFT 统计打点 + 传输提交（未提交时一次性提交暂存） |
| `response.output_item.added` | **不视为有效输出，不触发传输提交**（v2.4 修订：仅声明输出项结构，无增量内容） | 继续暂存，等同心跳不重置 First Content Timeout |
| `response.created` / `response.in_progress` 等纯状态事件 | 心跳 | 继续暂存，不重置 First Content Timeout；计入提交前暂存总量（Q-60） |
| `response.completed` | 正常终止 | 从事件内 `response.usage` 对象提取 usage（Q-41）；**从未提交过时先一次性提交全部暂存，再转发该事件并结束**（Q-61 兜底规则，保证纯多模态 / 无文本输出请求正常工作） |
| `response.failed` | **终止事件**（模型执行失败） | 立即终止等待（**不等待 First Content Timeout、不切换渠道**）；从未提交过时先提交全部暂存，原样转发该事件后结束，落库 `status=failed` |
| `response.incomplete` | **终止事件**（不完整终止） | 立即终止等待，按正常结束处理（非故障）；从未提交过时先提交全部暂存，原样转发后结束；落库口径见 Q-65：`status=success`，`error` 字段记录不完整原因摘要（如 `incomplete: max_output_tokens`），供历史窗口区分「正常结束」与「模型主动截断」 |
| 音频 / 图像等多模态增量事件 | **传输提交事件**（v2.5 修订，原为仅透传） | 原样透传并**触发传输提交**（未提交时一次性提交暂存，含此前暂存的全部事件）；**不触发 TTFT / TPS 统计打点**——第一版只承诺文本与函数调用类统计（Q-59），TTFT / TPS 落库 NULL |
| 未知事件 | 原样透传 | 解析器安全跳过，不影响转发（Q-49）；计入提交前暂存总量（Q-60），持续大量到达可触发暂存上限保护 |

> 关键语义：HTTP 200 ≠ 模型执行成功——`response.failed` 属于**流内业务终止**，与网络故障分开处理（统一状态机见 FR-02 规则 7）。无任何有效 delta 即收到终止事件时，立即按终止语义处理，防止已被上游明确失败的请求继续等待超时或被切换重试。**v2.5 补充：统计与传输分离**——「统计有效输出」仅用于 TTFT / TPS 打点（Q-59 边界不变），「传输提交事件」决定何时向客户端发送响应（文本 delta、多模态 delta、终止事件兜底三类），两者不再完全绑定；终止事件兜底提交保证纯音频等无文本输出请求的客户端能收到完整响应流（Q-61）。

### 3.2 指标定义（canonical）

| 指标 | 定义 | 计算公式 |
|------|------|----------|
| T_request | 网关收到客户端请求的时刻 | — |
| T_first | 网关从上游收到首个有效输出内容的时刻 | — |
| T_last | 网关从上游收到最后一个有效输出内容的时刻 | — |
| T_end | 请求终结（正常结束 / 失败 / 取消 / 中断）的时刻 | — |
| **TTFT** | 从请求开始到首个有效输出内容 | `T_first − T_request` |
| **Generation Time** | 首个有效输出到最后一个有效输出的时间 | `T_last − T_first` |
| **Output TPS** | 平均每秒输出 Token 数（客户端可观察吞吐） | `OutputTokens / (GenerationTime 秒)` |
| **Total Time** | 整个请求总耗时 | `T_end − T_request` |
| **Input Tokens** | 输入 Token 数 | 优先取上游 `usage.prompt_tokens`；缺失时用估算值 |
| **Output Tokens** | 输出 Token 数 | 优先取上游 `usage.completion_tokens`；缺失时用估算值 |

流式请求下各时刻在网关收到上游数据的瞬间打点；由于收到即转发（透传），打点值与客户端可观察时刻一致。

**非流式口径（v2.1 修订，决议 Q-25）**：`stream=false` 时上游在生成完成后一次性返回响应体，网关只能观察传输过程、无法观察生成过程，因此：

| 指标 | 非流式请求行为 |
|------|----------------|
| Input / Output Tokens、Total Time | 正常统计（usage / 估算，同 §3.3） |
| TTFT | 仅记录"响应体首字节到达时刻 − T_request"，**明确不等同于真实首 Token 时间**，仅作参考 |
| Generation Time | 不可靠（测得的是网络传输时间，≈ 0） |
| Output TPS | **默认 NULL，不计算**，不得把传输速度伪装成生成速度 |

**口径声明**：以上统计的是**客户端可观察到的输出吞吐量**，包含网络传输开销，不应描述为模型服务端内部的纯 Decode TPS。指标命名固定为 `output_tps`：**usage 总输出 Token ÷ 可观察生成时间的近似吞吐**——当 usage 总输出含 SSE 中未以 delta 暴露的内部内容（如部分 reasoning）时，TPS 会被高估，属已知口径偏差（决议 Q-48）；UI 文案统一为「网关观察到的平均输出速率」，不承诺模型内部 Decode TPS；`visible_output_tps`（仅按可观察输出内容估算的口径）列为 P2。

### 3.3 Token 数据来源规则（canonical）

**Output Tokens 边界（v2.1 明确，决议 Q-26）**：OutputTokens 指模型生成的**全部输出 Token**（对齐上游 `completion_tokens` 语义），涵盖 `content`、`reasoning_content`、`tool_calls.function.name`、`tool_calls.function.arguments`、`refusal`，而非仅用户可见文本。

| 规则 | 内容 |
|------|------|
| 校准优先 | 上游返回的 `usage` 字段**存在且合法**时，Input/Output Tokens 一律采用 usage 值——**usage 为 0 也是合法值，无条件保留 0，不得用估算覆盖**（决议 Q-19）。**协议字段映射（v2.3，决议 Q-41）**：Chat Completions 取 `usage.prompt_tokens` / `usage.completion_tokens`；Responses 取结束事件或响应体中 `usage.input_tokens` / `usage.output_tokens`。映射后统一走同一套校准、来源标记与落库规则，统计层不感知协议 |
| 非法判定 | usage 字段缺失、类型错误、负数、非整数、超出合理范围（如 > 10^9）视为非法，此时才启用估算兜底 |
| 估算兜底 | 无法采用 usage 时，优先使用对应模型的 Tokenizer 估算；无法获取该模型 Tokenizer 时，退化为字符启发式估算：`tokens = ceil(CJK 字符数 × 1 + 非 CJK 非空白字符数 × 0.25)`，下限 1。**估算输入必须覆盖全部输出内容边界**：`content`、`reasoning_content`、`tool_calls` 的 name 与 arguments、`refusal`。已知局限（不在第一版解决）：字符启发式对代码、JSON 密集内容偏差较大（符号、缩进、变量名切分更多），对多模态（图片 / 音频）内容无法估算，标记为 unknown 来源 |
| 来源标记 | 每个 Token 数值必须落库标记来源（v2.1 新增，决议 Q-19）：`usage`（上游校准）/ `tokenizer`（模型 Tokenizer）/ `heuristic`（字符启发式）/ `unknown`（多模态等无法估算），见 FR-06 表结构。UI 展示速率时可据此区分真实校准数据与估算数据 |
| 实时 vs 最终 | 流式过程中以估算器实时计数（用于本次 TPS 计算），usage 到达后以 usage 值覆盖，最终落库为准（来源同步更新为 usage） |
| 禁止按块计数 | SSE 数据块数量不等于 Token 数量，任何情况下不得用块数近似 Token 数 |

---

## 4. 功能需求

### FR-01 API 代理

**目的**：让任何 OpenAI 兼容客户端只改 base URL 即可接入网关。

**接口清单**：

| 接口 | 功能 | 行为 |
|------|------|------|
| `GET /v1/models` | 返回网关配置的模型 | 返回渠道配置（§5）中模型别名的 OpenAI models 列表格式；quota 冷却等瞬时状态**不影响**列表；组内渠道全部手动禁用的别名**不返回**（决议 Q-57） |
| `POST /v1/chat/completions` | 转发对话请求 | 路由（FR-04）→ 转发（FR-02）→ 必要时切换（FR-05）→ 统计（FR-03）→ 落库（FR-06） |
| `POST /v1/responses` | 转发 Responses 创建请求（v2.3 新增；**仅创建接口透传兼容**，范围见规则 10） | 流程同上；透传至 `<base_url>/responses`，不做协议互转（决议 Q-40） |
| `GET /health` | 检查网关运行状态 | 进程存活即返回 `200 {"status":"ok"}`；仅表征网关自身，不做任何渠道探测 |

`GET /v1/models` 响应示例：

```json
{
  "object": "list",
  "data": [
    { "id": "gpt-6", "object": "model", "owned_by": "calmbar" }
  ]
}
```

**处理规则**：

1. 客户端接入方式：原 `https://api.openai.com/v1` 改为 `http://127.0.0.1:8317/v1`，调用方式不变（Chat Completions 与 Responses 客户端均适用）。
2. 监听地址**固定为 `127.0.0.1`，不提供任何修改入口**（UI 与配置均不暴露，防止意外开放到 0.0.0.0，决议 Q-21）；仅监听端口可在偏好设置「AI 网关」Tab 中修改（默认 8317）。端口被占用时 HTTP 服务启动失败：Feature 置为 `failed` 状态，设置页与面板分区显示明确错误，**不得影响主 App 其他功能、不得退出 App**（决议 Q-15）。
3. 网关级鉴权：可选配置网关访问密钥 `server.api_key`（§5）——未设置时不校验客户端凭据；设置时客户端必须携带 `Authorization: Bearer <server.api_key>`，缺失或不匹配返回 `401`；**密钥比较必须使用恒定时间算法**，防时序侧信道（决议 Q-21）。校验通过后网关丢弃客户端凭据，统一替换为所选用渠道的 `api_key`（渠道 `api_key` 为空时不发送该头，用于本地无需鉴权的上游；认证 Header 类型按规则 9 `auth_header_type` 决定）。
4. 请求体透传语义（v2.4 精确化，决议 Q-55）：除 `model` 字段按 FR-04 改写为上游实际模型名外，其余 JSON 字段**语义保持不变**——不注入、不删改；但 model 改写需解析并重新序列化请求体，**不承诺请求体字节级一致**（仅语义一致）。响应方向 SSE 正文内容原样透传、不要求 HTTP Chunk 边界一致（FR-02）。
5. 请求体大小限制：默认上限 **20 MB**（决议 Q-23），超出时拒绝转发并返回 `413`，不读入完整请求体。
6. 客户端请求安全约束（决议 Q-21；**v2.5 扩充浏览器跨源防护，决议 Q-63**）：仅接受 `Host` 为 `127.0.0.1[:port]` 或 `localhost[:port]` 的请求。**浏览器边界防护**——「无 CORS 头」只能阻止浏览器读取跨源响应，不能阻止简单跨源请求发出，因此对疑似浏览器请求增加四层防护：
   - `Sec-Fetch-Site` 头存在且值为 `cross-site` → 返回 `403` 拒绝；
   - `Origin` 头存在且不匹配本机回环源（`http://127.0.0.1:port` / `http://localhost:port`，含 `Origin: null` 时视同不匹配拒绝）→ 返回 `403` 拒绝（curl / SDK 等非浏览器客户端不带 Origin，不受影响）；
   - `OPTIONS` 请求一律返回 `405`，不提供 CORS 预检支持；
   - `POST` 转发端点要求 `Content-Type` 含 `application/json`，不满足返回 `415`（跨源简单请求典型以 `text/plain` 规避预检，拒绝后浏览器无法改写 Content-Type 发简单请求）。
   未设置 `server.api_key`（默认无网关鉴权）时上述浏览器防护仍然生效；设置网关密钥后浏览器请求还须通过 Bearer 校验。
7. 上游响应 Header 转发策略（v2.1 新增）：按白名单转发（`Content-Type` 等），**剥除全部 hop-by-hop Header**（`Connection`、`Keep-Alive`、`Transfer-Encoding`、`Proxy-Authenticate` 等）及 `Content-Length`——这些由网关对客户端的传输层自行生成，禁止原样透传导致协议错误。
8. 日志与错误脱敏：上游 API Key、网关密钥**禁止出现在任何日志、错误信息、落库字段与 UI 文案中**；对客户端返回的上游错误内容须检查并剥离其中的凭据痕迹。
9. 上游认证方式（v2.4 新增，决议 Q-54）：渠道可选 `auth_header_type`——`bearer`（默认，`Authorization: Bearer <key>`）/ `api-key`（OpenAI 风格 `api-key: <key>`）/ `x-api-key`；自定义 Header 与 Query 参数认证列 P2。向上游转发的请求头按白名单控制：客户端认证头（已被渠道凭据替换）、代理相关头与网关内部实现头**不得**透传到上游。
10. Responses 端点范围（v2.4 新增，决议 Q-42）：第一版定位为「**Responses 创建接口透传兼容**」，仅实现 `POST /v1/responses`；`GET /v1/responses/{id}` 查询、`POST /v1/responses/{id}/cancel` 取消、输入项查询列为 P2；`background=true` 后台模式与 WebSocket 模式不在支持范围（客户端如携带 background 参数，网关按普通透传转发，但因无查询 / 取消端点不承诺其可用性；文档与 UI 不得宣称完整兼容 Responses API）。
11. 错误响应统一使用 OpenAI 风格 error 对象，便于客户端 SDK 解析：

```json
{ "error": { "message": "model `foo` not found", "type": "invalid_request_error", "code": "model_not_found" } }
```

**异常**：

| 场景 | 结果 |
|------|------|
| `server.api_key` 已设置但客户端凭据缺失/错误 | 返回 `401`，code 为 `invalid_api_key` |
| `Host` 非本机回环域名 | 返回 `421` 并拒绝处理 |
| 跨源浏览器请求（`Sec-Fetch-Site: cross-site` 或 `Origin` 不匹配回环源） | 返回 `403`（v2.5，决议 Q-63）；`OPTIONS` 返回 `405`；POST Content-Type 非 JSON 返回 `415` |
| 请求体超过 20 MB | 返回 `413`，不读入完整请求体 |
| `model` 别名未在配置中定义 | 返回 `404`，code 为 `model_not_found` |
| 请求体非法 JSON / 缺少 `model` | 返回 `400`，`invalid_request_error` |
| 未知路径或方法 | 返回 `404` |
| 全部渠道尝试失败 | 返回 `502`，`api_error`，message 注明已尝试的渠道数 |

---

### FR-02 流式转发

**目的**：流式响应实时、逐事件、原样地到达客户端，网关"像不存在一样"。

**触发**：客户端请求体 `stream=true` 或 `stream=false`（Chat Completions 或 Responses 协议均适用）。

**处理规则**：

1. **Raw Byte Forwarding + Side-channel Parsing（v2.1 修订，决议 Q-27）**：`stream=true` 时，网关将上游返回的原始数据直接转发，**SSE 解析器作为旁路**，仅用于识别有效输出内容、usage 与结束事件，绝不解析后重新序列化 SSE。保证对象为 **SSE 事件流的内容一致**（不丢弃、不新增、不修改任何事件，含 usage 帧与 `data: [DONE]`），**不要求 HTTP Chunk 边界 / TCP 分片一致**——上游的 Transfer-Encoding、压缩、分片由传输层处理，网关对客户端使用自己的传输编码。**压缩处理（v2.4，决议 Q-50；v2.5 增补验证要求，决议 Q-66）**：网关向上游统一携带 `Accept-Encoding: identity`，尽量避免压缩流；若上游仍返回压缩内容，原样转发压缩流，旁路解析器对压缩数据跳过事件识别（统计退化为估算口径，来源标记不变），转发不受影响。**URLSession 对 gzip / br 等内容编码存在自动解压行为，且自动解压后 `Content-Encoding` 头的存留与网关转发头白名单的匹配须实测确认**——该验证项并入开发前 PoC（§6.5 / Q-66），确保「转发给客户端的响应头与响应体编码声明一致、旁路解析器看到的数据与转发数据同源」。
2. **SSE Parser 解析边界（v2.4 补全，决议 Q-49）**：Parser 必须支持——跨网络读取边界切分（单事件拆多块 / 多事件合一块）；`\r\n` 与 `\n` 两种换行；单事件多行 `data:` 拼接；UTF-8 多字节字符跨读取块（按字节缓冲，不拆断）；`event:` / `id:` / `retry:` 字段解析；`:` 注释心跳识别；**单事件缓冲上限（默认 1 MB，超限放弃该事件的统计、不影响转发）**。核心约束：**旁路解析失败不得影响原始转发**——非法 JSON 事件、未知 Responses 事件、解析器自身异常均只跳过该事件的统计，转发字节流不受任何破坏。
3. `stream=false`：上游响应体完整转发。网关在收齐响应体之前不向客户端写出任何字节（提交点规则见 §3.1），从而为非流式请求保留完整的故障切换窗口。暂存响应体设**大小上限（默认 64 MB，决议 Q-23）**；超限属**执行状态未知类故障**（上游可能已完成生成并计费，v2.4 修订，决议 Q-56）：记录 `retry_reason=response_too_large`，按 FR-05 执行状态未知类切换，客户端收统一 `502` 错误；流式单事件缓冲上限见规则 2。
4. 网关不注入 `stream_options`（已决：保守透传优先，不改写客户端请求体）；客户端未携带 `include_usage` 时，上游不会返回 usage 帧，统计按 §3.3 估算兜底。
5. 结束事件识别：收到 `data: [DONE]` 或上游正常关闭连接视为流结束；最终 usage 帧被识别并用于校准（FR-03），同时原样转发给客户端。
6. **提交状态机（v2.1 明确，衔接 FR-05）**——上游 HTTP 200 响应头与 SSE 正文分别管理，200 响应头本身不构成提交：

| 状态 | 网关行为 |
|------|----------|
| 等待上游响应 | 不向客户端提交任何字节 |
| 收到 200 响应头 | 暂存响应头，继续等待 |
| 收到 SSE 注释 / 空事件 / role-only chunk / Responses 纯状态事件 | 继续暂存（不计入 First Content Timeout 的"有效内容"，防心跳无限拖延，见 FR-05 规则 5） |
| 收到首个传输提交事件（首个统计有效输出，或多模态增量事件——Q-61） | 一次性提交暂存的响应头 + 已缓冲字节，此后纯透传 |
| 收到终止事件（`[DONE]` / `response.completed` / `.failed` / `.incomplete`）而从未提交过 | 先一次性提交全部暂存，再按终止语义转发并结束（Q-61 兜底，保证纯多模态请求客户端能收到完整响应） |
| 提交前上游失败 | 丢弃暂存，走 FR-05 切换 |
| 提交后上游失败 | 关闭连接，不切换、不拼接（见异常表） |

7. **统一上游响应状态机（v2.4 新增，决议 Q-45）**：规则 6 的提交状态机仅覆盖 2xx 流式响应；完整状态机将 HTTP 状态与 SSE 业务语义分开——

| 上游状态 | 网关行为 |
|----------|----------|
| 非 2xx | **立即**读取错误体（大小上限 1 MB），按 FR-05 错误分类决定切换或透传，**不等待 SSE 有效内容** |
| 2xx 非流式 | 暂存响应体（上限规则 3）→ 收齐后提交 |
| 2xx 流式 | 按规则 6 提交状态机处理；SSE 终止事件（`[DONE]`、`response.completed` / `.failed` / `.incomplete`）按 §3.1.1 终止语义处理，**与网络故障分开**——HTTP 状态成功 ≠ 模型执行成功 |
| 超时 / 断开 | 按提交点决定：提交前按 FR-05 分类切换；提交后关闭连接记 interrupted |

8. **Responses 协议差异（v2.3 新增，v2.4 完善，决议 Q-40 / Q-41 / Q-43）**：`POST /v1/responses` 的流式响应为 SSE 事件流（`event:` + `data:` 行），Raw Byte Forwarding、提交状态机、三段超时、故障切换全部同样适用；旁路识别按 §3.1.1 事件分级表执行——usage 从 `response.completed` 事件内的 `response.usage` 对象提取并按 §3.3 映射；终止事件立即终结请求，不等待超时、不切换；状态类与结构类事件（`response.created`、`response.output_item.added`）等同心跳，不重置 First Content Timeout。
9. **提交前暂存总量上限（v2.5 新增，决议 Q-60）**：规则 6 提交状态机下，所有已暂存但未提交的原始数据（含 200 响应头 + 累积 SSE 字节）设**累计总量上限 `precommit_buffer_limit`，默认 8 MB**——单事件 1 MB 上限（规则 2）只约束一个事件，本上限约束整个提交前缓冲区，防止上游持续发送不触发传输提交的事件（如大量音频增量前置状态、未知事件族）导致内存占用失控。达限处理：
   - **首次提交前**达到上限：视为上游异常，丢弃全部暂存，按 FR-05 **执行状态未知类**处理（retry_reason=`precommit_buffer_exceeded`，可切换但记录重复执行风险），全部渠道耗尽时客户端收统一 `502`；
   - 已提交后的转发不受本上限约束（纯透传不缓冲）；
   - 配合 Q-61 的多模态传输提交规则：多数场景下多模态 delta 会正常触发提交、缓冲随提交清空，本上限仅兜底「大量不可识别事件且无任何传输提交事件」的异常场景；
   - 纯状态事件持续到达的场景由 First Content Timeout（300s）与本上限双兜底：先到者触发。

**异常**：

| 场景 | 行为 | 状态 |
|------|------|------|
| 客户端主动断开 | 网关在察觉断开后立即取消上游请求，不留孤儿连接；察觉时限 ≤ 1s | 记录 `status=cancelled` |
| 提交点之前上游失败 | 走 FR-05 切换逻辑 | 按 FR-05 |
| 提交点之后上游断开 | 不切换、不拼接备用渠道结果：直接关闭客户端连接，不伪造 `[DONE]` 或补写内容 | 记录 `status=interrupted`，error 注明 `upstream disconnected mid-stream` |
| 非流式响应体超暂存上限（64 MB） | 记录 `response_too_large`，归**执行状态未知类**（v2.4，决议 Q-56）：允许切换但落库记录重复执行风险，客户端收统一 `502` | 记录 `retry_reason=response_too_large` |
| 提交前暂存总量超上限（8 MB） | 记录 `precommit_buffer_exceeded`，归**执行状态未知类**（v2.5，决议 Q-60）：允许切换但落库记录重复执行风险，全部渠道耗尽时客户端收统一 `502` | 记录 `retry_reason=precommit_buffer_exceeded` |

---

### FR-03 Token 与速度统计（最高优先级模块）

**目的**：为每次请求产出可信、可复算的体感指标。这是整个项目最重要的功能。

**触发**：每个进入 `POST /v1/chat/completions` 或 `POST /v1/responses` 的请求。

**处理规则**：

1. 按 §3.2 指标定义打点并计算 TTFT、Generation Time、Total Time、Output TPS（流式）；非流式请求按 §3.2 非流式口径：TTFT 仅记录响应体首字节参考值，Output TPS 落库 NULL。
2. Input/Output Tokens 按 §3.3 规则取值：usage 存在且合法（含 0）时无条件采用，仅缺失/非法时估算兜底，禁止按 SSE 块数计数；Token 来源（usage / tokenizer / heuristic / unknown）随数值一并落库（FR-06）。
3. Output TPS = OutputTokens / GenerationTime（秒），仅流式请求计算。Generation Time 为 0（无有效输出，如首个内容后立即结束）时不计算 TPS，落库为 NULL。
4. 每次请求终结时，无论成功、失败、取消还是中断，均按 FR-06 落库一条记录（含本次实际使用的 retry_reason，见 FR-05）；失败的尝试性请求（被切换丢弃的）不单独落库，只在实际发给客户端的最终尝试上统计。
5. 记录实际使用的渠道名（FR-04）。

**结果**：`requests` 表中一条完整记录，字段含义见 FR-06。

**异常**：上游 usage 非法（缺失、负数、非整数、超范围）时按 §3.3 估算兜底并标记来源，不中断转发；usage 合法为 0 时保留 0。

---

### FR-04 渠道路由

**目的**：客户端只请求别名，网关决定真实渠道与真实模型名。

**配置结构**（数据模型示意，实际存储于 AppSettings，由 FR-09 的设置 UI 编辑，完整规格见 §5）：

```json
{
  "models": {
    "gpt-6": { "channels": ["channel-a", "channel-b"] }
  },
  "channels": {
    "channel-a": {
      "base_url": "https://api-a.example.com/v1",
      "api_key": "sk-xxx",
      "model": "gpt-6"
    },
    "channel-b": {
      "base_url": "https://api-b.example.com/v1",
      "api_key": "sk-yyy",
      "model": "gpt-6"
    }
  }
}
```

**处理规则**：

1. 客户端只请求 `gpt-6`；网关按 `models.gpt-6.channels` 找到渠道组，**数组书写顺序即最终尝试顺序**（第一权威，取代 priority 数值排序，决议 Q-22）；设置 UI 的拖拽 / 上下移直接修改数组顺序。**处于禁用状态的渠道不参与本次尝试顺序**（FR-09 渠道启停，决议 Q-37）。
2. 选中渠道后，将请求体 `model` 从别名改写为该渠道的 `model`（上游实际模型名），再**按客户端请求协议选择上游端点**：Chat Completions → `base_url + /chat/completions`；Responses → `base_url + /responses`（拼接规范化规则见 §5）。
3. 每次请求记录实际使用的渠道名，写入 `requests.channel`。
4. 跨请求渠道状态**仅限两种**：用量耗尽冷却标记（FR-05 规则 6，决议 Q-24，对 Q-07 的修订）与 response_id → 渠道粘性映射（规则 7，决议 Q-62）；其余故障每次新请求都从渠道组头部重新尝试——临时 429 限流不应导致主渠道被跨请求降级。
5. **配置快照语义**：每个请求在进入路由时读取一次配置快照，整个请求生命周期（含故障切换重试）固定使用该快照；请求进行中用户修改配置只影响后续新请求（决议 Q-11）。
6. **配置者责任**：只有模型能力、请求参数与**协议支持**都兼容的渠道才能放进同一个故障切换组；网关不做兼容性校验（例如把不支持 tools 或不支持 Responses 端点的渠道混入同组，由配置者自行承担切换后的行为差异——上游对不支持端点返回的 4xx 按 FR-05 透传不切换）。
7. **Responses 有状态请求的渠道粘性与 response_id 映射（v2.4 新增决议 Q-44，v2.5 修订为方案 A：第一版实现映射表，决议 Q-62）**：携带 `previous_response_id` 的请求与生成该 ID 的上游渠道存在跨请求状态依赖——该 ID 属于特定上游，其他渠道无法识别，跨渠道切换会产生状态断裂（即使本次请求不切换，若按数组顺序选中了非生成渠道，同样会失败）。**映射表机制**：
   - 网关维护内存态 `response_id → channel_id` 映射表：Responses 请求以 `status=success` 终结时，从最终响应事件中提取 `response.id` 记录映射（`store=false` 请求上游不存储响应、且无后续引用价值，不记录映射）；
   - 携带 `previous_response_id` 的请求先查映射：**命中**时无论渠道在数组中的顺序如何，直接路由到映射渠道（粘性优先于数组顺序）；映射渠道处于禁用 / 冷却 / 提交点前失败时**不切换**，直接向客户端返回 `502`，code 为 `stateful_channel_unavailable`，error 注明原渠道与失败原因，由客户端决策；
   - **未命中**（非本网关生成的 ID、已过期或已淘汰）：按数组顺序正常路由、不跨渠道切换（粘性失败由上游报错自然暴露，网关不做猜测性拦截）；
   - **容量与过期**：映射表容量上限默认 1024 条，LRU 淘汰；条目过期时间默认 24 小时；映射仅存内存运行态，App 重启即清空；
   - 不带 `previous_response_id` 的无状态请求不受影响。

**异常**（并入后不再 fail-fast 退出进程；校验失败时网关不启动，错误在设置页逐条内联提示，决议 Q-15）：

| 场景 | 行为 |
|------|------|
| 配置中 `models.*.channels` 引用了不存在的渠道名 | UI 保存时内联报错指明引用位置；服务启动兜底校验拒绝启动 |
| 模型别名对应渠道组为空 | 同上，UI 内联报错 + 兜底校验拒绝启动 |
| 渠道字段缺失/类型错误 | 同上 |
| 渠道组内全部渠道处于禁用状态 | 允许保存；路由时发现组内无可用渠道，返回 `503`，code 为 `no_available_channel`（不自动启用渠道） |

---

### FR-05 自动故障切换与用量限制切换

**目的**：主渠道故障或账号用量耗尽时，切换到备用渠道继续服务，并把每次切换的原因记录到请求历史。

**故障判定表（canonical，v2.1 修订：按重复执行风险分级 + 新增用量限制切换，决议 Q-18 / Q-24；v2.4 修订：429 / 402 / 403 类按「HTTP 状态码 + 错误体结构化错误码」两级分类，不以状态码单独定类，决议 Q-46）**：

| 故障类型 | 是否切换 | 风险级别 | retry_reason |
|----------|----------|----------|--------------|
| DNS 解析失败 / TCP 连接失败 / TLS 握手失败 / 连接超时 | 是 | 未执行类：请求未到达上游，无计费与副作用 | `connect_failed` |
| HTTP 429（错误体含 `rate_limit` / `concurrency` 类特征，瞬时限流） | 是 | 未执行类：上游拒绝执行 | `rate_limited` |
| HTTP 429 / 402 / 403（错误体含 quota / billing 类特征，如 `insufficient_quota`、`quota_exceeded`、`billing_error`） | 是 | 未执行类；**同时标记用量耗尽**（规则 6） | `quota_exhausted` |
| HTTP 500 / 502 / 503 / 504 | 可以切换，但**明确存在重复执行风险**（上游可能已执行并计费） | 执行状态未知类 | `server_error` |
| 请求发出后读取超时（First Content Timeout） | 可以切换，执行状态未知 | 执行状态未知类 | `first_content_timeout` |
| 收到 200 后、首个有效内容前连接中断 | 可以切换，执行状态未知 | 执行状态未知类 | `disconnected_before_content` |
| 提交前暂存总量超上限（8 MB，FR-02 规则 9） | 可以切换，执行状态未知（上游持续发送不可识别 / 不触发传输提交的事件） | 执行状态未知类 | `precommit_buffer_exceeded` |
| 上游 3xx 重定向 | 是（视为连接类故障，**不跟随重定向**，见决议 Q-28） | 未执行类：跨域重定向可能把 API Key 转发到其他主机 | `redirect_rejected` |
| HTTP 401 / 403（错误体含 `invalid_api_key`、`permission_denied` 等凭据 / 权限类特征） | 否 | 记录错误并透传给客户端；第一版固定该行为，不提供开关 | — |
| HTTP 429 / 403 错误体**无法识别类别** | 429 按瞬时限流切换；**403 默认不切换**、透传错误 | 403 无法仅凭状态码区分余额 / 权限 / Key 问题（决议 Q-46） | 429→`rate_limited`；403→— |
| HTTP 400 / 404 / 422 等其他 4xx | 否 | 视为请求本身的问题，原样透传，避免换渠道重复失败 | — |
| 客户端主动取消 | 否 | 终止请求，不切换 | — |
| 已向客户端输出部分内容后上游断开 | 否 | 不自动拼接备用渠道生成结果（见 FR-02 异常） | — |

**切换流程**：

```
收到请求 → 按 FR-04 得到渠道尝试顺序（跳过冷却中的渠道，规则 6）
  └─ 尝试当前渠道
       ├─ 未执行类故障 → 丢弃暂存，尝试下一渠道（逐个直到耗尽）
       ├─ 执行状态未知类故障 → 可切换，但记录 retry_reason（客户端可在历史中分析重复执行风险）
       ├─ 401 / 403 凭据类 / 其他 4xx → 不切换，透传错误响应，记录
       └─ 正常响应 → 暂存直至首个有效内容（FR-02 状态机）→ 提交并透传
            ├─ 某渠道成功 → 继续正常转发与统计，retry_reason 落库最终成功渠道前的切换原因
            └─ 全部耗尽 → 502 + OpenAI error JSON
```

**处理规则**：

1. 切换安全条件（关键限制）：**只有在提交点之前（尚未向客户端输出响应正文）时，才能透明切换**。已输出部分内容后，不能拼接另一个渠道的生成结果。
2. 流式请求下，提交点之前暂存（§3.1），因此"上游已返回 200 响应头、但首个有效内容到来之前连接失败"仍属可切换故障——但属于执行状态未知类，落库 retry_reason。
3. 每次切换计入该请求的尝试链，最终成功响应只统计实际完成响应的渠道（FR-03 规则 4）；**retry_reason 落库为本次请求最终尝试渠道之前的最后一次切换原因**（多个渠道时记录切换链摘要，如 `connect_failed:a>server_error:b`）。
4. **三段超时（v2.1 修订，取代原"无字节超时 300s"，决议 Q-29）**：

| 超时参数 | 默认值 | 作用域 | 触发后行为 |
|----------|--------|--------|------------|
| Connect Timeout | 10s | DNS + TCP + TLS 建立连接 | 未执行类，安全切换 |
| First Content Timeout | 300s | 自请求发出至收到**首个有效输出内容**（心跳、注释、空事件、role-only chunk 均不算，防上游用心跳无限拖延） | 执行状态未知类，可切换并记录 retry_reason |
| Idle Read Timeout | 120s | 已开始输出后，两次有效内容之间的最大空闲 | 仅提交点前后有别：提交前可切换；提交后**只关闭连接不切换**，记录 interrupted |

5. 收到上游首字节后仍由 Idle Read Timeout 兜底流式 stall；不设整体生成时长上限，避免长生成被误杀。
6. **用量耗尽冷却（v2.1 新增，用户需求 R-14，决议 Q-24；v2.4 修订作用域，决议 Q-47）**：识别到 `quota_exhausted` 后，除本次请求内切换下一渠道外，打跨请求冷却标记（默认 **10 分钟**），**作用域分级**——错误明确为模型级额度耗尽时按（渠道, 模型）冷却，仅跳过该渠道该模型的请求，同渠道其他模型不受影响；错误明确为账户级耗尽时按渠道整体冷却；无法判断级别时默认按渠道整体冷却并记录判断来源（error 中注明）。冷却期内路由直接跳过对应作用域（对客户端表现为从下一渠道开始，无额外失败往返）；渠道组全部处于冷却时，不再跳过、按原顺序尝试（可用性优先，quota 状态可能已被上游重置）；冷却到期自动恢复尝试。标记仅存于内存运行态，App 重启即清空；设置 UI 在渠道行展示冷却剩余时间与作用域。瞬时限流（`rate_limited`）**不**打冷却标记。

---

### FR-06 请求记录

**目的**：每次请求的统计结果落盘可查。

**表结构**（SQLite，v2.1 在 R-07 基础上扩展三个字段 + 索引 + WAL，决议 Q-19 / Q-30）：

```sql
CREATE TABLE requests (
    id TEXT PRIMARY KEY,
    model TEXT,
    channel TEXT,
    status TEXT,

    input_tokens INTEGER,
    output_tokens INTEGER,
    input_token_source TEXT,     -- usage / tokenizer / heuristic / unknown
    output_token_source TEXT,   -- usage / tokenizer / heuristic / unknown

    ttft_ms INTEGER,
    generation_ms INTEGER,
    total_ms INTEGER,

    output_tps REAL,

    retry_reason TEXT,          -- 最终成功渠道前的切换原因（FR-05），无切换为 NULL
    error TEXT,
    created_at INTEGER
);

-- 覆盖面板速率图聚合与历史窗口筛选查询（决议 Q-30）
CREATE INDEX idx_requests_created_at ON requests(created_at DESC);
CREATE INDEX idx_requests_model_created_at ON requests(model, created_at DESC);
CREATE INDEX idx_requests_channel_created_at ON requests(channel, created_at DESC);
CREATE INDEX idx_requests_status_created_at ON requests(status, created_at DESC);

PRAGMA journal_mode = WAL;      -- 降低 UI 查询与后台写入的锁竞争
```

**字段口径**：

| 字段 | 口径 |
|------|------|
| `id` | 网关生成的请求 UUID（尝试链共享同一 id，不随切换变化） |
| `model` | 客户端请求的模型别名 |
| `channel` | 实际完成响应的渠道名；未完成任何渠道时为最后尝试的渠道名 |
| `status` | 枚举：`success`（正常结束）/ `failed`（全部渠道失败）/ `cancelled`（客户端取消）/ `interrupted`（提交点后上游中断） |
| `input_tokens` / `output_tokens` | §3.3 规则取值（usage 合法值含 0 一律保留）；无 Token 数据（如连接失败）为 NULL |
| `input_token_source` / `output_token_source` | Token 数值来源：`usage` / `tokenizer` / `heuristic` / `unknown`（决议 Q-19），UI 据此区分真实校准与估算数据 |
| `ttft_ms` / `generation_ms` / `total_ms` | §3.2 定义，单位毫秒；未产生对应阶段时为 NULL；非流式请求按 §3.2 非流式口径（TPS 为 NULL） |
| `output_tps` | 流式请求：OutputTokens / GenerationTime(秒)；非流式请求或无法计算为 NULL |
| `retry_reason` | 最终成功渠道前的切换原因（FR-05 判定表枚举值），无切换为 NULL；供历史请求分析"连接问题 vs 上游执行问题 vs 用量耗尽" |
| `error` | 失败/取消/中断时的简要错误描述（含故障类型与渠道名，**不含任何密钥**）；正常成功为 NULL；**`response.incomplete` 终止（v2.5，决议 Q-65）**：`status=success` 但 `error` 记录不完整原因摘要（如 `incomplete: max_output_tokens`），供历史窗口区分「正常结束」与「模型主动截断」，`incomplete_details` 原文存于该字段 |
| `created_at` | 请求开始时刻，Unix 毫秒（与 `*_ms` 列同量纲） |

**处理规则**：

1. 写入时机：请求终结时一次性写入，不做流中更新。
2. 写入失败（如磁盘满）不得影响代理主流程，须在面板「网关」分区与历史窗口中显示明确的落库失败提示。
3. 查询方式：菜单栏面板「网关」分区（FR-07，状态行 + 速率折线图）与请求历史独立窗口（FR-08，分页记录表格）；`sqlite3` 命令行查询库文件作为调试兜底。不提供 HTTP 查询接口。
4. 库文件路径固定为 `~/Library/Application Support/CalmBar/aigateway.db`，不可配置（决议 Q-14）；**不做自动清理，允许用户在历史窗口手动删除单条记录**（FR-08）；自动数据清理策略列为 P2 迭代。

---

### FR-07 面板统计分区（菜单栏面板「网关」Tab）

**目的**：不打断工作流，点开菜单栏面板即可看到各「渠道 + 模型」组合的输出速率趋势。

**接入方式**：`PopoverTab` 新增 `gateway` 分区，`PopoverTabRoute` 路由常量表同步登记（title「网关」，subtitle「AI 网关状态与速率趋势」，`kind: gatewayCards`）。

**分区内容**（自上而下）：

| 区块 | 内容 | 数据粒度 |
|------|------|----------|
| 状态行 | 网关运行开关 + 监听地址端口；Feature 状态为 `failed` 时展示错误摘要 | 实时 |
| 速率折线图卡（主体） | Output TPS 折线图：**默认展示近 10 分钟、每分钟一个数据点**；每条折线对应一个（渠道 + 模型）组合；支持按小时 / 按天切换时间窗口与粒度 | 分钟 / 小时 / 天三档 |
| 底部入口 | 「查看完整历史」按钮，打开请求历史独立窗口（FR-08） | — |

**折线图规格**（UI 对齐参考图）：

1. 标题行：左侧时钟类 SF Symbol 图标 + 动态标题「模型速度趋势（近10分钟 / 近10小时 / 近10天）」，随粒度切换联动更新。
2. 粒度切换：分段控件「分钟 / 小时 / 天」，置于折线图卡标题行（标题文字右侧）；三档窗口与数据点口径：

| 档位 | 时间窗口 | 每点数据口径 |
|------|----------|--------------|
| 分钟（默认） | 近 10 分钟 | 该分钟内全部 `success` 请求 `output_tps` 的平均值 |
| 小时 | 近 10 小时 | 该小时内全部 `success` 请求 `output_tps` 的平均值 |
| 天 | 近 10 天 | 该自然日内全部 `success` 请求 `output_tps` 的平均值 |

3. 系列：每条折线 = 一个（渠道 + 模型别名）组合；取当前窗口内出现过请求的组合，按窗口内请求数降序最多展示 4 条，超出的组合不在面板展示，完整数据在历史窗口（FR-08）查看（决议 Q-17）。
4. 图例：标题下方横向排列，格式为「彩色圆点 + 渠道名 · 模型别名」，不直接显示数值。
5. 悬停交互：鼠标悬停数据点时显示 Tooltip，内容为该时间点各系列的数值（`xxx.x tok/s`，保留一位小数）与时间标签。
6. 坐标轴：Y 轴线性刻度、按数据自动量程，单位标注 tok/s；X 轴按档位标注时间刻度（分钟档 `HH:mm`、小时档 `HH:mm` / `MM-dd`、天档 `MM-dd`）。
7. 空点：某时间桶内无 `success` 请求时该点为空，折线在空点处断开为缺口，**不做 0 值填充**（避免把「无请求」误读为「速率归零」）。
8. 数据点标记：空心圆点；每个系列的最新一个有效点高亮。

**处理规则**：

1. 分区可见性跟随网关启用状态：未启用时显示引导卡（说明 + 「前往设置」跳转 FR-09）；已启用但窗口内无请求时图表区显示空态文案，不隐藏分区。
2. 数据直接查询 `requests` 表，按时间桶 +（渠道, 模型）分组聚合，面板不维护独立缓存；每次落库后自动刷新当前窗口。
3. 粒度选择持久化到 AppSettings，下次打开面板沿用上次档位；默认档位为「分钟」。

**布局约束**（硬约束，实现不得违反）：

- 面板窗口固定 `320×520`，切 Tab 禁止修改窗口 frame，仅在 SwiftUI 内部动画内容区高度；视口高度经 `PopoverLayout.clampedViewport` clamp 在 `[200, 360]`，建议路由常量 `viewportHeight: 320`。
- 分区栏总宽固定 `268pt`、在 `292pt` 内容区内居中；新增第 6 个分区后，胶囊宽度常量须按 268pt 总宽重新推导（如选中 `68pt` / 未选中 `34pt` / 间距 `6pt`），禁止拉伸胶囊或摊大间距突破内容区。
- 选中态宽度变化与相邻胶囊重排在同一 `120ms` 动画事务内完成。
- 颜色统一取自 `PopoverPalette` 令牌体系（浅色/深色双值自适应）；折线系列色从同一令牌体系派生一组数据可视化色（建议蓝 / 绿 / 金，对齐参考图），禁止散落硬编码色值。
- 图表使用系统 Swift Charts 框架实现（系统框架，不违反 APP-09 不新增第三方依赖红线）。

**异常**：落库失败时分区顶部显示持久性错误提示条，直至写入恢复。

---

### FR-08 请求历史独立窗口

**目的**：全量历史请求的查看、筛选与复算，覆盖面板分区装不下的明细。

**窗口形态**：独立 WindowController（不与其他功能复用窗口实例），从面板分区入口按钮打开。

**表格列**（数据源：`requests` 表，时间倒序，分页加载，见规则 1）：

| 列 | 内容 |
|------|------|
| 时间 | `created_at`，展示本地时间（精确到秒） |
| 模型 | 客户端请求的模型别名 |
| 渠道 | 实际完成响应的渠道名（显示名称而非内部 ID） |
| 状态 | success / failed / cancelled / interrupted 四态，颜色区分 |
| Tokens | Input / Output Token 数；来源非 `usage` 时附估算标记（如 `≈`），来源见 §3.3 |
| TTFT | 毫秒 |
| TPS | Output TPS（非流式或不可计算时显示 `—`） |
| 总耗时 | 毫秒 |
| 切换原因 | `retry_reason` 简要展示（如 `quota_exhausted`），无切换显示 `—` |
| 操作 | 固定在表格最右侧列：查看详情、复制错误信息（仅失败态）、删除单条 |

**处理规则**：

1. **分页加载（v2.1 新增，决议 Q-31）**：默认每页 50 条，基于 `created_at` 游标分页；筛选条件（模型别名 / 渠道 / 状态 / 时间范围组合）全部由 SQLite `WHERE` 子句执行，**禁止在内存中加载全量记录再筛选**；筛选不改变默认排序。
2. 趋势展示由面板「网关」分区（FR-07）承载；**历史窗口第一版不含趋势图**，历史趋势图增强列为 P2 迭代（决议 Q-32）。
3. 删除单条记录需二次确认；第一版不提供批量删除与导出；不做自动清理（与 FR-06 一致）。
4. 详情页展示该请求全部字段原文（含 Token 来源、retry_reason、`error` 完整描述）。
5. **加权 TPS 口径（P2 迭代，决议 Q-33）**：后续在历史窗口提供统计口径切换——简单平均 TPS（`AVG(output_tps)`，平均单次请求速度，FR-07 速率图口径）与加权平均 TPS（`SUM(output_tokens) / SUM(generation_ms)`，整体 Token 吞吐量），让用户区分两种含义。第一版仅保留简单平均。

**异常**：数据库不可读时窗口显示整窗错误态，不显示空白表格。

---

### FR-09 渠道配置 UI（偏好设置「AI 网关」Tab）

**目的**：模型别名与渠道的全套配置在原生设置页完成，替代手编 JSON。

**接入方式**：`SettingsTab` 新增 `aiGateway`，标题「AI 网关」，归属「生产力工具」分组，补齐 subtitle / 图标渐变 / 搜索关键词（如：网关、AI、代理、渠道、路由、Token、TPS、gateway、API），保证设置搜索可命中。

**页面结构**（自上而下）：

| 区块 | 内容 |
|------|------|
| 总开关 | 网关启用 / 停用，**默认停用**（新装 / 重置后不监听端口、不随 App 启动自动开启，手动开启后持久化，决议 Q-37）；关闭时 HTTP 服务立即停止，面板分区切换为引导卡 |
| 服务配置 | 监听端口（默认 8317，修改后重启网关生效）；监听地址固定 `127.0.0.1`，不提供编辑控件（决议 Q-21）；可选网关访问密钥 `server.api_key`（密码框，留空 = 不鉴权，存 Keychain） |
| 模型别名列表 | 每行：别名 + 渠道组成员（多选，组内顺序即尝试顺序）；新增 / 编辑 / 删除 |
| 渠道列表 | 每行：名称、启用开关（禁用即不参与路由与故障切换）、base_url、api_key（掩码显示，如 `sk-***xxxx`，点击可修改）、上游模型名、排序（拖拽或上下移，直接决定渠道组尝试顺序，决议 Q-22）、代理标记（已配置代理时显示）、冷却剩余时间（用量耗尽时展示，FR-05 规则 6）、测试连接按钮；新增 / 编辑 / 删除 |
| 渠道编辑弹层 | base_url、api_key、上游模型名、代理配置（类型 无 / HTTP / HTTPS / SOCKS5、主机、端口、可选认证用户名密码，认证凭据存 Keychain）；「测试连接」发起探测并内联展示结果 |

**处理规则**：

1. 所有可编辑字段（含无值的空字段）始终显示，不因空值隐藏控件。
2. 保存即生效：每次请求前读取当前配置快照，进行中的请求继续使用旧快照（决议 Q-11，FR-04 规则 5）。
3. 校验错误（§5 校验规则）内联显示在对应字段下方，逐条列出；存在错误时保存被阻止。
4. 删除被渠道组引用的渠道前必须先从所有渠道组移除，否则删除按钮禁用并提示引用位置。
5. **凭据存储（v2.1 修订，决议 Q-20）**：渠道 api_key、代理认证凭据与网关访问密钥均存 **macOS Keychain**，AppSettings 仅保存 Keychain 条目引用；UI 仅掩码显示，不提供明文导出；编辑时留空表示保持原值（服务级密钥留空表示不鉴权）。
6. 修改端口后需重启网关服务（提示条说明），其余配置项保存即时生效。
7. **模块默认不启用（v2.2 新增，决议 Q-37）**：Feature 初始状态 disabled，新装 / 重置后不监听端口、不随 App 启动自动开启；用户手动打开总开关后状态持久化，后续随 App 启动自动恢复。总开关关闭仅停服务，渠道与模型配置全部保留。
8. **渠道手动启停（v2.2 新增，决议 Q-37）**：渠道级启用开关即时生效——禁用渠道不参与路由与故障切换（FR-04 规则 1），但不影响历史记录与统计；渠道组内全部渠道被禁用时，对应模型请求返回 `503 no_available_channel`，渠道行给出提示但不阻止保存（给用户临时下线某模型的自由）。
9. **测试连接（v2.2 新增，决议 Q-38）**：渠道行与编辑弹层的「测试连接」按钮发送最小探测请求（`GET <base_url>/models`，经该渠道配置含代理直连上游），展示成功 / 失败与**接口延迟（RTT 毫秒）**；失败展示错误原因（脱敏，不含密钥）；测试请求**不计入 requests 统计与速率图**；测试进行中按钮显示加载态，未完成前可取消。**结果定位（v2.4，决议 Q-51）**：仅命名为「连接测试」——只证明 `/models` 端点可达与延迟，**不代表** Chat Completions / Responses 端点可用、模型存在或代理能稳定支撑长时间 SSE，UI 不宣称「模型兼容性测试」；真实模型探测列为 P2 可选项，不混入连接测试。**独立超时策略（决议 Q-58）**：连接 10s、`/models` 响应 15s、响应体上限 1 MB、用户取消立即生效，不与正常请求的三段超时共用。
10. **渠道代理（v2.2 新增，决议 Q-39）**：渠道级可选代理配置（类型 / 主机 / 端口 / 可选认证）；配置后该渠道全部上游请求（含连接测试）经代理发出，未配置渠道保持直连；代理仅作用于上游请求，不影响网关对客户端的监听服务；代理不可达按连接类故障走 FR-05 切换（retry_reason=`connect_failed`）。

**异常**：配置错误导致网关无法启动时，本 Tab 顶部显示持久性错误横幅（含错误明细），Feature 状态在权限中心 / 面板同步可见 `failed`。

---

## 5. 配置规格（AppSettings 存储）

**存储位置**：CalmBar AppSettings（UserDefaults / 用户级 plist）。FR-09 的设置 UI 是唯一编辑入口，不提供 config.json 文件与热重载概念（决议 Q-11 / Q-12）。下列 JSON 为配置的**逻辑数据模型**，字段名即 AppSettings 序列化键名。

**安全口径（v2.1 修订，决议 Q-20）**：渠道 api_key 与网关访问密钥存 **macOS Keychain**（长期有效的敏感凭据不应落明文 plist——UserDefaults 的文件权限与备份行为不可控，不等同于 chmod 600 的配置文件）；AppSettings 仅保存 Keychain 条目引用（如渠道名派生的 account 标识），凭据的读写经 Service 层封装完成。

**逻辑模型示例**：

```json
{
  "server": {
    "port": 8317,
    "api_key_ref": "calmbar.aigateway.server"
  },
  "models": {
    "gpt-6": { "channels": ["channel-a", "channel-b"] }
  },
  "channels": {
    "channel-a": {
      "base_url": "https://api-a.example.com/v1",
      "api_key_ref": "calmbar.aigateway.channel.channel-a",
      "model": "gpt-6",
      "enabled": true
    },
    "channel-b": {
      "base_url": "https://api-b.example.com/v1",
      "api_key_ref": "calmbar.aigateway.channel.channel-b",
      "model": "gpt-6",
      "enabled": true,
      "proxy": { "type": "socks5", "host": "127.0.0.1", "port": 1080 }
    }
  }
}
```

> 监听地址固定 `127.0.0.1`，无配置项（决议 Q-21）。`api_key_ref` 为 Keychain 条目标识；渠道允许空 api_key（本地无鉴权上游，此时不创建 Keychain 条目）。`proxy` 可选，配置后该渠道全部上游请求经代理发出（决议 Q-39）。

**字段表**：

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `server.port` | 否 | Int | 默认 `8317` |
| `server.api_key_ref` | 否 | String | 网关级鉴密钥的 Keychain 引用：默认空 = 不校验客户端凭据；设置后客户端必须携带 `Authorization: Bearer <key>`（见 FR-01 规则 3，恒定时间比较） |
| `models.<alias>.channels` | 是 | [String] | 渠道组，引用 `channels` 中的渠道名；**数组顺序即尝试顺序（第一权威）**，同组渠道须模型能力与请求参数兼容（FR-04） |
| `channels.<name>.base_url` | 是 | String | 上游端点，**已含 `/v1` 版本路径**；网关按客户端请求协议在其后拼接 `/chat/completions` 或 `/responses`（拼接规范化见下方规则） |
| `channels.<name>.api_key_ref` | 否 | String | 上游凭据的 Keychain 条目引用；允许为空（本地无鉴权上游） |
| `channels.<name>.model` | 是 | String | 该渠道的上游实际模型名 |
| `channels.<name>.auth_header_type` | 否 | String | 上游认证头类型：`bearer`（默认）/ `api-key` / `x-api-key`（决议 Q-54）；自定义 Header 与 Query 认证列 P2 |
| `channels.<name>.enabled` | 否 | Bool | 默认 `true`；`false` 时该渠道不参与路由与故障切换（FR-04 / FR-09，决议 Q-37） |
| `channels.<name>.proxy` | 否 | Object | 可选代理配置：`type`（`http` / `https` / `socks5`）、`host`、`port`、可选 `username_ref` / `password_ref`（Keychain 引用）；配置后该渠道全部上游请求（含连接测试）经代理发出，未配置直连（决议 Q-39） |

**Base URL 规范化（v2.1 新增，决议 Q-34）**：

1. 必须是合法 `http://` 或 `https://` URL（允许 http，用于本地模型如 Ollama）；
2. 末尾 `/` 自动剥除（`https://api.example.com/v1/` → `https://api.example.com/v1`），避免拼出 `//chat/completions`；
3. 保留用户填写的路径前缀（如 `/v1`、`/openai/v1`），**禁止自动追加或重复拼接 `/v1`**；
4. 拒绝含查询参数（`?`）或片段（`#`）的 URL，保存时内联报错；
5. 上游 3xx 重定向一律不跟随，视为连接类故障走 FR-05 切换（防 API Key 被转发到其他主机）。

**校验规则（保存时 UI 内联逐条报错；服务启动时兜底校验，拒绝启动但不退出 App，决议 Q-15）**：`channels` 引用悬空 / 模型渠道组为空 / 必填字段缺失或类型不符 / `port` 超出 1–65535 / `base_url` 违反上述规范化规则 / `proxy.host` 非法或 `proxy.port` 超出 1–65535 或 `proxy.type` 不在枚举内。渠道组内全部渠道禁用**不属校验错误**（允许保存，路由时按 FR-04 异常表处理）。

---

## 6. 工程结构约束（并入 CalmBar 主 App）

### 6.1 目录结构（代码全部位于 `app/Sources/CalmBar/`，不创建独立子项目）

```
app/Sources/CalmBar/
├── Features/AIGatewayFeature.swift
├── Services/AIGateway/
│   ├── GatewayServer.swift        # HTTP 服务启动与监听
│   ├── GatewayRouter.swift        # 模型和渠道路由
│   ├── GatewayProxy.swift         # 上游 API 请求转发
│   ├── SSEParser.swift            # SSE 数据解析
│   ├── TPSMeter.swift             # Token 和速度统计
│   ├── Failover.swift             # 故障检测和渠道切换
│   ├── GatewayConfig.swift        # AppSettings 配置读取与校验
│   └── GatewayDatabase.swift      # SQLite 数据存储
└── UI/
    ├── Popover/Gateway/GatewaySectionView.swift          # 面板「网关」分区（FR-07）
    ├── Windows/GatewayHistoryWindowController.swift      # 请求历史独立窗口（FR-08）
    └── Settings/Tabs/AIGatewaySettingsTab.swift          # 偏好设置「AI 网关」Tab（FR-09）
```

原规划的 `main.swift` 不再需要：进程入口即 CalmBar 主程序，网关生命周期由 `AIGatewayFeature` 的 `start()` / `stop()` / `cleanup()` 驱动。

### 6.2 文件职责

| 文件 | 职责 |
|------|------|
| AIGatewayFeature.swift | Feature 生命周期、命令注册、状态发布（模板 §2.3） |
| GatewayServer.swift | HTTP 服务启动与监听（进程内，随 Feature 启停）；内部按 HTTP1Parser / HTTPResponseWriter / HTTPConnection 三个子职责组织（决议 Q-53） |
| GatewayRouter.swift | 模型和渠道路由（FR-04） |
| GatewayProxy.swift | 上游 API 请求转发（FR-01 / FR-02） |
| SSEParser.swift | SSE 数据解析（chunk 边界、结束事件、usage 帧、有效输出内容判定） |
| TPSMeter.swift | Token 和速度统计（FR-03，§3.2 / §3.3） |
| Failover.swift | 故障检测和渠道切换（FR-05） |
| GatewayConfig.swift | AppSettings 配置读取与校验（§5） |
| GatewayDatabase.swift | SQLite 数据存储（FR-06） |
| GatewaySectionView.swift | 面板「网关」分区视图（FR-07） |
| GatewayHistoryWindowController.swift | 请求历史独立窗口（FR-08） |
| AIGatewaySettingsTab.swift | 渠道配置设置 Tab（FR-09） |

**内部职责边界（v2.1 新增，决议 Q-35）**：物理文件数可按需增加（R-08 修订），但各文件内部职责必须按下列边界组织，禁止相互侵入：

| 模块 | 只负责 | 不负责 |
|------|--------|--------|
| HTTP 协议层（HTTP1Parser / HTTPResponseWriter / HTTPConnection，v2.4 明确，决议 Q-53） | 请求行与 Header 解析、Content-Length / Chunked 解码、Keep-Alive、请求体分段接收、SSE 响应写入、客户端断开检测、并发连接管理 | 任何网关业务逻辑（路由 / 切换 / 统计） |
| GatewayProxy | 请求转发、连接生命周期 | 统计触发、切换决策 |
| SSEParser | SSE 协议解析（跨读取边界切分事件、识别有效内容 / usage / 结束事件） | 统计计算、转发本身（原始数据不经 Parser 重组，见 FR-02） |
| TPSMeter | 内部分为 RequestMetrics（时间打点）/ TokenEstimator（估算）/ UsageCollector（usage 校准）/ MetricsCalculator（TPS 计算）四个子职责 | HTTP 层逻辑 |
| Failover | 故障判定、切换决策、retry_reason 记录、quota 冷却标记 | 直接读写 Proxy 内部状态（通过独立的尝试状态结构交互） |
| GatewayDatabase | SQL 执行、行 ↔ 模型映射、分页与聚合查询（Repository 职责） | 业务逻辑 |

**HTTP 协议层资源与解析安全限制（v2.5 新增，决议 Q-64）**——HTTP1Parser / HTTPConnection 必须实现下列限制，防慢速攻击、请求走私与并发内存压力；单请求大小限制（20 MB 请求体 / 64 MB 非流式暂存 / 8 MB 提交前暂存）之外，增加连接级与全局级约束：

| 限制项 | 默认值 | 触发后行为 |
|--------|--------|------------|
| 单请求 Header 总大小 | 32 KB | 返回 `431` 并关闭连接 |
| 单请求 Header 字段数量 | 100 | 返回 `431` 并关闭连接 |
| Header 接收超时（慢速攻击防护） | 15s | 关闭连接，不产生请求记录 |
| 请求体接收超时（Content-Length 已声明但迟迟不收齐） | 60s | 关闭连接，记录 `status=interrupted` |
| `Content-Length` 与 `Transfer-Encoding` 同时存在 | — | 返回 `400` 并关闭连接（请求走私防护，RFC 7230 优先 TE） |
| Chunked 非法长度行 / 异常结束（缺终结 chunk） | — | 返回 `400` 并关闭连接 |
| Keep-Alive 空闲超时 | 60s | 关闭连接 |
| 单连接最大请求数（Keep-Alive） | 1000 | 响应后正常关闭连接 |
| 最大并发客户端连接数 | 64 | 超出直接关闭新连接 |
| 最大并发代理请求数（进行中上游请求） | 16 | 超出时新请求返回 `503`，code `overloaded`，不排队 |
| 全局暂存内存预算（所有请求的提交前暂存 + 非流式暂存合计） | 256 MB | 超预算时新请求返回 `503` `overloaded`；进行中请求不受影响 |

> 并发内存压力说明：20 MB / 64 MB / 8 MB 均为**单请求**限制，16 个并发代理请求理论上限约 1 GB——全局暂存预算 256 MB 与并发上限共同兜底，保证网关随主 App 常驻运行时的内存占用可控。

### 6.3 测试清单（v2.1 扩充并发与边界用例）

| 测试项 | 断言要点 |
|--------|----------|
| SSE 事件流透传 | 网关转发与直连上游的 SSE 事件流内容逐事件一致（含 usage 帧与 `[DONE]`），旁路解析不改变转发数据（FR-02 规则 1） |
| SSE 跨读取边界 | 单个事件拆成多个 TCP 数据块 / 多事件合并同一数据块，均正确识别并转发 |
| 指标计算 | TTFT / Generation / TPS / Total 按公式复算一致；usage 校准覆盖估算值；**非流式请求 TPS 为 NULL**（Q-25） |
| 估算兜底 | 上游不返回 usage 时仍能产出 Token 与 TPS，不按块数计数，来源标记为估算（Q-19） |
| usage=0 保留 | 上游合法返回 0 Token 时保留 0，不被估算覆盖；负数/非整数/超范围视为非法走估算 |
| 工具调用与 reasoning | `tool_calls` 参数分多次输出不丢失不修改；`reasoning_content` / `refusal` 正确识别并纳入估算（Q-26） |
| 故障切换触发 | DNS / TCP / TLS / 超时 / 429 / 5xx / 3xx 逐类触发切换并透传成功，retry_reason 按判定表落库 |
| 故障切换不触发 | 401 / 403 / 400 / 404 透传不切换；已输出后中断不拼接 |
| 用量限制切换 | quota 类 429 / 402 切换下一渠道并打冷却标记；冷却期路由跳过；全部冷却时按原顺序尝试；到期恢复；瞬时限流不打标记（Q-24） |
| 提交点边界 | 已收上游 200 响应头但首内容前断开 → 仍能切换（200 响应头已暂存、未提交客户端） |
| 心跳拖延 | 首内容前持续收到 SSE 注释 / 空事件 / role-only chunk：First Content Timeout 到点触发切换，不无限等待 |
| 空闲超时 | 首个有效内容后上游停止输出：Idle Read Timeout 到点关闭连接并记 interrupted，不切换 |
| 客户端断开 | 取消上游请求并落库 `status=cancelled`；不影响其他并发请求 |
| 落库完整性 | 四种 status 场景各落库一条，字段与 FR-06 口径一致（含来源、retry_reason） |
| 并发写入 | 多个请求并发终结写 SQLite（WAL 模式）不丢记录、不阻塞 UI 查询 |
| 配置快照隔离 | 请求进行中修改配置：该请求继续使用旧快照直至终结，新请求用新快照（FR-04 规则 5） |
| 配置校验 | 各类非法配置逐条报错（UI 内联 + 启动兜底），不退出进程 |
| 配置即时生效 | 修改 AppSettings 渠道配置后，下一次请求即按新配置路由（Q-11） |
| 网关鉴权 | `server.api_key` 设置后：无凭据/错凭据返回 `401`（恒定时间比较）；正确凭据放行；未设置时不校验；`Host` 非回环返回 421 |
| 大小限制 | 请求体超 20 MB 返回 `413` 不读入；非流式响应超 64 MB 记 `response_too_large`，按执行状态未知类切换（Q-56） |
| 重定向不泄露 | 上游 3xx 一律不跟随，API Key 不被转发到其他主机 |
| App 退出清理 | Feature `cleanup()` / 重复 start / stop：端口释放、进行中请求终止、重复启停无副作用 |
| 非流式大响应 | 64 MB 内正常转发，不造成无限内存占用 |
| Responses 终止事件 | 无有效 delta 时收到 `response.failed` / `response.incomplete`：立即终止，不等待 First Content Timeout、不切换渠道（Q-43） |
| Responses 多模态传输提交 | 纯音频输出请求：多模态 delta 触发传输提交，客户端收到完整事件流（含此前暂存事件）；TTFT / TPS 落库 NULL；统计与传输提交分离（Q-61） |
| 终止事件兜底提交 | 仅有状态事件 + `response.completed`（无任何传输提交事件）：客户端仍收到全部暂存事件后正常结束（Q-61） |
| 提交前暂存总量上限 | 上游持续发送不触发传输提交的事件累计超 8 MB：按执行状态未知类切换，`retry_reason=precommit_buffer_exceeded`，耗尽后客户端收统一 502（Q-60） |
| response_id 映射粘性 | Responses 成功请求记录 response_id → 渠道映射；后续携带 `previous_response_id` 的请求路由到映射渠道（即使非数组首位）；映射渠道禁用 / 失败返回 `502 stateful_channel_unavailable`；容量 1024 LRU 与 24h 过期生效；`store=false` 不记录（Q-62） |
| 浏览器跨源防护 | `Sec-Fetch-Site: cross-site` → 403；`Origin` 不匹配回环 → 403；`OPTIONS` → 405；POST Content-Type 非 JSON → 415；正常 curl / SDK 请求（无 Origin 头）不受影响（Q-63） |
| HTTP 层资源限制 | 超 32 KB Header / 100 字段 → 431；`Content-Length` + `Transfer-Encoding` 并存 → 400；慢速 Header 15s / Body 60s 超时断连；并发代理请求超 16 或全局暂存预算超 256 MB → 新请求 `503 overloaded`（Q-64） |
| incomplete 落库 | `response.incomplete` 终止：`status=success`，`error` 记录不完整原因摘要，历史窗口详情可区分正常结束与截断（Q-65） |
| Responses 多模态事件 | 音频 / 图像增量事件原样透传、解析器不崩溃；触发传输提交但不触发统计打点（Q-59 / Q-61，v2.5 修订） |
| 有状态请求禁切换 | 带 `previous_response_id` 的请求：映射命中渠道失败 / 禁用 / 冷却返回 `502 stateful_channel_unavailable`，不切换；映射未命中按数组顺序路由且不切换；无状态请求不受影响（Q-44 / Q-62） |
| 非 2xx 立即分类 | 上游 401 / 429 JSON 错误：立即读取错误体分类处理，不等待 SSE 有效内容（Q-45） |
| 错误体分类 | 403 按 `quota_exceeded` / `permission_denied` / 未识别分类处理；429 区分 `rate_limit` / `insufficient_quota`；未识别 403 不切换（Q-46） |
| 冷却作用域 | 模型级额度耗尽只冷却（渠道, 模型），同渠道其他模型可继续路由；账户级冷却整渠道；无法判断默认整渠道（Q-47） |
| SSE 协议边界 | `\r\n` 换行、多行 `data:`、UTF-8 跨读取块、未知事件：正确解析或安全跳过，转发字节流不受影响（Q-49） |
| 压缩响应 | 上游请求带 `Accept-Encoding: identity`；上游仍返回压缩内容时原样转发、解析器安全跳过（Q-50） |
| 非流式超限 | 响应体超 64 MB：`retry_reason=response_too_large`，执行状态未知类切换，客户端收统一 502（Q-56） |
| models 列表一致性 | 组内全部渠道手动禁用的别名不出现在 `/v1/models`；quota 冷却不影响列表（Q-57） |
| 测试连接独立超时 | 异常上游挂起时测试连接 15s 内返回失败并可取消，不长时间占用资源（Q-58） |
| 模块默认关闭 | 新装 / 重置后 Feature 为 disabled、不监听端口；手动开启后随 App 启动自动恢复（Q-37） |
| 渠道启停路由 | 禁用渠道不参与路由与切换；组内全部禁用返回 `503 no_available_channel`；启停不影响历史统计（Q-37） |
| 连接测试 | 测试请求经渠道配置（含代理）发出，展示 RTT 与脱敏错误；不计入 requests 统计与速率图（Q-38） |
| 渠道代理 | 配置代理的渠道上游请求经代理发出、未配置直连；代理不可达按 `connect_failed` 切换（Q-39） |
| Responses 透传 | `/v1/responses` 流式事件流逐事件透传一致；非流式响应体完整转发；`model` 别名正确改写且端点为 `<base_url>/responses`（Q-40） |
| Responses 统计 | `response.completed` 的 `usage.input_tokens` / `usage.output_tokens` 正确映射落库；delta 事件触发 TTFT 打点；状态事件不重置 First Content Timeout（Q-41） |
| Responses 切换 | Responses 请求首内容前上游失败可切换；无 usage 时估算兜底并标记来源 |

### 6.4 新功能接入 10 项准入原则对照（`doc/design/CalmBar 新功能接入模板.md`）

| 原则 | 落实方式 |
|------|----------|
| Feature 元信息 | `FeatureID.aiGateway`，displayName「AI 接口网关」，category `.productivity`；**默认状态 disabled（新装 / 重置不自动开启，Q-37）** |
| Service 边界 | 全部 HTTP / 转发 / SQLite 逻辑封装在 `Services/AIGateway/`，UI 层不裸写底层调用 |
| 权限声明 | 无系统权限需求（本机回环监听 + 网络客户端），`requiredPermissions: []`；无需新增 Info.plist 权限项 |
| Command 注册 | 注册命令：开启 / 关闭 AI 网关、打开请求历史窗口（含中文别名），支持命令面板搜索 |
| Dashboard 准入 | 网关运行状态与速率趋势属高频状态，以独立分区进入菜单栏面板（R-12 明确要求，超出"默认不进首页"的保守口径，属用户显式指令） |
| Settings 项 | AppSettings 新增 aiGateway 配置域；SettingsView 新增「AI 网关」Tab（FR-09） |
| Recovery 恢复行为 | Feature `cleanup()` 停止 HTTP 服务并释放端口；App 退出 / 崩溃时端口随进程释放，进行中请求按 FR-02 客户端断开语义处理 |
| 测试清单 | `app/Tests/CalmBarTests/AIGatewayTests`，见 §6.3 |
| 失败可见 | 端口占用 / 配置校验失败 / 全渠道失败 / 落库失败均在设置页或面板可见，禁止静默失败 |

### 6.5 构建约束

- 随 `app/Package.swift` 构建（`swift build`），无独立 SwiftPM 包与独立产物；不依赖 Docker、Node、Python 等外部运行时。
- **除 Sparkle 外不新增第三方依赖**（APP-09 红线）：HTTP 服务用 **Network.framework**（`NWListener` / `NWConnection`）实现（v2.1 定案，决议 Q-36），**禁止从 BSD socket 手写完整 HTTP 协议栈**；注意 Network.framework 只提供连接能力、非完整 HTTP Server 框架——HTTP 协议层（解析 / 写入 / 连接管理）按 §6.2 职责表自行实现并与业务分层，便于单测（决议 Q-53）；不引入 Hummingbird、Vapor、swift-nio 等第三方服务框架。
- **代理 PoC 前置（v2.4 新增决议 Q-52；v2.5 增补压缩验证场景，决议 Q-66）**：渠道代理功能动工前先做技术验证——HTTP / HTTPS / SOCKS5 三种代理连接、SOCKS5 下的 SSE 长连接、代理认证、**URLSession 压缩行为验证**共六个场景，各产出一个小型 PoC（放 `UI/Spike` 目录，验收后整目录删除）；URLSession 对 SOCKS5 的支持方式与 HTTP/HTTPS 代理不同，不能默认同样简单；压缩验证须实测确认：URLSession 是否自动解压 gzip / br 响应、自动解压后 `Content-Encoding` 头是否保留、网关转发给客户端的响应头与响应体编码声明是否一致、旁路解析器看到的数据与转发数据是否同源（Q-66）；PoC 不通过则把第一版代理类型收窄为 HTTP / HTTPS / 调整压缩处理策略并回改本 PRD，不留到开发后期暴露。
- macOS 目标版本 `.macOS(.v14)`，对齐主 App。
- SQLite 使用系统自带 libsqlite3 或 SwiftPM 轻量封装，不引入 ORM。
- 服务器逻辑不得依赖 AppKit / SwiftUI（保持 Service 可测）；UI 通过 `@Published` 状态订阅服务，遵守主 App 并发约定（`@MainActor`，耗时工作后台队列）。

---

## 7. 待定项决议记录

> **v1.0 评审（Q-01 ~ Q-09）**：9 项待定/假设全部决议，正文对应位置已同步更新。
> **v2.0 修订（Q-10 ~ Q-16）**：并入 CalmBar 主 App（R-11）引出的新决策，正文对应位置已同步更新。
> **v2.1 修订（Q-18 ~ Q-36）**：外部评审回填（故障风险分级、三段超时、非流式口径、Token 来源、Keychain、用量限制切换等 20 项）引出的新决策；同时修订 Q-01（Keychain）、Q-05（三段超时）、Q-07（允许 quota 冷却一种跨请求状态）。
> **v2.2 修订（Q-37 ~ Q-39）**：模块默认不启用、渠道手动启停、渠道连接测试与延迟测量、渠道级代理配置（R-15 ~ R-17）；同时修订 Q-16（连接测试由"不做"转为第一版范围）。
> **v2.3 修订（Q-40 ~ Q-41）**：新增 OpenAI Responses 协议透传（R-18）；同时修订 R-10（「仅 Chat Completions」→ 支持两种 OpenAI 协议透传）。
> **v2.4 修订（Q-42 ~ Q-59）**：第二轮外部评审回填（Responses 端点范围、事件分级与终止语义、有状态粘性、统一上游状态机、错误体分类、冷却作用域、SSE 边界、压缩、认证类型等 19 项）；同时修订 Q-41（事件分级细化）。
> **v2.5 修订（Q-60 ~ Q-66）**：第三轮边界闭合评审回填（提交前暂存总量上限、统计与传输提交分离、previous_response_id 渠道映射、浏览器跨源防护、HTTP 层资源限制、incomplete 落库口径、URLSession 压缩验证共 7 项）；同时修订 Q-44（方案 A：第一版实现映射表）、Q-50（增补压缩行为验证）、Q-52（PoC 增补第六场景）。

| 编号 | 待定项 | 决议 | 理由 |
|------|--------|------|------|
| Q-01 | 渠道 `api_key` 字段 | 允许为空（本地无鉴权上游）；存储方式 **v2.1 修订为 macOS Keychain**（Q-20），AppSettings 仅存引用 | 原决议"明文 + chmod 600"不严谨——UserDefaults 文件权限与备份行为不可控，不等同 0600 配置文件 |
| Q-02 | 网关鉴权 | 新增可选 `server.api_key`（默认空 = 不鉴权）；v2.1 增补恒定时间比较与 Host 校验（Q-21） | 防本机其他进程盗刷上游额度；仅一个字段 + Bearer 头校验，不构成用户体系 |
| Q-03 | `stream_options` 注入 | 保持保守透传，不注入；usage 缺失走估算兜底 | 不改写客户端请求体是透传原则底线；主流客户端默认已带 `include_usage`，校准覆盖率可接受；若实测估算误差不可接受，后续版本再加渠道级开关 |
| Q-04 | Token 估算系数 | `tokens = ceil(CJK 字符数 × 1 + 非 CJK 非空白字符数 × 0.25)`，下限 1；v2.1 修订：估算输入扩展至 reasoning_content / tool_calls / refusal（Q-26），并落库标记来源（Q-19）；已知对代码/JSON/多模态偏差大，属可接受兜底 | 英文约 4 字符/token、中文约 1 字符/token 的业界通行折中；来源标记让用户可区分校准值与估算值 |
| Q-05 | 超时默认值 | **v2.1 修订为三段超时（Q-29）**：Connect 10s / First Content 300s（仅有效内容重置，心跳不算）/ Idle Read 120s | 原"无字节超时 300s + 首字节后无超时"存在两个漏洞：上游可用心跳无限拖延、流中 stall 无限挂起 |
| Q-06 | `created_at` 单位 | Unix 毫秒 | 与 `*_ms` 列同量纲 |
| Q-07 | 渠道健康状态 / 热重载 / 保留策略 | 无热重载、无保留策略保持；**v2.1 修订**：跨请求渠道状态允许且仅允许"用量耗尽冷却标记"一种（Q-24）；数据不做自动清理但允许手动删除单条（Q-31 相关） | quota 耗尽是持续状态，每次请求先打已耗尽渠道再切换会浪费一次完整往返；临时 429 与 5xx 仍无跨请求状态，符合优先级语义 |
| Q-08 | macOS 目标版本 | `.macOS(.v14)`，对齐主 App | MiniGateway 无 14+ API 硬依赖，monorepo 内统一平台避免工具链摩擦 |
| Q-09 | 已输出后上游中断 | 直接关闭客户端连接，不伪造 `[DONE]` | 伪造完成事件会让客户端把残句当完整回答静默接受；主流 SDK 将"[DONE] 前连接关闭"识别为 incomplete stream 错误，行为诚实且可检测 |
| Q-10 | 独立子项目 vs 并入 CalmBar | 并入主 App：FeatureID `aiGateway`，服务在 `Services/AIGateway/`，HTTP 服务随 App 进程启停 | 用户指令（R-11）；免去单独安装、单独守护与"忘了启动网关"问题 |
| Q-11 | 配置存储与生效方式 | AppSettings（UserDefaults）存储；FR-09 设置 UI 为唯一编辑入口；每次请求前读取当前配置快照，保存即时生效（端口变更除外，需重启网关） | UI CRUD 替代手编 JSON，消除配置文件路径问题；配置量小（几 KB），每请求读取无性能影响 |
| Q-12 | JSON 配置导入 / 导出 | 第一版不做 | UI CRUD 为唯一事实来源，避免双份配置来源产生漂移；后续有迁移需求再评估 |
| Q-13 | 面板分区命名与数据粒度 | Tab 命名「网关」（与既有温控/守护/工具/监控/声音不重复）；分区以速率折线图为主体，档位为「近 10 分钟每分钟 / 近 10 小时每小时 / 近 10 天每天」三档，默认分钟档；不展示秒级曲线 | 与现有分区标签零重复；窗口统一 10 个桶，三档信息密度一致 |
| Q-14 | SQLite 库文件路径 | 固定 `~/Library/Application Support/CalmBar/aigateway.db`，不可配置 | 并入 App 后不再有"可执行文件相对路径"语义；Application Support 为 macOS 标准数据位置 |
| Q-15 | 端口占用 / 配置错误的处理 | 不退出 App：Feature 置 `failed`，设置页与面板显示明确错误，网关拒绝启动，主 App 其他功能不受影响 | 独立进程的 fail-fast 退出语义不适用于承载十几个常驻功能的主 App |
| Q-16 | 渠道连通性测试按钮 | **v2.2 修订为第一版范围**（Q-38）：「测试连接」发送最小探测请求，展示连接结果与接口延迟 RTT；测试不计入统计 | 原决议"不做"基于最小实现边界；用户需求 R-16 显式要求测试连接与接口延迟，且实现成本低（复用渠道配置发一个 GET） |
| Q-17 | 速率折线图口径 | 每点 = 该时间桶内全部 `success` 请求 `output_tps` 的简单平均值（可复算：`AVG(output_tps)`）；空桶不画点、折线断开为缺口，不填 0；系列按窗口内请求数降序最多展示 4 条 | 简单平均与 SQL 聚合一致、可复算验证；填 0 会把"无请求"误读为"速率归零"；面板 292pt 宽度最多容纳 4 条可辨识折线与图例 |
| Q-18 | 故障切换的重复执行风险 | 故障按「未执行类 / 执行状态未知类」分级：连接类与 429 安全切换；5xx、读超时、首内容前断开可切换但落库 `retry_reason` | "未向客户端输出 ≠ 上游未执行"——渠道 A 可能已推理并计费后失败，渠道 B 重复执行（含工具调用的副作用风险）；retry_reason 让历史记录可分析"连接问题 vs 上游执行问题 vs 用量耗尽" |
| Q-19 | usage=0 与 Token 来源 | usage 存在且合法（**含 0**）一律保留；仅缺失/负数/非整数/超范围才估算；新增 `input_token_source` / `output_token_source` 落库字段（usage / tokenizer / heuristic / unknown） | 合法 0（空输出）被估算覆盖会统计失真；来源字段让用户知道 50 tok/s 是真实校准还是估算 |
| Q-20 | 凭据存储 | 渠道 api_key 与网关密钥均存 macOS Keychain，AppSettings 仅存条目引用 | UserDefaults ≠ chmod 600 配置文件；API Key 是长期有效敏感凭据，Keychain 是 macOS 标准做法 |
| Q-21 | 回环安全加固 | 监听地址固定 `127.0.0.1`（无配置项、无 UI）；Host 校验；密钥恒定时间比较；无 CORS 头默认拒绝浏览器读取；凭据禁止入日志/错误/落库 | 127.0.0.1 仍可被本机其他进程访问；暴露 bind 修改入口有误配 0.0.0.0 风险 |
| Q-22 | 渠道排序 | 删除 `priority` 字段；渠道组数组顺序即尝试顺序（唯一权威）；UI 拖拽直接改数组序 | Dictionary 书写顺序不可作稳定排序依据；避免 UI 显示顺序与实际请求顺序不一致 |
| Q-23 | 大小限制 | 请求体默认上限 20 MB（超限 413）；非流式响应暂存默认上限 64 MB（超限按上游异常切换） | 防 SDK 大上下文或恶意超大 JSON 撑爆内存；数值第一版固定，后续可配置化 |
| Q-24 | 用量限制切换（用户需求 R-14） | quota 类 429 / 402 / 403 计费类：请求内切换下一渠道 + 渠道打跨请求冷却标记（默认 10 分钟，内存态，重启清空）；冷却期路由跳过；全部冷却则按原顺序尝试；瞬时限流不打标记 | quota 耗尽是持续状态，不标记则每次请求都先打已耗尽渠道、白付一次失败往返；全跳过会误杀（上游可能已重置配额），可用性优先 |
| Q-25 | 非流式统计口径 | 非流式：TTFT 仅记响应体首字节参考值、Generation 不可靠、TPS 落库 NULL；Input/Output Tokens 与 Total Time 正常 | 上游生成完成后一次性返回响应体，网关测得的是传输时间而非生成时间，不得伪装成流式指标 |
| Q-26 | Output Tokens 边界 | 定义为模型全部输出 Token（content + reasoning_content + tool_calls name/arguments + refusal），对齐上游 completion_tokens 语义 | 仅统计可见文本会与上游 usage 校准值系统性偏差；全部输出更接近上游口径 |
| Q-27 | SSE 透传语义 | Raw Byte Forwarding + Side-channel Parsing：保证事件流内容一致，不保证 HTTP Chunk 边界 / TCP 分片一致；Parser 跨读取边界解析、仅旁路识别不重组 | URLSession 接收再经自建 HTTP Server 返回，传输细节本就不可复制；强行字节级一致既不可行也无产品价值 |
| Q-28 | 上游重定向 | 3xx 一律不跟随，视为连接类故障走切换，retry_reason=redirect_rejected | 跨域重定向可能把 API Key 转发到其他主机，泄漏凭据 |
| Q-29 | 超时拆分 | 三段：Connect 10s / First Content 300s / Idle Read 120s；First Content 仅有效内容重置（心跳、注释、空事件、role-only 均不算）；Idle Read 提交后只关闭不切换 | 堵两个漏洞：上游用心跳无限拖延首内容；输出中途 stall 无限挂起 |
| Q-30 | SQLite 索引与日志模式 | 建 created_at / (model,created_at) / (channel,created_at) / (status,created_at) 四个 DESC 索引；WAL 模式 | 面板聚合与历史筛选全部命中索引；WAL 降低 UI 查询与后台写入的锁竞争 |
| Q-31 | 历史窗口分页 | 每页 50 条、created_at 游标分页；筛选由 SQLite WHERE 执行，禁止全量载入内存 | 36 万条级记录全量加载会导致首帧慢、内存涨、筛选卡顿 |
| Q-32 | 历史窗口趋势图 | 第一版不含；趋势由面板 FR-07 承载；历史趋势图增强列 P2 | 避免第一版功能蔓延，趋势已在面板抬头可见 |
| Q-33 | 加权平均 TPS | P2：历史窗口提供「简单平均 / 加权平均（SUM tokens ÷ SUM generation）」口径切换 | 两种口径含义不同（平均单次速度 vs 整体吞吐），都值得看但不阻塞第一版 |
| Q-34 | Base URL 规范化 | 合法 http/https、末尾 / 剥除、保留路径前缀、禁止重复拼 /v1、拒绝 ?/#、3xx 不跟随 | 杜绝 `//chat/completions` 类拼接事故；本地模型允许 http |
| Q-35 | 模块内部职责边界 | Proxy/SSEParser/TPSMeter（内部四子职责）/Failover/Database 按职责表组织，物理文件数可按需增加（修订 R-08 的 10 文件约束） | 职责清晰优先于文件数；统计模块混塞会导致不可测 |
| Q-36 | HTTP Server 实现 | Network.framework（NWListener/NWConnection），禁止手写 BSD socket HTTP 协议栈；协议层与业务分层 | 手写 HTTP（chunked、keep-alive、SSE、断连检测、并发管理）复杂度失控；系统框架免造轮子且不违反 APP-09 |
| Q-37 | 模块与渠道的默认启停（用户需求 R-15 / R-16） | 模块：Feature 初始 disabled，新装 / 重置不监听端口、不自动启动，手动开启后持久化并随 App 启动恢复；关闭总开关仅停服务、配置全保留。渠道：级启用开关默认开启，禁用即不参与路由与故障切换；组内全部禁用时该模型返回 `503 no_available_channel`，允许保存不阻止 | 网关属显式开发者工具，默认监听端口不符合"按需启用"预期；渠道启停让用户可临时下线单个渠道而不删配置 |
| Q-38 | 测试连接口径（用户需求 R-16） | 探测请求为 `GET <base_url>/models`（最小开销、上游标准接口）；展示成功 / 失败与接口延迟 RTT（毫秒）；错误脱敏；测试请求不计入 requests 表与速率图（避免污染 TPS 统计与折线图）；测试走该渠道完整配置（含代理与 api_key） | /models 是 OpenAI 兼容端点的最低成本必选接口；测试数据混入统计会让"测试连接"直接影响速率曲线真实性 |
| Q-39 | 渠道级代理（用户需求 R-17） | 渠道可选代理：类型 http / https / socks5、主机、端口、可选认证（凭据存 Keychain）；仅作用于该渠道上游请求（含连接测试），不影响网关对客户端的监听；代理不可达按连接类故障切换（retry_reason=`connect_failed`）；未配置渠道直连 | 用户明确要求部分渠道经代理请求（典型场景：本地模型直连、境外上游走代理）；渠道级而非全局级，避免影响本地 Ollama 等直连渠道 |
| Q-40 | Responses 协议支持方式（用户需求 R-18） | 透传不互转：新增 `POST /v1/responses` 转发至 `<base_url>/responses`；客户端发哪种协议、上游就收哪种协议；不做 Chat Completions ↔ Responses 格式互转；渠道无需声明协议——不支持该端点的渠道由上游 4xx 透传暴露，协议兼容性归入 FR-04 配置者责任 | 两套 API 的语义映射（工具调用、reasoning、多模态结构）差异巨大，互转违背透传定位且极易出错；透传零转换成本，与「客户端只改 base URL」契约一致 |
| Q-41 | Responses 统计口径 | 有效输出内容 = 增量 delta 类事件（**v2.4 细化见 §3.1.1**：`response.output_item.added` 不算有效输出，状态事件等同心跳）；usage 取 `response.completed` 事件内 `response.usage` 的 `input_tokens` / `output_tokens`，映射到统一 Input / Output Tokens 字段落库；TTFT / TPS 公式复用 §3.2 | Responses 的 SSE 事件模型与 Chat Completions chunk 不同但时间语义等价，统一映射后统计层（FR-03 / FR-06 / 速率图）无需感知协议 |
| Q-42 | Responses 端点支持范围 | 定位「创建接口透传兼容」：仅 `POST /v1/responses`；查询 / 取消 / 输入项接口列 P2；background=true 与 WebSocket 不支持不承诺；文档与 UI 不宣称完整兼容 Responses API | 查询与取消是 background 模式的前提，只做创建接口却宣称完整兼容会误导客户端开发者 |
| Q-43 | Responses 事件分级与终止语义 | `response.failed` / `incomplete` 为终止事件：立即终结请求，不等待 First Content Timeout、不切换渠道；`output_item.added` 不视为有效输出；usage 从 `response.completed` 的 `response.usage` 对象提取 | 防止已被上游明确失败的请求被延迟处理、在备用渠道重复执行、失败事件未及时透传 |
| Q-44 | previous_response_id 有状态请求 | 不跨渠道切换：命中渠道失败直接返回 `502 stateful_channel_unavailable`；**v2.5 修订（Q-62）为方案 A：第一版实现 response_id → 渠道映射表**（成功终结时记录映射，粘性优先于数组顺序；容量 1024 LRU、过期 24h、内存态；store=false 不记录）；未命中按数组顺序且不切换 | 「不切换」只解决单次请求内的问题——若上次成功渠道非数组首位，本次按顺序仍会选中不认识该 ID 的渠道；映射表让跨请求状态真正连续，诚实报错优于静默半失效 |
| Q-45 | 统一上游响应状态机 | 非 2xx 立即读错误体（上限 1 MB）按 FR-05 分类，不等待 SSE 内容；HTTP 成功 ≠ 模型执行成功，流内业务失败按终止事件处理 | 401 / 429 等 JSON 错误本无 SSE 可等；把 HTTP 错误、SSE 业务错误、网络故障混为一谈会导致错误切换 |
| Q-46 | 429 / 403 错误分类 | 按「HTTP 状态码 + 错误体结构化错误码」两级分类；403 无法识别类别时默认不切换；429 区分瞬时限流与 insufficient_quota | 403 可能是余额 / 权限 / Key 问题，仅凭状态码无法区分；把凭据错误当 quota 切换会无意义重试全部渠道 |
| Q-47 | quota 冷却作用域 | 分级：模型级额度耗尽按（渠道, 模型）冷却；账户级按渠道整体冷却；无法判断默认整渠道并记录来源 | 一个模型额度耗尽不应误伤同渠道其他模型；默认整渠道保守但保证不会反复撞已耗尽额度 |
| Q-48 | TPS 命名与口径偏差 | 指标命名固定 `output_tps` = usage 总输出 ÷ 可观察生成时间的**近似吞吐**；UI 文案「网关观察到的平均输出速率」；visible_output_tps 列 P2 | usage 总输出可能含未以 delta 暴露的 reasoning，TPS 会被高估——保留算法但诚实标注口径，不伪装成模型 Decode TPS |
| Q-49 | SSE Parser 边界 | \r\n 与 \n 换行、多行 data: 拼接、UTF-8 跨读取块、event:/id:/retry: 字段、: 注释心跳、单事件 1 MB 缓冲上限；解析失败只跳过统计、绝不影响原始转发 | SSE 可在任意字节处拆分，协议细节缺失会导致事件错切；旁路解析器任何异常都不能破坏转发主链路 |
| Q-50 | SSE 压缩处理 | 向上游统一携带 `Accept-Encoding: identity`；上游仍压缩则原样转发、解析器跳过事件识别（统计退化估算口径）；**v2.5 增补（Q-66）**：URLSession 自动解压行为与 Content-Encoding 头存留须开发前 PoC 实测确认 | 压缩流读不出明文事件；identity 请求实现最简单，符合第一版轻量定位；但 URLSession 的自动解压可能导致「转发头声明压缩、转发体已被解压」或「旁路数据与转发数据不同源」，必须实测而非假设 |
| Q-51 | 连接测试的结果定位 | 只命名为「连接测试」，证明 /models 可达与延迟，不代表端点可用或模型兼容；真实模型探测列 P2 可选项 | GET /models 证明不了 Chat Completions / Responses 可用，夸大测试含义会误导配置决策 |
| Q-52 | SOCKS5 代理 PoC 前置 | 动工前对 HTTP / HTTPS / SOCKS5 连接、SOCKS5 SSE 长连接、代理认证、**URLSession 压缩行为（v2.5 增补，Q-66）**六个场景各做 PoC（UI/Spike，验收后删除）；不过则收窄为 HTTP/HTTPS 或调整压缩策略 | URLSession 对 SOCKS5 的支持方式与 HTTP/HTTPS 代理不同，不能默认同样简单；压缩行为属于同类「URLSession 隐性行为」风险，技术风险应在开发前暴露 |
| Q-53 | HTTP 协议层内部职责 | Network.framework 只提供连接能力；HTTP1Parser（请求行/Header/Chunked 解析）、HTTPResponseWriter（SSE 写入）、HTTPConnection（Keep-Alive/断连/并发）三个子职责独立组织，不混业务逻辑 | 避免 HTTP 协议实现全部堆进 GatewayServer.swift 导致不可测、不可维护 |
| Q-54 | 上游认证 Header 类型 | 渠道可选 auth_header_type：bearer（默认）/ api-key / x-api-key；自定义 Header 与 Query 认证列 P2；上游转发请求头按白名单控制 | 不是所有 OpenAI 兼容服务都用 Bearer；白名单防止客户端认证头 / 代理头 / 内部头意外透传到上游 |
| Q-55 | 请求体透传语义 | 除 model 改写外其余 JSON 字段**语义不变**，不承诺字节级一致（model 改写需重新序列化） | 「原样透传」与「改写 model」在字节层面自相矛盾，按语义一致性定义更准确诚实 |
| Q-56 | 非流式响应超限的故障分级 | 超限记录 `response_too_large`，归**执行状态未知类**（上游可能已生成并计费），可切换但记录重复执行风险，客户端收统一 502；流式单事件 1 MB 缓冲上限 | 超限时上游大概率已执行，按普通连接失败处理会掩盖重复计费风险 |
| Q-57 | /v1/models 列表口径 | 展示配置中的模型别名；quota 冷却等瞬时状态不影响列表；组内渠道全部手动禁用的别名不返回 | 列表随冷却抖动会让客户端误以为模型被删除；手动禁用是持久意图，应当反映 |
| Q-58 | 连接测试独立超时 | 连接 10s / 响应 15s / 响应体 1 MB / 取消立即，与正常请求三段超时分离 | 测试被异常上游挂起会长时间占用资源并阻塞 UI 加载态 |
| Q-59 | Responses 多模态事件边界 | 方案 A：第一版只承诺文本与函数调用类事件的 TTFT/TPS 统计；音频 / 图像等事件不触发统计打点；**v2.5 修订（Q-61）：多模态事件触发传输提交**，保证纯多模态请求客户端正常收到响应 | 多模态事件族庞大且 Token 无法估算，轻量网关不做全量承诺；但「不计入统计」不能推出「不触发提交」——后者直接决定纯音频请求能否正常工作 |
| Q-60 | 提交前暂存总量上限 | `precommit_buffer_limit` 默认 8 MB：所有已暂存未提交的原始数据（响应头 + 累积 SSE 字节）合计超限即按执行状态未知类处理（retry_reason=`precommit_buffer_exceeded`），全部耗尽客户端收统一 502；与 First Content Timeout 双兜底，先到者触发 | 单事件 1 MB 上限约束不了整个提交前缓冲区——上游持续发送不触发传输提交的事件（音频前置状态、未知事件族）会造成内存占用失控 |
| Q-61 | 统计有效输出 vs 传输提交事件 | 两概念分离：统计有效输出仅用于 TTFT / TPS 打点（Q-59 边界不变）；传输提交事件决定何时向客户端发送响应——文本 / 推理 / 函数调用 delta、多模态增量事件均触发提交，终止事件（completed / failed / incomplete）从未提交过时兜底一次性提交全部暂存再结束 | 纯多模态请求全程无文本 delta，若提交与统计绑定则网关永不提交、客户端收不到响应——这不只是统计口径问题，而是纯音频请求能否工作的正确性问题 |
| Q-62 | response_id → 渠道映射表 | 方案 A（评审推荐）：第一版实现——Responses 请求 success 终结时记录 response_id → channel_id 映射（store=false 不记录）；携带 previous_response_id 的请求命中映射则粘性优先于数组顺序，映射渠道不可用 / 失败返回 `502 stateful_channel_unavailable` 不切换；未命中按数组顺序且不切换；容量 1024 条 LRU、过期 24 小时、仅内存态（重启清空） | 评审举例：渠道 A 失败切到 B 成功生成 resp_xxx，下次按数组顺序仍选 A，A 不认识该 ID 必失败——仅禁止本次切换解决不了跨请求状态连续性；映射表内存开销极小（一条记录几十字节），彻底闭合该边界 |
| Q-63 | 浏览器跨源请求防护 | 四层防护补充 Host 校验：Sec-Fetch-Site=cross-site → 403；Origin 存在且不匹配回环源（含 null）→ 403；OPTIONS → 405 不提供预检；POST 要求 Content-Type 含 application/json 否则 415；未设置网关密钥（默认态）时防护仍然生效 | 无 CORS 头只阻止浏览器读取响应，不阻止简单跨源请求发出——恶意网页仍可借本机网关消耗上游配额（DNS rebinding 与跨源 POST 均可绕过纯 Host 校验） |
| Q-64 | HTTP 协议层资源与解析安全限制 | Header 总大小 32 KB / 100 字段（超限 431）；Header 15s、Body 60s 接收超时（慢速攻击）；CL+TE 并存 400（防走私）；Chunked 非法 400；Keep-Alive 空闲 60s、单连接 1000 请求；并发客户端连接 64、并发代理请求 16（超出 503 overloaded）；全局暂存内存预算 256 MB | 单请求限制（20 MB / 64 MB / 8 MB）防不了并发内存压力（16 × 64 MB ≈ 1 GB）；自建 HTTP 层无框架兜底，解析边界与资源上限必须逐项显式定义，防慢速攻击与请求走私 |
| Q-65 | response.incomplete 落库口径 | `status=success`（非故障、不切换），`error` 字段记录不完整原因摘要（如 `incomplete: max_output_tokens`，含 incomplete_details 原文），历史窗口详情页可见 | 四态枚举不新增状态；不记录原因会让用户把「模型主动截断」与「正常结束」混为一谈，违背统计可信目标 |
| Q-66 | URLSession 压缩行为验证 | 并入 Q-52 开发前 PoC：实测 URLSession 自动解压、Content-Encoding 头存留、转发头与转发体编码声明一致性、旁路解析数据与转发数据同源性；实测结果不符则调整转发策略并回改 PRD | URLSession 默认自动解压 gzip / deflate 且可能剥除编码头——「原样转发压缩流」的实现前提是否成立不能靠假设，头体不一致会直接破坏客户端解码 |
