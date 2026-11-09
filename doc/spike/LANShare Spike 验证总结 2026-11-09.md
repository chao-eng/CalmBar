# CalmBar 局域网互传 Spike 验证总结（2026-11-09）

> 目的：在正式实施前验证 PRD 中三个技术不确定项，并补充跨机、连接复用与预连接噪音三个遗留项。
> 基线提交：`184c003` · 运行环境：macOS 15.7.9（arm64）
> 实现：`NWListener + NWConnection` + 统一事件契约，A = 自研增量状态机，D = vendored llhttp 9.4.3
> 状态：验证完成。Spike 代码仅用于取证，**不进入主线**，验收后整目录删除。

## 一、结论速览

| 验证项 | 结论 | 关键证据 |
| --- | --- | --- |
| A 自研 Parser 处理真实浏览器/手机请求 | **PASS** | 52 条语料、7 种分片差分、10 万次模糊均 0 分歧；Chrome 与手机实测通过 |
| 20GB multipart 流式落盘、内存可控 | **PASS** | 20GB 上传约 45s，footprint 增量 1.69MB；20GB 下载增量 16KB |
| llhttp 是否明显降低维护成本 | **不成立** | 仍需 311 行 Swift 适配 + 11,890 行 vendored C，且行为 Black-box 不可控 |
| 真实局域网跨机传输 | **PASS** | 手机 `192.168.10.194` 上传 166,495 字节 JPEG，落盘完整 |
| HTTP keep-alive 复用 | **按设计不支持** | 二次请求 `ConnectionReset`；流水线两请求仅 1 个响应；响应头 `Connection: close` |
| Chrome 预连接导致的 400 噪音 | **已修复** | 修复后 `rejected=0`、`INCOMPLETE=0` |

结论：采用 **A 自研 Parser + PRD 的 `Connection: close` 设计**，不引入 llhttp。

## 二、S-03：Parser 正确性与稳定性

自检命令（10 万次模糊）：

```bash
./.build/arm64-apple-macosx/debug/CalmBar --spike lanshare --selftest --fuzz 100000
```

结果：

```json
{"passed":true,"cases":52,
 "fragmentationMismatches":0,
 "fuzzIterations":100000,"fuzzMismatches":0,
 "multipartPassed":true,
 "baselineFootprint":11175680,"afterFootprint":14010368,"elapsedSeconds":17.77}
```

- 语料覆盖正常请求、Host/CL 冲突、chunked、Expect、路径穿越、超限、畸形请求行等 52 例，A/D 状态与期望值全部一致。
- 关键状态码均命中：`400 / 403 / 405 / 411 / 413 / 415 / 417 / 431 / 501`。
- multipart 单元测试：1 字节分片、9 个 Part、9KB Part Header 均按预期处理。
- 差分与模糊过程中 A/D 未出现语义分歧。

实测过程中修复的两个真实缺陷：

1. **llhttp 9.x 头字段边界**：`on_header_field` / `on_header_value` 是 span 回调，必须依赖 `on_header_field_complete` / `on_header_value_complete` 才能正确 `pushHeader`，否则所有请求都会误报「Host 缺失」。
2. **空连接与半截请求**：Parser 在请求行/头未完成时收到关闭，必须显式返回 400；随后按「对端关闭语义」在连接层区分静默关闭与 INCOMPLETE（见第六节）。

## 三、S-04：20GB 流式落盘与内存

内存口径：`phys_footprint` 峰值 − 空闲基线；目标为下载增量 ≤40MB、上传增量 ≤64MB。

| 场景 | 耗时 | 基线 → 峰值 | 增量 | 结论 |
| --- | --- | --- | --- | --- |
| 20GB 上传（A） | 约 45.1s | 19.34MB → 21.02MB | **1.69MB** | PASS |
| 2GB 上传（A） | — | 11.95MB → 19.27MB | **7.32MB** | PASS |
| 2GB 上传（D） | — | 11.82MB → 19.01MB | **7.19MB** | PASS |
| 20GB 下载 | 约 13.5s | 20.97MB → 20.99MB | **16KB** | PASS |
| 2 路并发 2GB 上传 | — | 19.04MB → 20.17MB | **1.13MB** | PASS |
| 中断上传清理 | — | — | 临时目录 0 残留 | PASS |

上传期间的滑动缓冲始终维持在 64KB 量级：

```text
[17:33:24.802] UPLOAD progress bytes=268500575 bufferCount=65585 bufferStart=0 pending=0 footprint=18959040
[17:33:26.235] UPLOAD progress bytes=536936031 bufferCount=65585 bufferStart=0 pending=0 footprint=19155648
[17:33:27.948] UPLOAD progress bytes=805371487 bufferCount=65585 bufferStart=0 pending=0 footprint=19434176
[17:33:28.296] UPLOAD done conn=B5BBAF7B-... file=big-1g.bin bytes=1073741824 peakPending=1048576
```

**关键根因（必须回写实现约束）**：早期版本使用 `Data.removeFirst` 裁剪已消费字节，底层容量随上传线性增长。2GB 上传时出现 `EXC_BREAKPOINT`（`Data._Representation.replaceSubrange`，`mach_vm_allocate_kernel failed`），footprint 涨到 1.94GB。改为 **`bufferStart` 游标 + 已消费 ≥64KB 时压缩 + 缓冲清空时彻底释放** 后，20GB 上传稳定在 1.7MB 增量。

## 四、真实浏览器与跨机

- Chrome 连续 3 次刷新：16 个请求 / 19 条连接，其中 3 条为预连接（preconnect），说明浏览器会主动建立空连接。
- 本机 LAN IP `192.168.10.10:47821`：页面加载与上传均正常。
- 手机（同 Wi-Fi，`192.168.10.194`）实测：
  - 页面加载建立 3 条连接，上传另建 1 条连接；
  - 上传文件名 `Screenshot_2026-11-09-17-01-54-40_...jpg`，`bytes=166495`，`peakPending=56472`；
  - 落盘文件 166,495 字节，1080×2354 JPEG，尾部 `FFD9`，`sips` 解码通过；
  - 手机侧无 REJECT / INCOMPLETE，`.calmbar-tmp` 为空。

```text
[17:35:49.217] CONN 901A6869-... ready peer=192.168.10.194:38842
[17:36:00.196] CONN 637F4600-... ready peer=192.168.10.194:54464
[17:36:00.249] UPLOAD done conn=637F4600-... file=Screenshot_...jpg bytes=166495 peakPending=56472
```

跨机结论：双栈监听 `*:47821`、防火墙关闭时，同网段手机可直接访问并完成上传，无需额外配置。

## 五、keep-alive 与预连接噪音

`proto_test.py` 实测输出：

```text
preconnect: closed=3 rejected=0 connections=6
keepalive#1: bytes=206 status='HTTP/1.1 200 OK' ['Connection: close']
keepalive#2: send-failed ConnectionResetError
pipeline: bytes=818 responses=1
delta: connections=+7 requests=+4 rejected=+0
```

- 服务端明确返回 `Connection: close`，同连接第二次请求被重置；流水线两请求只返回 1 个响应。这与 PRD 第 9 章「不支持连接复用」一致，**不需要为 keep-alive 增加实现**。
- 预连接与半截请求处理策略（已落地）：
  1. 0 字节连接：直接静默关闭，不回 400、不计 rejected；
  2. 已响应或消息已完整接收：交给异步收尾，避免误删已上传文件；
  3. 真正半截的请求：仅记 `INCOMPLETE conn=... bytes=...`，不回写无意义的 400。

```text
[17:33:22.256] INCOMPLETE conn=F8351A9D-... bytes=564620407
```

修复后 Chrome 3 次刷新与手机访问均为 `rejected=0`、`INCOMPLETE=0`，日志噪音消除。

## 六、对主线实现的影响

1. **Parser 选型**：采用 Parser A；不引入 llhttp（vendored 体积与适配成本未换来可维护性）。
2. **连接语义**：保持 `Connection: close`，不实现 keep-alive / pipelining 响应排队。
3. **上传缓冲**：必须使用游标式滑动窗口，禁止循环 `removeFirst`；缓冲清空时释放底层存储。
4. **关闭语义**：按第五节三条规则区分「静默关闭 / 正常收尾 / INCOMPLETE」，不把对端取消误判为 400。
5. **背压参数**（已验证可用）：`receiveChunk 64KB`、单连接高水位 1MB / 低水位 256KB、全局 Body 缓冲 32MB。
6. **验收口径**：20GB 上传 / 下载内存增量、断线清理 0 残留、跨机上传落盘完整性可直接沿用本报告数据。

## 七、复现方式

```bash
# 语料 + 10 万次差分/模糊
./.build/arm64-apple-macosx/debug/CalmBar --spike lanshare --selftest --fuzz 100000

# 启动服务（A）
./.build/arm64-apple-macosx/debug/CalmBar --spike lanshare --port 47821 --root /tmp/calmbar_lanshare/server_root

# keep-alive / 预连接探测
python3 /tmp/calmbar_lanshare/proto_test.py
```

## 八、证据清单

| 文件 | 内容 |
| --- | --- |
| `doc/spike/evidence/corpus_report_100k.md` | 52 条语料明细、A/D 差分、10 万次模糊结果 |
| `doc/spike/evidence/selftest_summary.json` | 自检汇总（通过、耗时、内存） |
| `doc/spike/evidence/mem_20g.log` | 20GB 上传 footprint 采样，增量 1.69MB |
| `doc/spike/evidence/mem_2g.log` / `mem_2g_d.log` | 2GB 上传 A / D 内存采样 |
| `doc/spike/evidence/mem_conc.log` | 2 路并发 2GB 上传内存采样 |
| `doc/spike/evidence/mem_down.log` | 20GB 下载内存采样，增量 16KB |
| `doc/spike/evidence/status_after.json` | keep-alive / 预连接探测后的服务指标（rejected=0） |
| `doc/spike/evidence/spike_samples.log` | 关键日志摘录（启动、跨机、上传进度、INCOMPLETE） |
