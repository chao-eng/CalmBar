# CalmBar 局域网互传 PRD

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v1.7 |
| 编写日期 | 2026-11-09 |
| 文档状态 | 待复审（v1.6 复审问题已修订） |
| 目标版本 | CalmBar 2.7.0（仅 P1 MVP） |
| 修订说明 | v1.1：修复无口令认证、令牌传递与边界；限定 HTTP 最小子集。v1.2：Content-Length 按方法区分；`/api/bootstrap`；网段前缀边界；Cookie 滑动同步。v1.3：Content-Type 按路由；P1/P2 网络与休眠范围；URL 解码；Range 三形式；占位生命周期；100-continue 前置校验；ZIP waiter；SSE 配额；文案统一。v1.4：占位改用 inode + `RENAME_EXCL` 防外部覆盖；100-continue 改为两阶段大小校验；JSON `charset` 容错统一；端口回退表述拆分；`/api/session` 与 DELETE 明确 CSRF；区分「刷新地址」与「自动选网卡」；补 IPv6/Expect/DELETE 验收。v1.5：新增 Parser 统一事件契约；新增 S-14（自研 Parser vs vendored llhttp）同语料对比 Spike；主架构仍默认方案 A，S-14 结论前不引入第三方代码。v1.6：明确 `onBody` 为原始 HTTP Body，新增 multipart/JSON Body Consumer 分层；Header 改为保序多值结构；`HTTPRequestLine` 保留 rawTarget/rawQuery；补回调所有权与高低水位背压；S-14 逐项断言 Chunked=501 等协议预期、加 ASan 与差分测试；内存口径按下载/上传拆分并统一 A/D。v1.7：上传路由上限区分「文件 Part 20GB」与「请求体 20GB+8MB」；补 `receive`/Parser/onBody 统一 64KB 粒度与水位判断口径；S-07 拆为 S-07a（P1 必过）与 S-07b（P2 仅验证可行性） |
| 关联文档 | `doc/design/CalmBar 新功能接入模板.md`、`app/AGENTS.md` |
| 参考实现 | `reference/file-share-master`（MIT） |

> 本文档分为两大部分：第 1 章是对参考项目 `file-share-master` 的逆向分析与证据链；第 2 章起是 CalmBar 自身的产品需求。所有 CalmBar 设计决策均可在第 1 章找到来源或反例。

---

## 0. 原始需求基线（追溯表）

| 原始诉求 | 拆解后的产品含义 | 落地章节 |
| --- | --- | --- |
| 弄清参考项目的局域网互传如何实现 | 用可核验的代码位置说明其服务端、协议、数据流、UI 与平台适配 | 第 1 章、附录 E |
| 展示证据 | 每条结论绑定 `文件:行号`，并附关键代码摘录与协议表 | 1.2、1.3、1.4、附录 E |
| 为 CalmBar 实现类似功能 | 在菜单栏 App 内提供「开始分享 → 对方浏览器打开 → 双向传文件/文字」的完整能力 | 第 2~9 章 |
| 符合 CalmBar 工程约束 | 不引入第三方依赖、走 Feature/Settings/Recovery/Command 体系、不破坏 320×520 面板 | 2.6、5.4、6、9.2 |
| 借鉴而非照搬 | 保留参考实现的优点，修复其安全与稳定性缺陷 | 1.6、7.3、7.4 |

---

## 1. 参考实现逆向分析（`file-share-master`）

### 1.1 架构总览

参考项目是一个「桌面端起 HTTP 服务 + 浏览器当接收端」的局域网文件中转工具，核心特点是**接收端零安装**。

```text
┌────────────────────────────── 分享者电脑（Electron / uTools） ──────────────────────────────┐
│  page_app (Vue3/Element Plus)                                                              │
│    ├─ StartPage   点击开启服务                                                             │
│    ├─ DetailPage  显示链接/二维码、分享列表、拖拽添加、停止分享                              │
│    └─ Setting     端口、上传目录、鉴权、账号、网络接口                                       │
│                                    │ window.api（preload 注入）                            │
│  render 进程 ──────────────────────┴───────────────────────────────────────────────────    │
│    render.js 把 shared 工具函数挂到 window.api                                               │
│                                    │                                                        │
│  shared/utils（Node.js，与 UI 同进程）                                                       │
│    Server.js     Express + 路由 + JWT + 静态页                                              │
│    FileDb.js     分享列表（KV 存储，JSON 字符串）                                            │
│    Setting.js    端口/IP/上传目录/鉴权开关                                                   │
│    Account.js    账号与路径访问规则                                                          │
│    SseUtil.js    SSE 订阅与广播                                                             │
│    IpUtil.js     枚举网卡选局域网 IP                                                         │
│    ZipUtil.js    文件夹打包 ZIP                                                             │
└────────────────────────────────────────────────────────────────────────────────────────────┘
                                    │ HTTP（默认 5421）
┌────────────────────────────── 接收者设备（任意浏览器） ─────────────────────────────────────┐
│  page_web (Vue3 + Element Plus + Tailwind)                                                  │
│    FilePage.vue  列表 / 面包屑 / 下载 / 上传 / 发文字 / SSE 刷新 / 批量下载                   │
│    Login.vue     可选账号登录                                                               │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

关键结论：

1. **没有原生客户端互传协议**，全部走 HTTP/1.1；接收端是浏览器。
2. **服务与 UI 同进程**，Express 直接跑在 Electron renderer / uTools preload 中，因此能直接调用 Node 的 `fs`、`os`。
3. **分享列表不是目录同步**，而是一份「用户显式添加的条目清单」，根列表只展示这些条目；进入文件夹后才实时读取真实文件系统。
4. **实时性靠 SSE**，不是 WebSocket；SSE 只发「列表变了」的信号，客户端收到后重新拉全量列表。
5. **鉴权是可选的**，默认关闭；关闭时所有请求视为管理员，开启后使用自签 JWT。

### 1.2 能力-证据对照表

| # | 能力 | 实现方式 | 代码证据 |
| --- | --- | --- | --- |
| E-01 | 启动/停止 HTTP 服务 | Express `app.listen(port)`；停止用 `server.close()`；状态机只有 `start`/`stop` | `reference/file-share-master/shared/utils/Server.js:414-441` |
| E-02 | 服务路由与静态页 | `connect-history-api-fallback` + `express.static(page_web)`；`/api/*` 先过鉴权 | `Server.js:195-213` |
| E-03 | 局域网地址选择 | `os.networkInterfaces()` 过滤 loopback/vmware/lo/vEthernet，取首个非回环 IPv4；支持 IPv6 与指定网卡 | `shared/utils/IpUtil.js:26-105` |
| E-04 | 分享链接生成 | `http://<ip>:<port>`，端口默认 5421，IP 可在设置中覆盖 | `shared/utils/Setting.js:56-58, 80-88` |
| E-05 | 分享列表存储 | KV 存储中的 JSON 字符串，key 为文件名；条目类型 `file`/`directory`/`text` | `shared/utils/FileDb.js:12-74` |
| E-06 | 根列表与子目录浏览 | `GET /api/files?path=`；根列表读 FileDb，子目录用 `fs.readdirSync` 实时读 | `Server.js:214-245`；`shared/utils/FileUtil.js:22-43` |
| E-07 | 相对路径解析 | 首段必须是分享条目名，映射到其真实父目录，再拼接剩余段 | `Server.js:158-181` |
| E-08 | 文件下载 | `res.download`，Express 自带 Range/断点续传 | `Server.js:291-320` |
| E-09 | 文件夹下载 | 先 `archiver` 打 ZIP 到临时目录，再下载；30 分钟后删 ZIP | `Server.js:303-315`；`ZipUtil.js:10-23`；`FileUtil.js:89-122` |
| E-10 | 接收端上传文件 | `multer.diskStorage` 直接落到上传目录，保留原始文件名 | `Server.js:360-380` |
| E-11 | 接收端发文字 | `POST /api/addText`，截前 20 字做标题、前 100 字做摘要 | `Server.js:382-397`；`FileDb.js:48-60` |
| E-12 | 列表实时刷新 | `EventDispatcher` 触发 `fileDb.listChange` → SSE 广播 → 前端重拉列表 | `Server.js:399-405`；`SseUtil.js:5-30` |
| E-13 | SSE 注册 | `text/event-stream`，每个客户端分配 UUID，`close` 时移除订阅 | `SseUtil.js:5-23` |
| E-14 | 可选鉴权 | 自签 HS256 JWT，密钥进程内随机生成；白名单放行首页/登录/SSE/下载/静态资源 | `Server.js:20-153` |
| E-15 | 账号权限 | `download`/`uploadFile`/`uploadText` 三个开关 + `allowAccess`/`denyAccess` 通配路径规则 | `shared/utils/Account.js:7-30, 166-220` |
| E-16 | 分享端 UI | 链接、二维码、双协议切换、网卡切换、分享列表、拖拽添加、停止分享 | `page_app/src/views/DetailPage.vue:16-79, 153-226, 320-322` |
| E-17 | 接收端 UI | 列表、面包屑、下载/批量下载、上传、发文字、SSE 刷新 | `page_web/src/views/FilePage.vue:144-165, 268-280, 313-362, 392-396` |
| E-18 | 跨平台存储适配 | Electron 用 `localStorage`；uTools 用内置 db；通过 `Database.setAdapter` 注入 | `electron/src/render/utils/PlatformAdapterInstance.js:6-79`；`utools/preload/index.js:5-6` |
| E-19 | 端口变更后重启 | 比较新旧端口，不同则 `stopServer()` → `startServer()` | `electron/src/render/render.js:27-42`；`utools/preload/index.js:53-69` |
| E-20 | 服务自启 | 读取 `autoStart`，App 就绪时自动启动 | `electron/src/render/render.js:20-24`；`utools/preload/index.js:18-40` |

### 1.3 关键代码摘录

**（1）服务启动：只监听端口，不指定网卡**

```javascript
// reference/file-share-master/shared/utils/Server.js:414-425
const startServer = () => {
    let port = Setting.getPort();
    const app = initApp()
    server = app.listen(port, () => {
        status = StatusStart;
        EventDispatcher.triggerEvent({ type: 'server.statusChange', data: { status: StatusStart } })
    });
    FileUtil.clearTempDir()
    return { success: true, message: "服务启动成功", url: Setting.getUrl() };
}
```

证据含义：`app.listen(port)` 未传 host，Node 默认绑定 `::`/`0.0.0.0`，即**所有网卡**。这解释了为什么它能在局域网被访问，也意味着在公共 Wi-Fi 下同样暴露。

**（2）相对路径到真实路径的映射**

```javascript
// Server.js:158-181
function parsePath(filename) {
    if (!filename) return { finalPath: '', filePaths: [], startPath: '' }
    let filePaths = filename.split('/').filter(p => !!p && p !== '')
    let startPath = filePaths[0]
    let startFile = FileDb.getFile(startPath);
    if (!startFile) throw new Error("分享列表未找到该文件")
    let filePath = startFile.path;
    let dirname = path.dirname(filePath)
    let fullPath = [...filePaths]
    fullPath.unshift(dirname)
    let finalPath = fullPath.join(path.sep)
    return { finalPath, filePaths, startPath };
}
```

证据含义：分享条目名是第一段，真实路径 = 条目父目录 + 全部请求段。注意它**没有过滤 `..`**，也没有校验最终路径仍位于分享根内，这是后文审计中的高危项。

**（3）下载：文件直传、文件夹先打包**

```javascript
// Server.js:303-319
if (fs.lstatSync(sourceFilePath).isDirectory()) {
    let fileName = FileUtil.parseFileName(sourceFilePath);
    let destZipFile = path.join(FileUtil.getTempFilePath(), fileName + "_" + timestamp) + ".zip"
    if (fs.existsSync(destZipFile)) {
        doDownload(destZipFile, () => FileUtil.clearTempFileDelay(destZipFile))
    } else {
        ZipUtil.zipDirectory(sourceFilePath, destZipFile).then(() => {
            doDownload(destZipFile, () => FileUtil.clearTempFileDelay(destZipFile))
        }).catch(error => console.log(error))
    }
} else {
    doDownload(sourceFilePath)
}
```

证据含义：文件下载由 Express `res.download` 负责，自带 Range；文件夹必须先落盘 ZIP，因此有「打包等待」和临时文件清理问题。

**（4）SSE：只广播事件，不携带业务数据**

```javascript
// shared/utils/SseUtil.js:5-30
function registry(req, res) {
    const subscriberId = uuid.v4();
    const headers = {
        'Content-Type': 'text/event-stream',
        'Connection': 'keep-alive',
        'Cache-Control': 'no-cache'
    };
    res.writeHead(200, headers);
    const value = JSON.stringify({type: 'registry', data: {id: subscriberId}});
    res.write(`data: ${value}\n\n`);
    subscribers.push({id: subscriberId, res: res});
    req.on('close', () => {
        subscribers = subscribers.filter(sub => sub.id !== subscriberId);
    });
}
async function sendEvent(data) {
    subscribers.forEach(subscriber => {
        const value = JSON.stringify(data);
        subscriber.res.write(`data: ${value}\n\n`);
    });
}
```

证据含义：SSE 是「失效通知」而非数据通道；没有心跳、没有写失败处理、没有订阅上限。

**（5）上传：multer 直接写目标目录，保留原始文件名**

```javascript
// Server.js:360-369
let storage = multer.diskStorage({
    destination: function (req, file, cb) { cb(null, Setting.getUploadPath()); },
    filename: function (req, file, cb) { cb(null, file.originalname); }
});
let upload = multer({ storage: storage });
```

证据含义：上传是流式落盘的，不需要把整个文件读进内存；但同名文件会静默覆盖，且没有大小/空间限制。

**（6）IP 枚举**

```javascript
// shared/utils/IpUtil.js:38-58
let getNetInterfaceNames = function (ipFamily = "ipv4") {
    let interfaces = networkInterfaces();
    let ipNames = Object.keys(interfaces).filter((name) => getIpAddresses(name, ipFamily).length > 0)
    let finalNames = ipNames.filter((name) => !/(loopback|vmware|internal|lo|vEthernet)/gi.test(name));
    return finalNames.length === 0 ? (ipNames.length === 0 ? [] : ipNames) : finalNames;
}
let getIpAddress = function (idx = 0, ipFamily = 'ipv4') {
    let names = getNetInterfaceNames(ipFamily);
    if (!names.length) return loopback(ipFamily);
    let ipAddresses = getIpAddresses(names[idx], ipFamily);
    return ipAddresses.length > 0 ? ipAddresses[0].address : loopback(ipFamily);
};
```

证据含义：默认取「第一个看起来像物理网卡」的 IPv4；Wi-Fi 切换、VPN、多网卡时不一定正确，所以它把「切换网卡 / 切 IPv4/IPv6」做成了手动按钮。

### 1.4 参考实现的协议与数据模型

**HTTP 接口（参考实现）**

| 方法 | 路径 | 鉴权 | 作用 | 证据 |
| --- | --- | --- | --- | --- |
| GET | `/`、`/index.html`、`/static/*` | 白名单 | 接收端页面 | `Server.js:133-141, 212` |
| GET | `/api/files?path=` | 可选 | 根列表或子目录列表 | `Server.js:214-245` |
| GET | `/api/download?filename=&token=&timestamp=` | 可选 | 下载文件；文件夹打 ZIP | `Server.js:247-320` |
| GET | `/api/registrySSE` | 白名单 | 注册 SSE | `Server.js:400` |
| POST | `/api/addFile`（multipart，字段 `file`） | 可选 | 接收端上传 | `Server.js:360-380` |
| POST | `/api/addText`（JSON `{message}`） | 可选 | 接收端发文字 | `Server.js:382-397` |
| POST | `/api/login` | 白名单 | 账号换取 JWT | `Server.js:332-357` |
| GET | `/api/getSetting` | 可选 | 返回 `authEnable` 与当前权限 | `Server.js:322-325` |
| GET | `/api/logout` | 可选 | 无状态登出，仅返回成功 | `Server.js:327-330` |

**分享条目数据（FileDb）**

| 字段 | 类型 | 说明 | 证据 |
| --- | --- | --- | --- |
| `type` | `file` / `directory` / `text` | 条目类型 | `FileDb.js:40-42, 56` |
| `name` | string | 显示名，同时是 FileDb 的主键 | `FileDb.js:12-22` |
| `path` | string | 真实绝对路径（file/directory） | `FileDb.js:40-42` |
| `content` | string | 文字全文（text） | `FileDb.js:56` |
| `intro` | string | 文字前 100 字摘要 | `FileDb.js:52-56` |
| `username` | string | 来源 IP（上传者）或本机 IP | `Server.js:377-378, 389-395` |

**设置项（Setting）**

| Key | 默认值 | 说明 | 证据 |
| --- | --- | --- | --- |
| `uploadPath` | 系统下载目录 | 接收端上传落盘位置 | `Setting.js:8, 22-28` |
| `port` | `5421` | HTTP 端口 | `Setting.js:56-58` |
| `authEnable` | `false` | 是否开启账号鉴权 | `Setting.js:116-118` |
| `tusEnable` | `false` | 预留的续传开关（服务端未实现对应路由） | `Setting.js:120-122`；`Server.js` 无 `tusConfig` |
| `chunkSize` | `20`（MB） | 预留的分片大小 | `Setting.js:135-137` |
| `autoStart` | `false` | 启动时自动开服务 | `Setting.js:190-192` |
| `ipFamily` | `ipv4` | 使用 IPv4 还是 IPv6 | `Setting.js:194-206` |
| `netInterfaceName` | 空 | 指定网卡 | `Setting.js:208-217` |

**安全模型（开启鉴权时）**

- JWT 为 HS256，密钥在服务进程内随机生成，**服务重启后所有旧 token 立即失效**（`Server.js:21-22`）。
- 本机 App 调 `getToken()` 生成管理员 token，用于拼分享链接和单文件链接（`Server.js:89-96`；`DetailPage.vue:362-369`）。
- 账号 token 只带 `username`，每次请求按账号当前权限实时解析，改权限立即生效（`Server.js:98-114`）。
- 下载接口单独从 query 取 token，因为浏览器地址栏下载无法带自定义 Header（`Server.js:247-263`；`FilePage.vue:392-396`）。

### 1.5 端到端时序（参考实现）

**（1）开启分享**

```text
用户            StartPage.vue          render.js / preload          Server.js              IpUtil/Setting
 │ 点击开启服务      │                         │                         │                        │
 │────────────────►│                         │                         │                        │
 │                 │ api.startServer()       │                         │                        │
 │                 │────────────────────────►│ startServer()           │                        │
 │                 │                         │────────────────────────►│                        │
 │                 │                         │                         │ getPort()/getUrl()     │
 │                 │                         │                         │───────────────────────►│
 │                 │                         │                         │◄───────────────────────│
 │                 │                         │                         │ app.listen(5421)       │
 │                 │                         │                         │ 状态 start → 事件       │
 │                 │                         │◄────────────────────────│                        │
 │                 │                         │ 更新 store.settingForm  │                        │
 │                 │◄────────────────────────│                         │                        │
 │ 看到链接/二维码   │                         │                         │                        │
```

**（2）接收端浏览与下载**

```text
浏览器                      Server.js                    FileDb / FileUtil / ZipUtil
 │ GET /                        │                                  │
 │─────────────────────────────►│ 返回 page_web 静态页              │
 │ GET /api/files?path=         │                                  │
 │─────────────────────────────►│ parsePath → FileDb.listFiles     │
 │                              │─────────────────────────────────►│
 │◄─────────────────────────────│ {path, files}                    │
 │ 点击文件夹                    │                                  │
 │ GET /api/files?path=dir/child│ fs.readdirSync(真实目录)          │
 │─────────────────────────────►│─────────────────────────────────►│
 │ GET /api/download?filename=… │                                  │
 │─────────────────────────────►│ 文件：res.download               │
 │                              │ 文件夹：archiver → 临时 ZIP       │
 │◄─────────────────────────────│ 200/206 + 文件流                 │
```

**（3）上传与实时刷新**

```text
浏览器 A                  Server.js                 FileDb            SSE 订阅者（浏览器 B）
 │ POST /api/addFile          │                        │                      │
 │───────────────────────────►│ multer 落盘 uploadPath │                      │
 │                            │───────────────────────►│ addFile             │
 │                            │                        │ listChange 事件      │
 │                            │◄───────────────────────│                      │
 │                            │ sendEvent('fileDb.listChange')               │
 │                            │──────────────────────────────────────────────►│
 │                            │                        │                      │ 收到事件
 │                            │                        │                      │ GET /api/files 重拉
 │◄───────────────────────────│ {code:200}             │                      │
```

### 1.6 缺陷审计与对 CalmBar 的约束

| # | 问题 | 证据 | 严重度 | CalmBar 对策 |
| --- | --- | --- | --- | --- |
| D-01 | 路径可穿越：`parsePath` 未过滤 `..`，也未校验最终路径在分享根内 | `Server.js:158-181, 214-245, 247-320` | 高危 | BR-09/BR-44：解码 → 标准化 → 符号链接策略 → fd 级 dev/ino 复核（防 TOCTOU） |
| D-02 | 默认监听所有网卡，且无来源网段限制，公共网络下暴露 | `Server.js:418` | 高危 | BR-03/BR-38：仅接受选定网卡同前缀来源，并校验 Host/Origin |
| D-03 | 上传保留原始文件名，同名静默覆盖 | `Server.js:364-366` | 高危 | BR-19：清洗 + ` (n)` 去重 + 原子写入 |
| D-04 | 上传无大小与磁盘空间限制 | `Server.js:369` | 中危 | BR-18：单文件 20GB 上限 + 剩余空间检查 |
| D-05 | 端口占用/监听失败无错误处理，直接抛异常 | `Server.js:418-422` | 高危 | BR-02：端口回退 + 明确失败态 |
| D-06 | SSE 无心跳、无写失败处理、无订阅上限 | `SseUtil.js:25-30` | 中危 | BR-23、BR-24 |
| D-07 | 文件夹 ZIP 在事件循环内触发，大目录阻塞服务 | `Server.js:303-315`；`ZipUtil.js:10-23` | 中危 | BR-15、BR-16：后台队列 + 并发合并 + TTL |
| D-08 | 重启后 JWT 全部失效，旧分享链接变 401 | `Server.js:21-22` | 中危 | BR-04：每次启动重发链接，UI 明确提示 |
| D-09 | token 放在 URL query，可能进入历史/日志 | `Server.js:247-263`；`FilePage.vue:392-396` | 中危 | BR-36/BR-37：Fragment 换 HttpOnly Cookie，URL 不含长期凭证 |
| D-10 | FileDb 以名称为主键，同名条目互相覆盖 | `FileDb.js:12-22` | 中危 | BR-10：稳定 ID 作为主键 |
| D-11 | 分享列表与设置明文存储在 localStorage | `PlatformAdapterInstance.js:6-25` | 低危 | BR-32/BR-47：仅存 Keychain 密钥 HMAC 校验值，状态文件原子写 |
| D-12 | 前端声明了 `tusConfig` 与续传开关，但服务端无对应实现 | `FileApi.js:35-42`；`Setting.js:120-122` | 低危 | CalmBar 一期不做续传上传，不展示假开关 |

> 结论：参考实现的**产品形态值得复用**（HTTP + 浏览器 + 分享清单 + SSE），但**安全边界、错误处理、并发模型必须重写**，不能直接照搬 Node 实现。

---

## 2. 产品概述

### 2.1 产品背景

CalmBar 是常驻菜单栏的效率工具集，用户已经习惯「点开面板 → 用一个工具 → 收起」。当前缺少一个「把文件快速丢给旁边设备」的能力：AirDrop 在跨平台（Windows/Android）场景不可用，微信/网盘需要登录且慢，数据线与 U 盘又不够即时。

本功能的目标是：**在同一个 Wi-Fi 下，让对方用浏览器扫码/打开链接，就能双向传文件与文字，不装任何客户端。**

### 2.2 第一性原则分析

> 回到本质：局域网互传真正提供的是什么？

1. **本质需求**：让「另一台设备」在**不安装软件、不注册账号**的前提下，访问本机主动开放的一小组内容，并能反向投递内容。
2. **必要条件**：
   - 本机有一个可被局域网访问的 HTTP 服务；
   - 服务的地址能被对方低成本获得（链接/二维码）；
   - 内容边界由分享者显式控制（不是整盘共享）；
   - 接收端有零安装的 Web 页面；
   - 双向能力：下载 + 上传 + 文字；
   - 状态变化能及时可见（列表刷新）。
3. **硬约束**：
   - 只能在局域网；不做出公网穿透；
   - 不能破坏菜单栏常驻体验（不弹大窗、不抢焦点）；
   - 必须零第三方依赖（CalmBar 只允许 Sparkle）；
   - 必须可被系统防火墙/本地网络权限拦截，并能解释原因；
   - 传输大文件不能整文件进内存，不能阻塞主线程。

### 2.3 产品目标与非目标

**目标**

- G-01：用户从菜单栏面板 3 步内完成「开启互传 → 拿到链接/二维码」。
- G-02：接收端在 5 秒内打开页面并看到分享列表。
- G-03：支持单文件 ≥ 20GB 的稳定下载，内存占用不随文件增大。
- G-04：支持接收端上传文件与发送文字，分享端实时看到。
- G-05：默认只接受来源 IP 属于选定网卡前缀的连接，拒绝其他网段来源；**不承诺识别同前缀的 VPN、桥接或网段重叠设备**（见 BR-50）。
- G-06：所有失败都有可读原因与下一步动作。

**非目标（明确不做）**

- N-01：不做公网中转、NAT 穿透、跨互联网传输。
- N-02：不做设备间自动发现与配对（Bonjour 发现列为 P2）。
- N-03：不做手机原生 App。
- N-04：不做云同步、历史版本、回收站。
- N-05：不做 HTTPS 证书管理（局域网明文 HTTP，靠会话令牌与口令控制）。
- N-06：不做断点续传上传（tus）一期不实现，不展示假开关。
- N-07：不默认开机自启服务；服务状态不跨启动恢复。

### 2.4 可测指标

| 指标 | 目标值 | 测量口径 |
| --- | --- | --- |
| 开启耗时 | ≤ 500ms（端口可用且权限已授予） | 点击开关到状态变为「运行中」；首次权限确认时间不计入 |
| 首屏时间 | ≤ 300ms | 接收端从导航到列表渲染完成（同一局域网、Chrome） |
| 首字节时间 | ≤ 300ms（≤ 1GB 文件） | `curl -w time_starttransfer` |
| 有线吞吐 | ≥ 80MB/s | 1Gbps 有线，单连接，20GB 文件 |
| Wi-Fi 吞吐 | ≥ 30MB/s | 5GHz Wi-Fi 5，单连接，20GB 文件 |
| 大文件完整性 | SHA-256 一致 | 20GB 下载/上传各 1 次 |
| 内存增量（下载） | ≤ 40MB（20GB 下载） | `phys_footprint` 峰值 − 空闲基线；排除页缓存 |
| 内存增量（上传） | ≤ 64MB（20GB 上传） | 同上；含 Body 缓冲 ≤32MB；A/D 路线同一口径 |
| 空闲 CPU | ≤ 1% | 服务运行但无连接，采样 60 秒 |
| 传输 CPU | ≤ 25% 单核 | 单连接满速下载 |
| 列表刷新延迟 | MVP ≤ 3s；P2 ≤ 500ms | 上传完成到另一端列表更新 |
| 断线重连 | ≤ 5s 恢复 | 关闭 Wi-Fi 再打开 |
| 异常可读率 | 100% | 验收用例中所有失败均有中文提示 |

### 2.5 系统范围与组件定义

| 组件 | 类型 | 职责 | 是否新增 |
| --- | --- | --- | --- |
| `LANShareFeature` | Feature | 生命周期、状态、命令、权限声明 | 新增 |
| `LANShareService` | Service（@MainActor） | 对 UI 暴露 start/stop/add/remove/copyLink 等 | 新增 |
| `LANShareHTTPServer` | Service（后台） | NWListener、连接管理、路由分发、流式收发 | 新增 |
| `LANShareHTTPParser` | Service（后台） | **最小 HTTP/1.1 子集** + 流式 multipart/请求体 | 新增 |
| `LANShareSessionManager` | Service | 会话凭证签发、校验、过期与撤销 | 新增 |
| `LANSharePathValidator` | Service | 路径标准化、符号链接策略、fd 级 TOCTOU 校验 | 新增 |
| `LANShareTransferManager` | Service | 传输任务、进度、并发、取消与限速 | 新增 |
| `LANShareStore` | Service | 分享条目、设置快照、JSON 持久化 | 新增 |
| `LANShareNetworkMonitor` | Service | 选定网卡/前缀、`NWPathMonitor` 变化通知 | 新增 |
| `LANShareZipper` | Service | 调系统 `ditto` 打包 ZIP、缓存与清理 | 新增 |
| `LANShareWeb/` | 资源 | 接收端 HTML/CSS/JS | 新增 |
| `LANShareWindowController` | UI | 独立管理窗口 | 新增 |
| `GatewayHTTPServer` | 现有 | AI 网关的 loopback HTTP 服务 | 复用写法，不改行为 |
| `UpdateRelayServer` | 现有 | 更新中转，`.any` 监听与 token 链接 | 复用写法 |
| `PermissionManager` | 现有 | 新增「本地网络」权限说明 | 扩展 |
| `RecoveryCoordinator` | 现有 | 退出/休眠关闭服务 | 扩展 |
| `SettingsTab` / `SettingsView` | 现有 | 新增设置 Tab | 扩展 |
| `CommandCenter` | 现有 | 新增命令与别名 | 扩展 |

### 2.6 与 CalmBar 现有能力的复用对照

| 需求 | 现有可复用资产 | 复用方式 |
| --- | --- | --- |
| HTTP 服务 | `Services/AIGateway/GatewayHTTPServer.swift:498-588`（NWListener 生命周期、连接表、stop） | 参考其生命周期与锁策略；**不共享实例**，避免影响 AI 网关 |
| 分块响应 | `GatewayHTTPServer.swift:336-360`（chunked 写流） | 参考实现方式，用于 SSE 与 ZIP 流 |
| `.any` 监听与 token 链接 | `Update/UpdateRelayServer.swift:19-34` | 参考 `NWListener(using:on: .any)` 与随机 token |
| 本地网络权限 | `Core/PermissionManager.swift`（现有四类权限） | 新增 `.localNetwork` 类型与设置页入口 |
| 生命周期恢复 | `Recovery/RecoveryAction.swift`、`RecoveryCoordinator` | 新增 `stopLANShareServer` 动作 |
| 设置与搜索 | `SettingsTab`、`SettingsCategory`、搜索关键词 | 新增 Tab，补齐关键词 |
| 命令面板 | `CommandCenter`、`FeatureCommand` | 新增「开启/停止互传」「复制互传链接」 |
| 二维码 | CoreImage `CIFilter.qrCodeGenerator()` | 本机生成，无外部依赖 |
| 文件操作 | Foundation + `/usr/bin/ditto` | 系统自带，不新增依赖 |

> 技术选型结论：**无需引入任何第三方库**。HTTP 服务用 `Network.framework`，二维码用 CoreImage，ZIP 用系统 `ditto`，持久化用 JSON + UserDefaults，均可满足 APP-09。

---

### 2.7 补充需求（R-01 ~ R-05）

| 编号 | 需求 | 规则落点 | 验收方式 |
| --- | --- | --- | --- |
| R-01 | 恶意网页跨站访问防护 | BR-38、BR-39：Host/Origin/Referer 校验 + `X-CalmBar-Client` + SameSite=Strict | A-22：伪造请求全部 403 |
| R-02 | 上传文件类型与文件名规则 | BR-19：清洗路径分隔符、控制字符、首尾点/空格；保留扩展名；≤255 字节 | A-07 + 单元测试覆盖特殊字符 |
| R-03 | 服务端连接超时 | BR-40：请求头 10s、请求体空闲 30s、上传总时长 24h、单 IP/全局连接上限 | 慢速客户端 30s 内被断开 |
| R-04 | 目录变化检测 | BR-41：列表/下载请求时 stat 校验；失效条目显示「已失效」；不自动删列表 | 外部删除文件后 3s 内标记失效 |
| R-05 | 文件并发修改 | BR-42：按已打开 fd 读取，fstat 校验 dev/ino；旧连接读旧 inode，禁止跨 inode 拼接 | 下载中替换文件，SHA-256 与打开时版本一致 |

> 编号约定：`D-xx` 表示第 1.6 节对参考实现的缺陷编号，`R-xx` 专指本节的补充需求编号，两者互不混用。

---

## 3. UML 用例模型

### 3.1 系统用例图

```text
                    ┌──────────────────────── CalmBar 局域网互传 ────────────────────────┐
                    │                                                                    │
   ┌────────┐       │  (UC-01 开启/关闭互传)      (UC-02 管理分享列表)                    │
   │ 分享者  │───────┼──► (UC-03 查看链接与二维码)  (UC-08 修改设置)                       │
   │(本机用户)│       │                                                                    │
   └────────┘       │  (UC-09 网络变化与休眠恢复)  (UC-10 异常处理)                       │
                    │                                                                    │
   ┌────────┐       │  (UC-04 浏览与下载)  ──include──► (UC-07 列表刷新)                  │
   │ 接收者  │───────┼──► (UC-05 上传文件/发文字) ──extend──► (UC-06 会话认证)             │
   │(浏览器) │       │                                                                    │
   └────────┘       │                                                                    │
                    │  (UC-11 临时文件清理与退出)                                          │
   ┌────────┐       │                                                                    │
   │ macOS  │───────┼──► 防火墙 / 本地网络权限 / 磁盘空间                                   │
   │  系统  │       │                                                                    │
   └────────┘       └────────────────────────────────────────────────────────────────────┘
```

### 3.2 参与者定义

| 参与者 | 说明 | 主要诉求 |
| --- | --- | --- |
| 分享者 | 本机 CalmBar 用户 | 快速开放内容、控制边界、随时停止 |
| 接收者 | 同网段浏览器用户（手机/PC/平板） | 不装软件就能看、下、传 |
| 系统 | macOS 防火墙、本地网络隐私、磁盘 | 权限与资源约束 |

### 3.3 用例列表

| 编号 | 用例 | 参与者 | 优先级 |
| --- | --- | --- | --- |
| UC-01 | 开启与关闭互传服务 | 分享者 | 高 |
| UC-02 | 管理分享列表 | 分享者 | 高 |
| UC-03 | 查看/复制链接与二维码 | 分享者 | 高 |
| UC-04 | 浏览与下载 | 接收者 | 高 |
| UC-05 | 上传文件与发送文字 | 接收者 | 高 |
| UC-06 | 会话认证（无口令 / 口令） | 接收者 | 中 |
| UC-07 | 列表刷新（MVP 轮询 / P2 SSE） | 接收者 | 中 |
| UC-08 | 修改设置 | 分享者 | 中 |
| UC-09 | 网络变化与休眠唤醒恢复 | 系统 / 分享者 | 中 |
| UC-10 | 异常处理 | 系统 / 分享者 | 高 |
| UC-11 | 临时文件清理与退出 | 系统 / 分享者 | 中 |

### 3.4 用例关系

- UC-04 **include** UC-07：浏览过程中列表变化需要刷新（MVP 3 秒轮询，P2 SSE）。
- UC-05 **extend** UC-06：开启口令时，上传前必须先完成会话认证。
- UC-09 **extend** UC-01：仅在「运行意图」存在时自动恢复。
- UC-10 **extend** UC-01/UC-04/UC-05：任何环节失败进入统一错误呈现。

---

## 4. 详细用例规格

### UC-01 开启与关闭互传服务

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-01 |
| **用例名称** | 开启与关闭互传服务 |
| **参与者** | 分享者 |
| **优先级** | 高 |
| **前置条件** | CalmBar 已启动；用户已打开「局域网互传」窗口或在命令面板执行命令 |
| **后置条件** | 服务运行中：监听端口可用、链接与二维码可见；服务停止：无监听、无活动连接、令牌失效 |
| **基本事件流** | 1. 用户点击「开始互传」<br>2. 系统读取端口、接收目录、口令开关，校验目录可写<br>3. 系统选择局域网地址并启动 NWListener<br>4. 监听就绪后生成会话令牌与链接，状态变为「运行中」<br>5. 界面展示链接、二维码、当前连接数<br>6. 用户点击「停止互传」<br>7. 系统关闭监听与全部连接，清空令牌，状态变为「已停止」 |
| **备选事件流** | 2a. 接收目录不可写：系统提示「接收文件夹不可写，请重新选择」，保持停止态<br>3a. 端口被占用：按 BR-02 自动尝试后续端口，成功后展示实际端口；全部失败则提示并保持停止态<br>3b. 本地网络权限/防火墙拒绝：状态变为「被系统阻止」，展示原因与打开系统设置按钮<br>6a. 存在活动传输：先提示「停止会中断 N 个正在进行的传输」，确认后停止 |
| **业务规则** | BR-01、BR-02、BR-03、BR-04、BR-07、BR-25、BR-26、BR-27、BR-35 |

**数据说明**

- 输入：`LANShareSettings`（A-2）
- 输出：`LANShareSession`（A-3）、`LANShareStatus`（A-3）

**接口说明**：`LANShareService.start() async throws -> LANShareSession`、`stop(reason:)`

---

### UC-02 管理分享列表

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-02 |
| **用例名称** | 管理分享列表 |
| **参与者** | 分享者 |
| **优先级** | 高 |
| **前置条件** | 已打开互传窗口 |
| **后置条件** | 分享列表与持久化状态一致；接收端下次请求可见 |
| **基本事件流** | 1. 用户拖入文件/文件夹，或点击「添加文件/文件夹/文字」<br>2. 系统校验路径存在且可读<br>3. 系统生成稳定 ID 写入列表并持久化<br>4. 列表立即显示条目（名称、类型、大小、来源）<br>5. 用户可移除单项或清空列表<br>6. 移除仅影响分享列表，不删除源文件 |
| **备选事件流** | 2a. 路径不可读：拒绝并提示具体原因<br>2b. 重复添加同一路径：聚焦已有条目并提示「已在分享列表中」，不产生重复项<br>2c. 文字超过 100,000 字符：拒绝并提示上限<br>5a. 清空列表：二次确认，确认后清空并广播 |
| **业务规则** | BR-08、BR-09、BR-10、BR-11、BR-12、BR-30、BR-33 |

**数据说明**

- 主表：`LANShareItem`（A-1）
- 持久化：`~/Library/Application Support/CalmBar/LANShare/state.json`

**接口说明**：`addItems(_:) throws`、`removeItem(id:)`、`clearItems()`

---

### UC-03 查看/复制链接与二维码

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-03 |
| **用例名称** | 查看/复制链接与二维码 |
| **参与者** | 分享者 |
| **优先级** | 高 |
| **前置条件** | 服务处于运行中 |
| **后置条件** | 剪贴板包含完整链接；二维码可被扫码打开 |
| **基本事件流** | 1. 系统根据当前网卡生成 `http://<ip>:<port>/`；无口令时使用 **URL Fragment** 携带链接令牌：`http://<ip>:<port>/#t=<token>`<br>2. 页面 JS 读取 `location.hash`，通过 `POST /api/session` 用链接令牌换取 **HttpOnly 会话 Cookie**，随后 `history.replaceState` 清除地址栏令牌<br>3. 界面展示可复制的短链接文本与二维码<br>4. 用户点击「复制链接」，系统写入剪贴板并 2 秒内提示「已复制」<br>5. 用户可切换网卡/IP 协议，链接与二维码同步刷新 |
| **备选事件流** | 1a. 无可用局域网 IP：展示「未连接到局域网」并禁用复制/二维码<br>1b. 选择了 VPN/虚拟网卡：默认过滤，用户可在高级设置手动指定<br>1c. 浏览器不支持/禁用 Cookie：页面提示「当前浏览器无法保存会话，请更换浏览器」，不降级为 URL 长期令牌<br>5a. 切换后监听未变但地址变化：仅刷新展示，不重启服务 |
| **业务规则** | BR-04、BR-25、BR-29、BR-34、BR-36、BR-37、BR-38、BR-49 |

**接口说明**：`currentShareLink: URL?`、`qrImage(size:) -> NSImage?`

---

### UC-04 浏览与下载

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-04 |
| **用例名称** | 浏览与下载 |
| **参与者** | 接收者 |
| **优先级** | 高 |
| **前置条件** | 服务运行中；网络可达；若开启口令则已认证 |
| **后置条件** | 文件被完整下载；服务端连接释放；临时 ZIP 进入 TTL 清理 |
| **基本事件流** | 1. 接收者打开链接，页面加载分享根列表<br>2. 点击文件夹进入子目录，面包屑显示相对路径<br>3. 点击文件下载，浏览器开始接收<br>4. 点击文件夹下载，服务端打包 ZIP 后返回<br>5. 下载完成后连接关闭，服务端记录完成状态 |
| **备选事件流** | 1a. 服务已停止：页面提示「分享已结束」，不暴露任何列表<br>2a. 目录不存在/已被移除：返回 404，页面回退上一级并提示<br>3a. 客户端断开：服务端停止读取并在 5 秒内回收连接<br>4a. 打包失败：返回 500，页面提示「打包失败，请重试」<br>4b. 打包中重复点击：复用同一打包任务，不重复打包<br>5a. 磁盘读取失败：返回 500，记录日志，不泄露绝对路径 |
| **业务规则** | BR-09、BR-10、BR-13、BR-14、BR-15、BR-16、BR-17、BR-28、BR-31 |

**数据说明**：`LANShareItem`（A-1）、`ZipCacheEntry`（A-4）

**接口说明**：`GET /api/items`、`GET|HEAD /api/download`

---

### UC-05 上传文件与发送文字

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-05 |
| **用例名称** | 上传文件与发送文字 |
| **参与者** | 接收者 |
| **优先级** | 高 |
| **前置条件** | 服务运行中；`allowUpload = true`；若开启口令则已认证 |
| **后置条件** | 文件保存到接收目录并出现在双方列表；文字进入列表 |
| **基本事件流** | 1. 接收者拖入或选择文件，页面显示上传进度<br>2. 服务端校验 `可用空间 ≥ Content-Length + 2GB` 后，在接收目录下 `.calmbar-tmp/` 流式写入临时文件<br>3. 校验文件名与完整性后，在同卷内原子 `rename` 到接收目录<br>4. 生成 `origin=remote` 的分享条目并递增 revision（P2 额外广播 SSE）<br>5. 分享端立即出现；接收端在 3 秒轮询内出现（P2 为 500ms）<br>6. 接收者输入文字并发送，服务端创建文字条目并递增 revision |
| **备选事件流** | 1a. `allowUpload=false`：页面隐藏入口，直接请求返回 403<br>2a. 单文件超过 20GB：返回 413，页面提示上限<br>2b. 可用空间 < `Content-Length + 2GB`：返回 507，提示清理空间<br>2c. 写入过程中触发 ENOSPC：关闭 fd、删除临时文件，返回 507<br>2d. 连接中断：删除临时文件，不产生半成品<br>3a. 同名文件：自动追加 ` (1)`、` (2)`，不覆盖<br>6a. 文字为空：返回 400，页面提示「内容不能为空」 |
| **业务规则** | BR-18、BR-19、BR-20、BR-21、BR-22、BR-30、BR-52 |

**数据说明**：`LANShareItem`（A-1），`source=remote`、`uploaderIP`

**接口说明**：`POST /api/upload`（multipart/form-data）、`POST /api/text`（JSON）

---

### UC-06 会话认证（无口令 / 口令）

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-06 |
| **用例名称** | 会话认证（无口令 / 口令） |
| **参与者** | 接收者 |
| **优先级** | 高 |
| **前置条件** | 服务运行中；请求来源属于选定网卡前缀 |
| **后置条件** | 通过校验后获得 HttpOnly 会话 Cookie；失败不泄露任何列表信息 |
| **基本事件流** | **页面初始化（两种模式共用）**：0. 页面加载后先请求 `GET /api/bootstrap`（无需 Cookie），仅返回 `{serverName, passcodeRequired, authMode}`，用于决定展示口令框还是走链接令牌；不含列表、权限或路径信息<br>**无口令模式**：1. 接收者打开带 `#t=<linkToken>` 的链接<br>2. 页面读取 Fragment，提交 `POST /api/session {linkToken}`<br>3. 服务端以恒定时间比较链接令牌，通过后签发 256-bit 随机会话 ID<br>4. 响应 `Set-Cookie: calmbar_session=<id>; HttpOnly; SameSite=Strict; Path=/; Max-Age=1800`<br>5. 页面清除地址栏 Fragment 并加载列表<br>**口令模式**：1. 链接不含任何令牌，页面依据 bootstrap 结果直接显示 6 位口令输入框<br>2. 提交 `POST /api/session {passcode}`<br>3. 服务端用 Keychain 密钥做 HMAC 校验，通过后签发同样的会话 Cookie |
| **备选事件流** | 0a. `GET /api/bootstrap` 不可用：页面显示「无法连接分享，请刷新重试」，不显示口令框<br>1a. 无口令模式下缺少/错误 linkToken：返回 401，**绝不无条件签发会话**<br>2a. 口令错误：统一提示「口令不正确」，不区分原因<br>2b. 单 IP 连续 10 次失败：锁定 60 秒，返回 429；全局限流 30 次/分钟<br>2c. 会话 30 分钟无操作：滑动过期，页面回到认证页<br>2d. 分享者刷新口令或停止服务：全部旧会话立即失效<br>2e. 请求 Host/Origin 不匹配：返回 403，拒绝 DNS Rebinding 与跨站请求 |
| **业务规则** | BR-05、BR-06、BR-29、BR-36、BR-37、BR-38、BR-39、BR-47、BR-49 |

**接口说明**：`GET /api/bootstrap`（无需 Cookie）、`POST /api/session`、`DELETE /api/session`（清除 Cookie）

**会话滑动过期规则（BR-05 展开）**

- 服务端会话 TTL 与浏览器 Cookie 必须同步：每次有效请求（非 401/403/静态资源）都同时延长服务端 `expiresAt` 并通过响应头重发 `Set-Cookie: ...; Max-Age=1800`。
- 有效期只延长、不缩短：`newExpiry = max(currentExpiry, now + 30min)`；并发请求按此规则合并，禁止旧请求把新的活动时间覆盖为更早值。
- 若浏览器拒绝频繁刷新 Cookie，可退化为「会话 Cookie（无 `Max-Age`）+ 服务端 30 分钟滑动 TTL」，但必须在 Spike S-05 中验证 Safari/Chrome 行为后二选一，不得两者都不做。
- 过期判定以服务端时钟为准；客户端时间不可信。

---

### UC-07 列表刷新（MVP 轮询 / P2 SSE）

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-07 |
| **用例名称** | 列表刷新（MVP 轮询 / P2 SSE） |
| **参与者** | 接收者 |
| **优先级** | 中 |
| **前置条件** | 页面已认证；服务运行中 |
| **后置条件** | 列表变化在 3 秒内可见（MVP）；P2 升级为 SSE 后 ≤ 500ms |
| **基本事件流** | **MVP**：1. 页面每 3 秒请求一次 `GET /api/items`<br>2. 仅在页面可见（`document.visibilityState === "visible"`）且无输入焦点时刷新<br>3. 比较 `revision`，未变化则不重绘<br>**P2**：1. 页面建立 `GET /api/events` SSE 连接<br>2. 服务端每 15 秒心跳<br>3. 列表变化广播 `items_changed`<br>4. 页面收到事件后重拉当前路径列表 |
| **备选事件流** | 1a. 请求失败：指数退避 3/6/12/24 秒，上限 30 秒<br>1b. 服务停止：提示「分享已结束」，停止轮询<br>2a.（P2）SSE 写失败：服务端移除订阅并关闭连接<br>2b.（P2）SSE 不可用：自动降级为 3 秒轮询 |
| **业务规则** | BR-23、BR-24 |

**接口说明**：`GET /api/items`（MVP）、`GET /api/events`（P2，`text/event-stream`）

---

### UC-08 修改设置

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-08 |
| **用例名称** | 修改设置 |
| **参与者** | 分享者 |
| **优先级** | 中 |
| **前置条件** | 已打开设置页「局域网互传」 |
| **后置条件** | 设置持久化；需要重启监听的项目按规则生效 |
| **基本事件流** | 1. 用户修改接收目录、端口、口令开关、允许上传开关<br>2. 系统即时校验（目录可写、端口 1024~65535）<br>3. 无需重启的项立即生效；端口变更提示「保存并重启互传」<br>4. 保存成功提示，状态与链接同步更新 |
| **备选事件流** | 2a. 目录不可写：输入框标红并提示<br>2b. 端口非法：拒绝保存<br>3a. 端口变更时有活动连接：二次确认，确认后停止并重启，令牌轮换<br>3b. 口令变更：立即撤销全部旧会话、重新生成 `linkToken`；口令模式下旧链接因口令已变而失效，需重新分享<br>3c. 关闭允许上传：立即拒绝新上传，并取消所有未完成上传任务、清理其临时文件（BR-52）；已完成文件保留<br>4a. 开启口令但未设置口令：自动生成 6 位数字并展示一次 |
| **业务规则** | BR-07、BR-32、BR-35、BR-52 |

**接口说明**：`LANShareService.updateSettings(_:) async throws`

---

### UC-09 网络变化与休眠唤醒恢复

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-09 |
| **用例名称** | 网络变化与休眠唤醒恢复 |
| **参与者** | 系统、分享者 |
| **优先级** | 中 |
| **前置条件** | 服务曾处于运行态 |
| **后置条件** | 地址变化后链接正确；旧连接明确终止；唤醒后服务可用或明确提示失败 |
| **优先级说明** | **MVP（P1）只覆盖网络变化**：刷新链接、旧连接明确失败。**休眠唤醒自动恢复属 P2**，MVP 仅在唤醒后展示「已停止，请重新开启」 |
| **基本事件流** | **P1 网络变化**：1. `NWPathMonitor` 检测到网卡/IP 变化<br>2. 3 秒内刷新当前网段地址、链接与二维码<br>3. 旧网卡上的连接可能已失效：服务端在 5 秒内清理并标记对应传输为「已中断」<br>4. 接收端用新链接重新发起请求；支持 Range 的客户端可从断点继续<br>**P2 休眠唤醒**：5. 系统休眠前停止监听并记录「运行意图」<br>6. 唤醒后若运行意图存在，自动重建监听并刷新链接 |
| **备选事件流** | 2a. 新网络无可用局域网地址：展示「当前网络不可用于互传」<br>2b. 旧连接仍可写：允许自然结束，但不承诺一定成功<br>（P2）6a. 自动恢复失败：状态变为「已停止」并提示一次，不循环重试<br>（P2）6b. 用户在休眠期间手动停止：清除运行意图，唤醒后不恢复 |
| **业务规则** | BR-25、BR-26、BR-42 |

**接口说明**：`LANShareNetworkMonitor.onChange: (LANShareNetworkState) -> Void`

---

### UC-10 异常处理

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-10 |
| **用例名称** | 异常处理 |
| **参与者** | 系统、分享者 |
| **优先级** | 高 |
| **前置条件** | 任意阶段 |
| **后置条件** | 用户看到可读原因与可执行动作；系统不崩溃、不静默 |
| **基本事件流** | 1. 系统捕获端口占用、权限拒绝、磁盘不足、路径失效、ZIP 失败、连接异常<br>2. 映射为 `LANShareError`（含中文描述与建议动作）<br>3. 界面展示对应状态与按钮（重试/更换端口/打开系统设置/重新选择目录）<br>4. 记录一条脱敏日志 |
| **备选事件流** | 1a. 同一错误 30 秒内重复：合并提示，不刷屏<br>1b. 未知错误：提示「发生未知错误」并附错误码，不展示堆栈 |
| **业务规则** | BR-27、BR-35 |

**数据说明**：`AccessLogEntry`（A-5）

---

### UC-11 临时文件清理与退出

| 项目 | 内容 |
| --- | --- |
| **用例编号** | UC-11 |
| **用例名称** | 临时文件清理与退出 |
| **参与者** | 系统、分享者 |
| **优先级** | 中 |
| **前置条件** | 存在 ZIP 缓存或上传临时文件 |
| **后置条件** | 临时文件被清理；源文件与已接收文件不受影响 |
| **基本事件流** | 1. ZIP 临时文件写入后记录创建时间<br>2. 满 30 分钟或服务启动时清理过期缓存<br>3. 停止/退出按 BR-51 固定顺序执行：拒绝新请求 → 撤销会话 → 关闭连接 → 关闭传输 fd → 终止 `ditto` 子进程 → 删除 `.calmbar-tmp/` 与 ZIP 临时文件<br>4. 异常退出的残留只清理 `.calmbar-tmp/` 与已知临时命名，不触碰用户文件 |
| **备选事件流** | 2a. ZIP 正在被下载：延迟删除，引用计数归零后再删<br>3a. 清理失败：记录日志，不阻塞退出 |
| **业务规则** | BR-15、BR-16、BR-33、BR-51 |

---

### 4.12 业务规则定义（BR-01 ~ BR-53）

> 第 4 章前 11 节依次为 UC-01 ~ UC-11，本节为第 12 节。本表是全文 BR 的唯一权威定义。各处用例与竞态清单引用 BR 编号时，以本表为准；如与旧描述冲突，以本表为准。

| 编号 | 名称 | 规则 | 触发条件 | 处理方式 | 验收方式 |
| --- | --- | --- | --- | --- | --- |
| BR-01 | 服务默认关闭 | 仅用户显式开启后才监听；退出/停用/关闭功能立即关闭监听与连接 | 启动、退出、停用、关闭功能 | 关闭 listener、取消连接、清空令牌 | 退出后端口可立即复用 |
| BR-02 | 端口回退 | 默认 47820；占用时 +1 尝试至 47829；全部失败进入 failed 并提示 | 启动监听 | 自动重试；失败不静默 | 占用 47820 后自动用 47821 |
| BR-03 | 来源边界 | 仅接受「来源 IP 落在选定网卡前缀内」的连接；IPv4 按掩码、IPv6 按前缀长度分别判定；回环不视为局域网客户端；能可靠识别入站接口时再叠加接口校验 | 每个连接建立 | 非前缀内来源直接 403 并关闭 | 跨前缀设备无法访问；IPv6 ULA/链路本地单独验证 |
| BR-04 | 链接令牌 | 32 字节 CSPRNG（256-bit），URL-safe；每次启动重新生成，停服即失效，不落盘 | 服务启动 | 仅放内存；UI 仅展示前 4 位 | 重启后旧链接 401 |
| BR-05 | 会话过期 | 会话 30 分钟滑动过期，服务端 TTL 与 Cookie `Max-Age` 同步刷新；最多 5 个并发会话；认证失败绝不签发 | 每次有效请求/认证 | 过期或超额返回 401 | 30 分钟无操作后 401；持续操作不中断 |
| BR-06 | 认证限流 | 单 IP 连续 10 次失败锁 60 秒；全局 30 次/分钟；文案统一 | 口令/linkToken 校验失败 | 返回 429 或统一 401 文案 | 暴力尝试被锁定 |
| BR-07 | 变更需重启 | 端口、接收目录、口令开关变更需重启监听或撤销会话；重启前二次确认 | 保存设置 | 停止→重建→轮换令牌 | 改端口后旧链接失效 |
| BR-08 | 显式分享 | 分享项只有文件/文件夹/文字；根列表只展示显式添加项，不展示任意目录 | 列表请求 | 返回分享清单 | 根列表不含未添加文件 |
| BR-09 | 路径安全 | 解码→标准化→符号链接策略→前缀校验；拒绝 `..`、NUL、超长与越界路径 | 所有文件访问 | 403；不泄露真实路径 | 路径穿越测试全 403 |
| BR-10 | 稳定主键 | 条目以 UUID 为主键；URL 使用 ID + 相对路径；不暴露绝对路径 | 添加/访问 | 生成 UUID；映射内部路径 | 重命名/同名不冲突 |
| BR-11 | 文字上限 | 单条文字 ≤ 100,000 字符；标题取前 20 字符；摘要取前 100 字符 | 发送文字 | 超限 400 | 100,001 字符被拒 |
| BR-12 | 移除不删源 | 移除分享项/停止服务不删除源文件；停服期间列表不可访问 | 移除/停止 | 仅更新列表与 revision | 源文件仍在 |
| BR-13 | 流式下载 | 下载必须流式发送；单连接读缓冲 ≤ 1MB；禁止整文件入内存 | 任意下载 | FileHandle 分块读 | 20GB 下载内存 ≤ 40MB |
| BR-14 | Range 语义 | 支持 HEAD、单区间 `bytes=a-b` / `bytes=a-` / `bytes=-n`、ETag/Last-Modified、206/416；越界 416；多区间 416；不支持 `If-Range`（收到按完整 200 返回）；文件大小用 Int64 | 下载请求 | 解析单区间三种形式；非法 416 | 三种形式字节一致；Safari/Chrome 实测记录 |
| BR-15 | ZIP 策略 | MVP 不缓存，按需打包；响应完成/失败/10 分钟后删除；P2 才引入指纹缓存（30 分钟 TTL） | 文件夹下载 | 生成临时 ZIP；引用计数清理 | 修改子文件后重新打包 |
| BR-16 | 打包并发 | 同一路径并发打包按「服务生命周期 generation + 条目 ID + 相对路径」合并为一个任务（**不使用单请求 ID**）；每个下载请求登记 waiter，单个断开只移除该 waiter，全部移除后才取消 ZIP；失败 500 | 并发文件夹下载 | 任务表合并 + waiter 引用计数 | 并发点击只产生一个 ZIP；A 断开不影响 B |
| BR-17 | 下载限流 | 单 IP 并发下载 ≤ 4，全局连接 ≤ 32；超限 429 | 新连接 | 计数与排队 | 第 5 个并发被拒 |
| BR-18 | 上传限制 | 仅 multipart；流式写临时文件（接收目录下 `.calmbar-tmp/`，保证同卷）；**两阶段校验**：返回 100 前校验 Content-Length 合法、请求体总量 ≤ 20GB + 8MB、认证、权限、CSRF、配额、`可用空间 ≥ Content-Length + 2GB`；接收过程中校验实际文件 Part ≤ 20GB，超限立即中断并清理；ENOSPC 关 fd、删临时文件、返回 507 | 上传请求 | 同卷临时文件 + 边读边写 + 两阶段校验 | 20GB 上传成功；超限/满盘均无残留 |
| BR-19 | 文件名与占位 | 清洗路径分隔符/控制字符/首尾空格与点；重名追加 ` (n)`；占位阶段：接收目录内 `O_CREAT\|O_EXCL` 建占位并写入扩展属性 `com.calmbar.placeholder=<uuid>`，记录 dev/ino；写 `.calmbar-tmp/` 临时文件；提交用 `renameatx_np(..., RENAME_EXCL)` **不覆盖已有目标**，遇 `EEXIST` 重新分配 `(n)` 名并重占位；失败删除占位与临时文件；崩溃恢复只清理「带占位 xattr 且 dev/ino 匹配」的文件，绝不按零字节批量删除；文件名 ≤ 255 字节 | 上传落盘 | inode 校验 + RENAME_EXCL 提交 | 外部同名文件不被覆盖；用户零字节文件不被误删 |
| BR-20 | 上传入库 | 成功写入后加入列表（source=remote），revision+1；失败清理临时文件 | 上传完成/失败 | 原子写 + 列表更新 | 双方 3 秒内可见 |
| BR-21 | 上传权限 | 关闭上传时接口 403 且页面隐藏入口；不得仅前端隐藏 | 上传/文字请求 | 服务端强制校验 | 直接请求也被拒 |
| BR-22 | 文字入库 | 文字与文件同等进入列表并持久化；接收端可复制 | 发送文字 | 创建 text 条目 | 重启后仍在 |
| BR-23 | 刷新机制 | MVP 3 秒轮询（页面可见时）；P2 SSE 心跳 15 秒、指数退避、失败降级轮询 | 列表页打开 | 轮询/事件 + revision 比对 | 上传后 3 秒内可见 |
| BR-24 | SSE 约束（P2） | 绑定会话；单 IP ≤ 2 订阅；SSE 独立配额 32，**计入**全局 64 连接上限；写失败立即移除并关闭 | 订阅/广播 | 快照遍历 + 失败剔除 | 订阅泄漏为 0；SSE 与普通请求不互斥耗尽 |
| BR-25 | 网络变化 | IP/网卡变化 3 秒内刷新链接与二维码；监听可保持；**不承诺旧连接不中断** | 网络路径变化 | 刷新地址；5 秒内清理失效连接 | 切换网络后新链接可用 |
| BR-26 | 休眠恢复（P2） | 休眠前停止监听并记录运行意图；唤醒后最多自动恢复 1 次；失败提示 1 次 | 休眠/唤醒 | 状态机恢复或停止 | 合盖唤醒后状态正确 |
| BR-27 | 权限受限 | 本地网络/防火墙被拒时进入 restricted，提供系统设置入口，不循环弹窗 | 权限拒绝 | 状态与引导 | 拒绝后有明确提示 |
| BR-28 | 安全响应头 | 全部响应 `nosniff`、`no-referrer`；API `no-store`；页面 CSP `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'`；**禁止内联脚本/样式**，全部走同源外部资源 | 所有响应 | 固定头注入 | CSP 扫描无 inline 违规 |
| BR-29 | 令牌保护 | 恒定时间比较；UI 仅显示前 4 位；日志不得出现完整令牌/口令 | 认证与日志 | 脱敏 | 日志扫描无令牌 |
| BR-30 | 根目录可读 | 添加分享时必须存在且可读；不可读拒绝并提示 | 添加条目 | 预检 | 不可读目录被拒 |
| BR-31 | 最小接口面 | 接收端仅列表/下载/上传/文字/事件；无删除/重命名/移动/执行/任意路径 | 任意请求 | 路由白名单 | 未声明路由 404/405 |
| BR-32 | 持久化边界 | 列表与设置持久化；口令不落明文；服务状态不持久化 | 退出/启动 | JSON + Keychain | 重启默认停止 |
| BR-33 | 原子状态 | 状态文件临时文件 + 原子替换；损坏时备份并回退空列表 | 每次写入/读取 | 原子写 + 容错 | 模拟损坏可恢复 |
| BR-34 | 二维码即凭证 | 二维码与链接等价，含完整 linkToken，属访问凭证；面板不展示明文令牌，复制后 2 秒内提示；UI 注明「请只向可信的人展示二维码」；停止服务或轮换令牌后旧二维码立即失效 | 展示/复制 | 脱敏展示 + 明确提示 | 截图不含明文令牌；旧二维码失效 |
| BR-35 | 错误可读 | 所有失败给中文原因与下一步动作；禁止只给错误码 | 任意失败 | 错误映射 | 验收用例 100% 有文案 |
| BR-36 | 会话 Cookie | 会话凭证仅存 HttpOnly + SameSite=Strict Cookie；不写 localStorage；停服/刷新口令/改端口即撤销 | 认证成功 | `Set-Cookie` 下发 | JS 无法读取 Cookie |
| BR-37 | 下载认证 | 下载使用同源 Cookie；URL 不含长期令牌；如需 URL 凭证，必须单次、60 秒、限定 item/path/Range 的 ticket（P2） | 下载导航 | Cookie 校验；ticket 备用 | 下载 URL 无长期 token |
| BR-38 | 请求来源校验 | Host 必须匹配当前地址/端口；校验 Origin/Referer；拒绝 DNS Rebinding 与跨站来源 | 每个请求 | 不匹配 403 | 伪造 Host/Origin 被拒 |
| BR-39 | CSRF 防护 | POST 必须带 `X-CalmBar-Client: web`，且 Origin 同源或为空；SameSite=Strict | 状态变更请求 | 缺失即 403 | 跨站表单请求失败 |
| BR-40 | 连接超时 | 请求头 10 秒、请求体空闲 30 秒、上传总时长 24 小时；单 IP 连接 ≤ 8，全局 ≤ 64（含 P2 SSE，SSE 另受 BR-24 的 32 上限约束） | 连接生命周期 | 超时关闭并计数 | 慢速攻击被断开 |
| BR-41 | 目录变化 | 列表/下载时校验条目存在性；失效条目显示「已失效」；下载 404；不自动删列表 | 列表/下载 | stat 校验 + 标记 | 外部删除后标记失效 |
| BR-42 | 并发修改 | 下载打开 fd 后按 fd 读取；源文件被替换时旧连接读旧 inode，新请求读新文件；禁止跨 inode 拼接 | 下载期间文件变化 | fd + fstat 校验 | 下载中替换文件不损坏 |
| BR-43 | 传输任务（P1） | 每个传输生成 TransferTask，P1 至少可见：文件名、方向、已传输字节/总量、状态、取消；实时速度/剩余时间/历史记录属 P2 | 上传/下载开始 | 任务表 + 进度回调 | 进度与实际字节一致 |
| BR-44 | TOCTOU 防护 | 校验时记录 dev/ino；打开使用 `O_NOFOLLOW`（最终组件）或 `openat` 链；`fstat` 复核 dev/ino；禁止只做字符串前缀判断 | 文件打开 | fd 级校验 | 并发替换符号链接测试失败即拒 |
| BR-45 | ZIP 指纹 | P2 缓存指纹必须递归包含子项 mtime/size/inode；MVP 不缓存 | 文件夹变化 | 递归指纹/不缓存 | 子文件修改后 ZIP 更新 |
| BR-46 | 上传文件生命周期 | 移除条目/清空列表不删除接收目录实体文件；外部删除后标记失效 | 移除/清空/外部变更 | 仅更新列表 | 实体文件保留 |
| BR-47 | 口令存储 | 6 位数字口令使用 Keychain 独立密钥 HMAC-SHA256；单 IP + 全局限流；锁定仅内存；改口令撤销会话 | 设置/认证 | Keychain + HMAC | 状态文件无口令哈希 |
| BR-48 | 端口范围 | 用户可设 1024~65535；**自动回退仅用于默认端口 47820**（+1 至 47829）；用户手动指定端口冲突时直接失败并提示，不自动改端口；系统保留端口提示改用其他端口 | 设置/启动 | 校验 + 默认值回退 | 非法/冲突端口被拒且提示明确 |
| BR-49 | 明文告知 | 页面与设置明确「口令只控制访问，不提供传输加密」；不得宣传为加密传输 | 首次开启/设置页 | 固定提示文案 | 文案检查通过 |
| BR-50 | 网络边界声明 | 能保证的是「来源 IP 属于选定网卡前缀」，**不承诺绝对排除 VPN/桥接/网段重叠设备**；产品文案统一表述为「同一局域网网段」 | 文档/UI/发版说明 | 统一措辞 | 文案与 Spike 结论一致 |
| BR-51 | 撤销顺序 | 停止/改口令/关闭功能时按序执行：拒绝新请求 → 撤销会话 → 关闭连接 → 关闭传输 fd → 终止 ZIP → 清理临时文件；顺序不可颠倒 | 停止/设置变更/退出 | 串行化清理 | 无残留连接与临时文件 |
| BR-52 | 上传权限关闭 | `allowUpload=false` 后立即拒绝新上传，并取消所有未完成上传任务、删除其临时文件；已完成文件保留 | 关闭上传开关 | 取消 + 清理 | 无半成品残留 |
| BR-53 | 文件夹大小 | 添加文件夹时大小可为空并异步估算；UI 显示「计算中…」，不得阻塞添加操作 | 添加文件夹 | 后台估算 + 回调 | 10 万文件目录添加不卡顿 |

**网络边界声明（BR-03/BR-50 展开）**

- `网络.framework` 的 `NWListener` 只暴露「本地地址 + 端口」，不提供「请求从哪块物理网卡进入」的可靠信息。因此 MVP 能落地的校验是**来源 IP 前缀校验**（`sourceIP ∈ selectedInterface.address/prefix`）。
- 「排除 VPN/虚拟网卡」只能通过「选定网卡」间接实现：用户选定 Wi-Fi 网卡后，其前缀之外的来源被拒；但**同前缀的 VPN/桥接/网段重叠设备无法被此机制区分**。
- 若 Spike（S-12）确认 macOS 可可靠取得入站接口标识，则追加接口校验；否则按 BR-50 收敛承诺，不得在 UI 或文档中写「只有同一 Wi-Fi 能访问」。
- IPv4 与 IPv6 必须分别判定：IPv4 用掩码，IPv6 用前缀长度；IPv6 ULA（`fc00::/7`）、链路本地（`fe80::/10`）与临时地址需单独用例。

---

## 5. 详细交互设计

### 5.1 总体交互流程

```text
分享者                                                         接收者
  │                                                              │
  │ 打开面板/窗口                                                   │
  │──► 点击「开始互传」                                             │
  │      ├─ 校验目录/端口                                           │
  │      ├─ 启动监听 ──► 状态：运行中                                │
  │      └─ 生成链接 + 二维码                                        │
  │                                                              │
  │ 添加文件/文件夹/文字                                             │
  │      └─ 分享列表更新 ──► revision+1 ──► 3s 轮询（P2 SSE）──────► 页面自动刷新
  │                                                              │
  │ 扫码/发链接 ──────────────────────────────────────────────────► 打开页面
  │                                                              │
  │                                                          浏览/下载
  │◄────────────────────────────── HTTP 文件流 ────────────────────│
  │                                                              │
  │◄────────────────────────────── 上传/文字 ──────────────────────│
  │      └─ 加入列表 + revision+1（P2 SSE 广播）                    │
  │                                                              │
  │ 点击「停止互传」                                                 │
  │      ├─ 关闭监听与连接                                           │
  │      └─ 令牌失效 ──► 接收端提示「分享已结束」                      │
```

### 5.2 状态机

```text
                 ┌──────────────┐
                 │   stopped    │◄──────────────────────────────┐
                 └──────┬───────┘                               │
                        │ start()                               │ stop()/失败
                        ▼                                       │
                 ┌──────────────┐   listener ready   ┌──────────┴────────┐
                 │   starting   │───────────────────►│      running      │
                 └──────┬───────┘                    └────┬─────────┬────┘
                        │ 失败                             │         │
                        ▼                                  │         │ 网络/权限异常
                 ┌──────────────┐                          │         ▼
                 │    failed    │                          │  ┌──────────────┐
                 └──────────────┘                          │  │  restricted  │
                        │ 重试                              │  └──────┬───────┘
                        └──────────────────────────────────┘         │ 恢复
                                                                     └──► running
```

**唯一状态枚举（全文以此为准）**

```swift
enum LANShareStatus {
    case stopped      // 未监听
    case starting     // 绑定端口/校验目录
    case running      // 监听正常
    case restricted   // 监听在，但网络/权限受限
    case failed       // 启动失败
}
```

| 状态 | 含义 | 允许操作 | UI 表现 |
| --- | --- | --- | --- |
| `stopped` | 未监听 | 开始、改设置 | 灰色状态点，「开始互传」 |
| `starting` | 正在绑定端口/校验目录 | 取消 | 转圈，按钮禁用 |
| `running` | 监听正常 | 停止、复制链接、管理列表 | 绿色状态点，显示链接/二维码/连接数 |
| `restricted` | 监听在但网络/权限异常 | 重试、打开系统设置、停止 | 黄色状态点 + 原因 |
| `failed` | 启动失败 | 重试、改端口、看帮助 | 红色状态点 + 错误说明 |

> UI 只展示上述 5 种状态；`failed`/`restricted` 内部可携带更细的 `LANShareError`，但不得新增第 6 种状态文案。

### 5.3 时序图

**（1）开启服务**

```text
分享者          LANShareFeature      LANShareService      NetworkMonitor      LANShareHTTPServer
  │ 点击开始          │                    │                    │                    │
  │─────────────────►│ start()            │                    │                    │
  │                  │───────────────────►│ 校验目录/端口        │                    │
  │                  │                    │───────────────────►│ 选择局域网 IP       │
  │                  │                    │◄───────────────────│                    │
  │                  │                    │ start(port)        │                    │
  │                  │                    │───────────────────────────────────────►│
  │                  │                    │                    │                    │ NWListener.ready
  │                  │                    │◄───────────────────────────────────────│
  │                  │                    │ 生成会话令牌/链接    │                    │
  │                  │◄───────────────────│                    │                    │
  │◄─────────────────│ 状态 running        │                    │                    │
```

**（2）下载（含 Range）**

```text
浏览器                      路由层                     PathValidator           文件系统
  │ GET /api/download?...      │                          │                     │
  │───────────────────────────►│ 校验 Cookie/Host/权限/路径 │                     │
  │                            │─────────────────────────►│ 标准化 + dev/ino     │
  │                            │◄─────────────────────────│ 校验通过             │
  │                            │ open(O_NOFOLLOW) + fstat │                     │
  │                            │──────────────────────────────────────────────►│ open()
  │                            │◄──────────────────────────────────────────────│ fd
  │◄───────────────────────────│ 200/206 + Content-Range + 1MB 分块流             │
  │                            │                          │                     │
  │ 断开                        │                          │                     │
  │───────────────────────────►│ cancel + close(fd)       │                     │
```

**（3）上传与广播**

```text
浏览器                    路由层                  临时文件           LANShareStore       其他接收端
  │ POST /api/upload          │                       │                  │                  │
  │──────────────────────────►│ 校验 Cookie/CSRF/权限/空间                │                  │
  │                            │ 流式写 ──────────────►│                  │                  │
  │                            │ 清洗文件名 + 原子 move  │                  │                  │
  │                            │───────────────────────────────────────►│ add(remote)      │
  │                            │                       │                  │ revision+1       │
  │                            │◄───────────────────────────────────────│                  │
  │                            │ P2: broadcast；MVP: 对端 3s 轮询          │                  │
  │◄───────────────────────────│ 200 {item}            │                  │                  │
```

### 5.4 线程模型

```text
MainActor（UI / Feature / Service 外观）
  │ 只做状态发布与用户操作，禁止文件 IO、ZIP、socket 读写
  │
  ├─► serverQueue（串行，com.calmbar.lanshare.server）
  │     NWListener 状态、连接接入/移除、路由分发、超时扫描
  │
  ├─► connectionQueue（每连接一个串行队列，或共享并发队列 + 每连接串行状态）
  │     最小 HTTP 子集解析、multipart 流式读取、响应分块写
  │
  ├─► transferQueue（串行）
  │     LANShareTransferManager：任务登记、进度、取消、并发配额
  │
  ├─► ioQueue（并发，qos=utility，信号量上限 8）
  │     文件打开/读取/写入、原子 move、目录枚举、fstat 校验
  │
  ├─► zipQueue（串行，qos=utility，并发上限 1）
  │     ditto 打包、临时文件清理（MVP 无缓存）
  │
  └─► stateQueue（串行）
        LANShareStore / SessionManager 读写、JSON 持久化、快照发布到 MainActor
```

**约束**

- `NWListener`、`NWConnection` 的回调不触碰 UI，只投递 `Sendable` 快照到 MainActor。
- 连接表、会话表、传输任务表、ZIP 任务表分别由独立 `NSLock` 保护；锁内不做 IO。
- 上传临时文件写入使用 `FileHandle`，按 256KB~1MB 块写入，禁止整包 `Data`。
- ZIP 通过 `Process` 调 `/usr/bin/ditto`，异步等待，不占用 serverQueue。
- 所有定时器（超时扫描、临时文件清理、P2 SSE 心跳）挂在 serverQueue/zipQueue，不使用 `Timer` 阻塞主线程。
- **HTTP Server 不直接管理传输生命周期**：上传/下载都登记为 `TransferTask`，由 `TransferManager` 负责进度、取消、限流。

### 5.5 竞态清单

| # | 竞态场景 | 危害 | 对应 BR |
| --- | --- | --- | --- |
| 1 | 停止服务时有传输在途 | 野指针/写已关闭连接 | BR-01：stop 先置状态、取消连接、等待回调退出 |
| 2 | 端口变更与启动并发 | 两个 listener 抢同一端口 | BR-07/BR-48：start 与 stop 串行化，用 generation 计数丢弃旧回调 |
| 3 | 同一目录并发打包 | 重复 ZIP、磁盘翻倍 | BR-16：按「服务生命周期 generation + 条目 ID + 相对路径」合并任务（MVP 无缓存） |
| 4 | ZIP 临时文件清理时仍在下载 | 下载中断/文件不存在 | BR-15：引用计数，归零后删；MVP 响应结束后再删 |
| 5 | 同时上传同名文件 | 覆盖/竞态 | BR-19：`O_CREAT|O_EXCL` 占名 + 记录 inode + `RENAME_EXCL` 提交；`EEXIST` 则重分配 `(n)` |
| 5b | 外部（Finder）删除占位并建同名文件 | 提交时覆盖用户文件 | BR-19：提交前 `fstat` 复核 dev/ino；目标被他人占用时不覆盖，改分配 `(n)` |
| 6 | 删除条目时正在下载 | 请求半途 404 | BR-12/BR-42：已打开 fd 继续，新请求 404 |
| 7 | （P2）SSE 广播时订阅退出 | 写已关闭 socket | BR-24：快照遍历 + 写失败即移除 |
| 8 | 网络切换与地址刷新 | 链接指向旧 IP | BR-25：地址快照带 generation，旧结果丢弃；旧连接 5 秒内清理 |
| 9 | 休眠唤醒与自动恢复 | 重复启动/僵尸监听 | BR-26：恢复前校验当前状态与运行意图 |
| 10 | 口令暴力尝试 | 被枚举 | BR-06/BR-47：单 IP + 全局计数 + 锁定 |
| 11 | 磁盘写满 | 半成品/损坏文件 | BR-18/BR-20：写前检查 + 失败清理临时文件 |
| 12 | 路径解码与符号链接 | 越权读文件 | BR-09/BR-44：解码→标准化→符号链接策略→fd 级 dev/ino 复核 |
| 13 | 校验后路径被替换（TOCTOU） | 读到分享根外文件 | BR-44：`O_NOFOLLOW`/`openat` + `fstat` 比对 dev/ino |
| 14 | 下载中源文件被修改 | 新旧字节拼接损坏文件 | BR-42：按已打开 fd 读取，不跨 inode 拼接 |
| 15 | 分享目录被外部删除/移动 | 列表指向不存在路径 | BR-41：请求时 stat 校验，标记「已失效」 |
| 16 | 会话过期与并发请求 | 半途 401/重复认证 | BR-05/BR-36：滑动过期，请求开始即快照会话状态 |
| 17 | 跨站请求伪造 | 恶意网页调用本机接口 | BR-38/BR-39：Origin/Host 校验 + 自定义头 + SameSite |
| 18 | 慢速/超长请求 | 连接资源被占满 | BR-40：头/体超时 + 连接上限 |
| 19 | 多设备同时上传 | 配额争抢/磁盘写满 | BR-17/BR-43：TransferManager 统一配额与排队 |

### 5.6 生命周期与恢复

- 应用退出：`LANShareFeature.cleanup()` → 停止监听、关闭连接、清理临时文件。
- 系统休眠（P2）：`RecoveryCoordinator` 记录 `wasRunning`，停止监听释放端口；在途传输标记为「已中断」。MVP 阶段唤醒后不自动恢复，仅展示「已停止」。
- 系统唤醒（P2）：若 `wasRunning` 且功能未被用户停用，重建监听；失败只提示一次。
- 网络切换：刷新链接；旧连接不承诺存活，5 秒内清理并将任务标记为「已中断」；接收端可用新链接重新发起 Range 请求。
- 功能被用户在设置中关闭：停止服务并清除运行意图。
- 崩溃恢复：下次启动扫描 `LANShare/tmp` 与临时 ZIP，删除残留；不自动恢复服务。

---

### 5.7 HTTP 最小子集与协议边界

> 目标不是实现完整 HTTP/1.1，而是实现**满足 CalmBar 需求且行为可验证的最小子集**。任何未声明行为必须返回明确错误，禁止“尽力解析”。

| 能力 | MVP | 约束 |
| --- | --- | --- |
| 方法 | 支持 | `GET`、`HEAD`、`POST`；其他返回 405 |
| 协议版本 | 支持 | 仅 HTTP/1.1；HTTP/0.9/2.0 直接拒绝 |
| 连接复用 | 不支持 | 统一 `Connection: close`，每次请求一个连接 |
| 请求头 | 支持 | ≤ 16KB、≤ 100 个；超限 431 并断开 |
| 请求体长度 | 支持 | 见下方「Content-Length 规则」，不得对所有方法一刀切要求 |
| Chunked 请求体 | 不支持 | `Transfer-Encoding: chunked` 返回 501，不尝试解析 |
| `Expect: 100-continue` | 支持 | **两阶段**：返回 `100` 前只校验「Content-Length 合法、请求体总量 ≤ 20GB + 8MB、会话认证、上传权限、CSRF、连接/上传配额、空间预检」；**文件 Part 实际大小在上传流中校验**（≤ 20GB），超限立即中断清理。任一前置失败直接回 4xx/507 并断开，不读 body |
| multipart | 支持 | 仅 `POST /api/upload` 使用 `multipart/form-data`；单文件字段 `file`；流式解析，不落内存；boundary ≤ 70、Part ≤ 8、单 Part Header ≤ 8KB；**请求体总量上限 20GB + 8MB** |
| JSON | 支持 | 仅 `POST /api/session`、`POST /api/text`；接受 `application/json`，可选 `charset=utf-8`（大小写不敏感）；拒绝其他 charset；重复/冲突 Content-Type 一律 415；body ≤ 1MB；解析失败 400；流式解析 |
| Range | 支持 | 仅单区间；多区间统一 416 |
| Keep-Alive | 不支持 | 响应后关闭连接 |
| HTTP/2 / WebSocket | 不支持 | 明确 501，不做协议升级 |
| SSE | P2 | `text/event-stream` + 15s 心跳 |
| 超时 | 支持 | 请求头 10s、body 空闲 30s、上传总时长 24h |
| 路径 | 支持 | 仅 origin-form（`/path`）；拒绝 absolute-form 与 `*` |

**Content-Length 规则（按方法区分）**

| 请求类型 | 规则 |
| --- | --- |
| `GET` / `HEAD` | **允许缺失**；无请求体按 0 处理，缺失不返回 411 |
| `POST` | 必须提供有效 `Content-Length`；缺失返回 411 |
| 任意请求 | 出现多个 `Content-Length` 字段一律拒绝（400），禁止合并或任选其一 |
| 任意请求 | `Content-Length` 与 `Transfer-Encoding` 同时出现一律拒绝（400） |
| 任意请求 | 长度非十进制、为负、超出 `Int64`、超过接口上限时拒绝 |

> 该规则直接决定浏览器能否打开首页：接收端首页、静态资源、列表刷新、下载都是无请求体的 `GET`，不得因缺少 `Content-Length` 被拦截。

**Parser 严格拒绝规则（命中任一即拒绝，不尝试纠正）**

| 情况 | 响应 |
| --- | --- |
| 多个 `Host` 字段 | 400 |
| 重复或冲突的 `Content-Length` | 400 |
| `Transfer-Encoding` 与 `Content-Length` 并存 | 400 |
| 非法 Header 名称、裸 CR/LF、折叠（obs-fold）Header | 400 |
| `Content-Length` 超出 `Int64` 或接口上限 | 400 / 413 |
| `POST` 缺少 `Content-Length` | 411 |
| `Content-Type` 与路由不匹配（见下方矩阵） | 415 |
| multipart boundary 缺失/超长（>70 字符）、Part 数 > 8、单 Part Header > 8KB | 400 |
| 路径含非法百分号编码、双重编码结果或 NUL 字符 | 400 |
| 请求头超 16KB 或字段数超 100 | 431 |

**Content-Type 路由矩阵（不得全局只允许 multipart）**

| 路由 | 允许的 Content-Type | 请求体上限 | 解析要求 |
| --- | --- | --- | --- |
| `POST /api/session` | `application/json`（可选 `charset=utf-8`，大小写不敏感；其他 charset 415） | 1MB | 流式 JSON，字段仅 `linkToken` 或 `passcode`；解析失败 400 |
| `POST /api/text` | `application/json`（可选 `charset=utf-8`，大小写不敏感；其他 charset 415） | 1MB | 流式 JSON，字段仅 `message`；超长 413 |
| `POST /api/upload` | `multipart/form-data; boundary=...` | **文件 Part ≤ 20GB；HTTP 请求体 ≤ 20GB + 8MB** | 单文件字段 `file`；boundary ≤ 70 字符；Part ≤ 8；单 Part Header ≤ 8KB |
| 其他 `POST` | — | — | 405 |
| `GET` / `HEAD` | 不校验 | — | 忽略请求体 |

> 20GB 是**文件内容上限**，不含 boundary、Part Header 等 multipart 协议开销；请求体上限独立为 `20GB + 8MB`。禁止把 Content-Length 直接限制为 20GB。

> Parser 只做「按路由校验 Content-Type + 流式读取」；路由判定发生在读取 body 之前，避免为被拒绝的请求分配缓冲。

**URL 解码约定（避免多层重复解码）**

- Parser 只对 **Path** 做一次 RFC 3986 百分号解码，输出 `decodedPath`；Query String 单独解析，**不与 Path 混合解码**。
- Router 只接收 `decodedPath`，只做前缀匹配，**不再解码**。
- PathValidator 只接收 Router 传来的已解码相对路径，只做标准化与 fd 校验，**不再解码**。
- 解码后不得「见 `%` 即拒绝」：合法文件名如 `report%2026.pdf`（原文本身含 `%`）必须可用。仅当解码结果仍含**有效百分号编码序列**（如 `%2e`、`%2f`、`%5c`、`%00`）时视为双重编码并拒绝 400。
- 无论是否双重编码，解码结果中出现 NUL、`..` 段、反斜杠或连续斜杠时一律 400/403。

**Parser 实现约束**

- 解析器为纯状态机，不依赖 `NWConnection`，可独立单元测试。
- 必须覆盖：半包、粘包、超长头、重复 Content-Length、非法十六进制 Range、multipart boundary 缺失/超长、客户端中途断开、无 Content-Length 的 GET、多个 Host。
- 模糊测试为**语料驱动 + 定向变异**，随机字节流 10 万次仅为最低执行量：
  1. 以合法请求（GET/HEAD/POST、JSON、multipart、Range）为种子语料；
  2. 定向变异：Content-Length、Host、重复 Header、CRLF/裸 LF、boundary、`%` 编码；
  3. 分片变异：将 multipart boundary、Header 结束符、Body 任意位置切到 TCP 分片边界；
  4. 中断变异：Body 中途断连、半包后不再发送；
  5. A 与 D 使用**同一批输入做差分比对**（解析结果、拒绝码逐条一致）；
  6. C 实现（llhttp）必须在 AddressSanitizer 下跑完语料，零越界/零 UAF；
  7. 覆盖率以「请求行/Header/Body/分片/multipart 状态」分支覆盖统计，不以执行次数为充分性证明。
- 未识别字段忽略并记录计数；安全相关字段（Host/Origin/Content-Length/Transfer-Encoding）异常时直接拒绝。

**Parser 统一事件契约（主方案 A 与备选方案 D 共用）**

无论最终采用自研实现还是 vendored llhttp，HTTP Server 只依赖以下事件接口，不直接依赖具体解析器：

| 事件 | 载荷 | 说明 |
| --- | --- | --- |
| `onRequestLine` | `HTTPRequestLine` | 保留原始请求目标，见下 |
| `onHeadersComplete` | `HTTPHeaders`（**保序多值**） | 头限制：≤16KB、字段 ≤100 |
| `onBody` | `UnsafeRawBufferPointer` + length（仅回调期内有效） | 原始 HTTP Body 片段，**不做业务格式解析** |
| `onMessageComplete` | — | 触发路由收尾与响应 |
| `onError` | status / reason | 400/411/413/415/431/501 |

```swift
struct HTTPHeader { let name: String; let value: String }   // 保留顺序与重复
typealias HTTPHeaders = [HTTPHeader]                        // 禁止 [String: String]

struct HTTPRequestLine {
    let method: String
    let rawTarget: String      // 原始 request-target（仅 origin-form）
    let rawPath: String        // 未解码
    let rawQuery: String?      // 未解码，单独解析，不与 Path 混合
    let decodedPath: String    // 单次解码结果，Router 直接使用
    let version: String
}
```

- Header 名比较大小写不敏感；**Adapter 不得静默合并重复字段**；`Host`/`Content-Length`/`Transfer-Encoding`/`Content-Type` 的重复与冲突由统一策略在 `onHeadersComplete` 后判定，判定前不得丢弃原始值。
- 仅接受 `origin-form` 请求目标；`absolute-form`/`authority-form`/`*` 一律 400。

**Body 分层：HTTP Body ≠ 文件内容**

```
HTTP Parser ──onBody(raw)──► Body Consumer（按路由选择） ──► 业务写入
                                ├── multipart/form-data → 流式 Multipart Parser → 仅文件 Part 内容写临时文件 fd
                                └── application/json     → JSON Body Consumer（≤1MB 受控缓冲/流式解析）
```

- `onBody` 交付的是**未经业务格式解析**的 HTTP Body 字节；**禁止**把原始 multipart Body 直接写入目标文件（会混入 boundary/Part Header）。
- 仅 Multipart Parser 提取出的文件 Part 内容可写入 `.calmbar-tmp/` 临时文件。
- JSON 仅允许在 1MB 上限内受控缓冲或流式解析；禁止为 20GB 上传分配整包内存。

**回调内存所有权与背压**

- `onBody` 指针**只在本次回调内有效**，禁止跨回调保存 C 指针；异步落盘必须先复制到有上限的缓冲区。
- `NWConnection.receive(maximumLength:)` 固定 ≤ **64KB**；Parser 单次输入块 ≤ 64KB；`onBody` 单次交付 ≤ 64KB（三者同口径）。
- 单连接缓冲高水位 1MB / 低水位 256KB：达高水位**暂停后续 `receive`**（不再提交新读取），但已交给 Parser 的当前输入块必须处理完毕；判断水位时须计入正在处理的输入块，不能只在回调结束后检查。
- 全局在途 Body 缓冲 ≤ 32MB；超限时暂停最慢连接。
- 恢复条件：缓冲降至低水位以下才重新提交 `receive`；恢复不得重放已消费数据。
- 单次回调上限 64KB **不等于**总缓冲上限，两者独立计量。
- 连接取消/超时/错误时必须释放未完成缓冲、关闭 fd、删除临时文件。

**实现路线与决策点**

| 路线 | 说明 | 状态 |
| --- | --- | --- |
| A. 自研最小 Parser | 零第三方代码，按本节规则实现纯状态机 | **默认方案**，主 PRD 架构不变 |
| D. NWConnection + llhttp | vendored C 解析器（`llhttp_execute` + `on_body`/`on_message_complete` 回调），传输层不变 | **由 S-14 并行验证**，通过后由评审决定是否替换 A |
| C. SwiftNIO + NIOHTTP1 | 替换传输层，引入 SPM 依赖 | 暂不采用 |
| B. NWConnection + PicoHTTPParser | 仅头部解析；`phr_decode_chunked()` 需应用层自行驱动，消息生命周期仍需自管 | 不作为长期方案 |

> S-14 报告必须包含 7 个维度：正确性（合法请求解析一致）、安全性（畸形/走私类拒绝一致）、内存（空闲基线、峰值 RSS、缓冲峰值）、性能（20GB 吞吐、CPU）、稳定性（长传/断开/取消）、维护成本（Swift-C 桥接代码量、许可证与升级责任）、缺陷（数量与严重度）。不得仅以「llhttp 能跑通」作为结论。

---

## 6. UI 设计规范

### 6.1 入口与信息架构

| 入口 | 位置 | 行为 |
| --- | --- | --- |
| 菜单栏面板 | 「工具」分区新增一个入口卡片/行 | **只展示状态与入口**，点击打开独立窗口；不在面板内放列表或配置 |
| 独立窗口 | 日常操作唯一主界面 | 开始/停止、链接与二维码、分享列表管理、基础访问设置 |
| 设置页 | 新增 `SettingsTab.lanShare`，分类 `.productivity` | **只放高级配置**（端口、接收目录、口令、权限说明、故障排查），不重复展示分享列表 |
| 命令面板 | `FeatureCommand` + 命令描述 | 「开启局域网互传」「停止局域网互传」「复制互传链接」 |
| 菜单栏图标 | 不新增状态项 | 仅在工具入口显示运行状态点，避免占用菜单栏 |

> 设计理由：面板宽度固定 320pt、视口高度 200~360pt，列表 + 二维码 + 设置会严重挤压其他分区；独立窗口更符合 APP-04 与现有「清理/剪贴板/音频」的窗口模式。

### 6.2 面板入口线框（工具分区）

```text
┌──────────────────────────────────────┐
│ 工具                                  │
│ ┌──────────────────────────────────┐ │
│ │ ⇄  局域网互传            ● 运行中 │ │
│ │    手机/电脑浏览器直接收发文件      │ │
│ │                        [打开]     │ │
│ └──────────────────────────────────┘ │
│ ┌────────┐ ┌────────┐ ┌────────┐     │
│ │ 截屏识字│ │ 屏幕录制│ │ 更多…  │     │
│ └────────┘ └────────┘ └────────┘     │
└──────────────────────────────────────┘
```

- 状态点：灰=已停止、绿=运行中、黄=受限、红=失败。
- 未运行时整行可点击直接开启（带二次确认），运行中点击打开窗口。

### 6.3 独立窗口线框（720×560，可缩放，最小 640×480）

```text
┌────────────────────────────────────────────────────────────────────┐
│ 局域网互传                                              [−][□][×] │
├───────────────────────────────┬────────────────────────────────────┤
│ 分享内容                       │ 连接                               │
│ ┌───────────────────────────┐ │ ┌────────────────────────────────┐ │
│ │ ⇄ 拖入文件或文件夹          │ │ │  ● 运行中   http://192.168.1.8:47820 │ │
│ │   或点击添加               │ │ │  [复制链接]  [停止互传]          │ │
│ └───────────────────────────┘ │ │                                │ │
│ ┌───────────────────────────┐ │ │        ██  ██  ██  ██            │ │
│ │ 📄 设计稿.fig      12.4 MB │ │ │        ██  二维码  ██            │ │
│ │ 📁 交付物          1.2 GB  │ │ │        ██  ██  ██  ██            │ │
│ │ 📝 一段文字        刚刚     │ │ │                                │ │
│ └───────────────────────────┘ │ │  已连接 2 台设备 · 传输 1 个       │ │
│ [添加文件] [添加文件夹] [文字]   │ └────────────────────────────────┘ │
│                               │                                    │
│ 访问设置                       │ 提示                                │
│ 接收文件夹  ~/Downloads/CalmBar 互传 [选择] │ · 手机与电脑需在同一局域网          │
│ 端口        47820（高级）       │ · 首次开启可能触发系统防火墙提示      │
│ [x] 允许对方上传文件与文字       │ · 停止后链接立即失效                 │
│ [ ] 访问口令（6 位）            │ · 口令仅控访问，不加密传输           │
└───────────────────────────────┴────────────────────────────────────┘
```

**窗口状态**

| 状态 | 左栏 | 右栏 |
| --- | --- | --- |
| `stopped`（已停止） | 列表可编辑 | 灰色占位 + 「开始互传」大按钮 + 上次链接（失效标记） |
| `starting`（启动中） | 列表可编辑 | 骨架屏/转圈，按钮禁用 |
| `running`（运行中） | 列表可编辑 | 链接、二维码、连接数、停止按钮 |
| `restricted`（受限） | 列表只读 | 黄色提示条 + 「打开系统设置」 |
| `failed`（失败） | 列表可编辑 | 红色错误卡 + 重试/换端口 |

> 「已连接 N 台设备」取活动会话数（UI 文案为「约 N 台设备（N 个会话）」），不取 TCP 连接数（见 A-3 定义）；传输中可点开基础任务列表查看进度与取消。

### 6.4 接收端页面（Web）

**桌面端（≥ 720px）**

```text
┌──────────────────────────────────────────────────────────────────┐
│  CalmBar 互传                        分享者：Jack 的 MacBook      │
│  ──────────────────────────────────────────────────────────────  │
│  ┌──────────────────────────────┐  ┌───────────────────────────┐ │
│  │ 拖拽文件到这里，或点击选择      │  │ 发一段文字                 │ │
│  │        [选择文件]             │  │ ┌───────────────────────┐ │ │
│  └──────────────────────────────┘  │ │                       │ │ │
│                                    │ └───────────────────────┘ │ │
│  分享内容                           │ [发送]                    │ │
│  📄 设计稿.fig          12.4 MB  ↓ │                           │ │
│  📁 交付物              1.2 GB   ↓ │                           │ │
│  📝 一段文字             复制       │                           │ │
└──────────────────────────────────────────────────────────────────┘
```

**移动端（< 720px）**

```text
┌─────────────────────────┐
│ CalmBar 互传             │
│ 分享者：Jack 的 MacBook   │
├─────────────────────────┤
│ ┌─────────────────────┐ │
│ │  点击选择要发送的文件  │ │
│ └─────────────────────┘ │
│ 分享内容                 │
│ 📄 设计稿.fig     ↓      │
│ 📁 交付物         ↓      │
│ 📝 一段文字       复制    │
├─────────────────────────┤
│ [发送文字]               │
└─────────────────────────┘
```

**页面规则**

- 页面加载顺序固定为：`GET /api/bootstrap`（公开）→ 按 `authMode` 认证 → `GET /api/state`（需 Cookie）→ `GET /api/items`。未认证前不请求任何需要 Cookie 的接口。
- 单页、无外部 CDN、无框架；HTML+CSS+JS 合计 ≤ 60KB（未压缩）。
- 跟随系统浅色/深色；主色使用中性黑灰，强调色仅用于下载/上传按钮。
- 触控目标 ≥ 44×44pt；列表行高 ≥ 52pt。
- 中文/英文按 `navigator.language` 自动选择；文案不使用技术术语。
- 禁用自动播放、自动下载、外部跳转。
- 服务停止后页面显示「分享已结束」并禁用所有操作。

### 6.5 组件、状态与文案

| 组件 | 状态 | 文案规范 |
| --- | --- | --- |
| 主开关 | 已停止/启动中/运行中/受限/失败 | 「开始互传」「正在开启…」「运行中」「被系统阻止」「开启失败」 |
| 链接框 | 可复制/不可用 | 不展示完整 token；仅展示域名与端口，复制时才写入完整链接 |
| 二维码 | 加载/可用/不可用 | 「扫码在手机上打开」 |
| 分享条目 | 文件/文件夹/文字/远程上传 | 远程条目加「来自 <IP 尾号>」 |
| 进度 | 上传/下载/打包 | 「正在打包…」「剩余 2 分钟」不显示虚假精确值 |
| 错误 | 端口/权限/磁盘/路径 | 原因 + 下一步按钮，禁止只给错误码 |

### 6.6 视觉令牌与尺寸

| 项目 | 规范 |
| --- | --- |
| 面板入口高度 | 56pt（与工具卡片一致） |
| 独立窗口 | 720×560pt，最小 640×480pt |
| 圆角 | 窗口内卡片 12pt，按钮 8pt |
| 间距 | 8 / 12 / 16 / 24 四档 |
| 字体 | 系统字体；标题 15pt Semibold，正文 13pt Regular，辅助 11pt |
| 颜色 | 复用 `PopoverPalette` 的中性色与强调色；状态色仅用于状态点 |
| 二维码尺寸 | 窗口内 140×140pt，面板内不展示（空间不足） |

---

## 7. 非功能需求

### 7.1 性能

| 场景 | 指标 | 备注 |
| --- | --- | --- |
| 服务启动 | ≤ 500ms | 端口可用、目录可读、权限已授予 |
| 页面首屏 | ≤ 300ms | 同一局域网、静态资源从内存/包内读取 |
| 小文件下载（<10MB） | ≤ 200ms 首字节 | 不含浏览器渲染 |
| 大文件下载（20GB） | ≥ 80MB/s（有线） | 单连接，SSD，SHA-256 一致 |
| Wi-Fi 下载（20GB） | ≥ 30MB/s | 5GHz，干扰可控 |
| 上传（20GB） | ≥ 50MB/s（有线） | 流式写盘，SHA-256 一致 |
| 文件夹打包 | 10 万文件 / 1GB ≤ 60s | SSD，ditto level 默认 |
| 内存（下载） | 增量 ≤ 40MB | 20GB 下载；`phys_footprint` 峰值 − 空闲基线，排除页缓存 |
| 内存（上传） | 增量 ≤ 64MB | 20GB 上传；含 Body 缓冲；A/D 同一口径 |
| 并发 | 8 下载 + 4 上传 | 超出排队或 429 |
| 列表刷新 | MVP ≤ 3s；P2 SSE ≤ 500ms | 页面可见时 |
| SSE（P2） | 独立配额 32（计入全局 64） | 超出拒绝新订阅 |

### 7.2 兼容性

| 维度 | 要求 |
| --- | --- |
| macOS | 14.0+（Sonoma），Apple Silicon 与 Intel 通用二进制 |
| 浏览器 | Safari iOS 15+、Safari macOS 15+、Chrome/Edge 90+、Firefox 90+ |
| 网络 | IPv4 必选；IPv6 可选（链路本地/ULA），公网地址不作为分享地址 |
| IPv6 URL | 方括号格式 `http://[fe80::1%25en0]:47820/`；Host 校验接受 `[...]`；链路本地必须带 zone ID（`%25` 编码）；ULA 优先于链路本地；系统无 IPv6 时只展示 IPv4 |
| 文件系统 | APFS/HFS+；支持中文、emoji、超长文件名（≤ 255 字节） |
| 权限 | 本地网络（macOS 15+）、入站连接（应用防火墙） |
| 签名 | 自签名/Ad-hoc；升级后防火墙可能再次询问，需在发版说明中提示 |

### 7.3 安全与隐私

**威胁模型**

| 威胁 | 场景 | 缓解 |
| --- | --- | --- |
| 同局域网未授权访问 | 公共局域网、宿舍或办公网络 | 链接令牌（256-bit）+ 可选口令 + **选定网卡前缀**来源限制 |
| 同前缀的 VPN/桥接设备 | 网段重叠或 VPN 使用与局域网相同前缀 | 能做的只有前缀校验；按 BR-03/BR-50 收敛承诺，Spike S-12 验证能否拿到入站接口 |
| 无口令模式被绕过 | 直接请求 `/api/session` 领取凭证 | 无口令时必须提交正确 linkToken；缺少/错误一律 401，绝不无条件签发 |
| 令牌泄露 | 链接被转发到群聊或留在 URL 中 | 令牌放 URL Fragment，不进服务端日志/Referer；换取 HttpOnly Cookie 后清除地址栏 |
| 路径穿越 | 构造 `../` 读取任意文件 | 解码→标准化→符号链接策略→fd 级 dev/ino 校验 |
| 符号链接逃逸 / TOCTOU | 分享目录内软链被并发替换 | 允许策略默认关闭；`O_NOFOLLOW`/`openat` + `fstat` 复核 |
| 恶意上传 | 超大文件、非法文件名、可执行文件 | 20GB/空间限制、文件名清洗、不自动执行、不返回绝对路径 |
| 暴力破解 | 枚举 6 位口令 | Keychain 密钥 HMAC + 单 IP/全局限流 + 60 秒锁定 |
| 跨站请求 / DNS Rebinding | 恶意网页调用本机接口 | Host/Origin/Referer 校验 + `X-CalmBar-Client` + SameSite=Strict |
| 慢速连接占满 | 恶意客户端只发半个请求 | 请求头 10s、请求体空闲 30s、连接上限 |
| 信息泄露 | 错误页暴露堆栈/绝对路径 | 统一错误响应，日志脱敏 |
| 明文传输 | 同局域网抓包 | 明确告知「口令只控访问，不提供传输加密」；不承诺机密传输 |

**硬性规则**

- BR-28：所有响应加 `X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`；API `Cache-Control: no-store`；页面 CSP `default-src 'self'`。
- BR-29：令牌/口令恒定时间比较；UI 只显示前 4 位；日志不含完整凭证。
- BR-31：接收端只有「列表/下载/上传/文字/事件」五类接口，无删除、重命名、执行、打开路径能力。
- BR-36：会话只存 HttpOnly Cookie；禁止 localStorage/sessionStorage 保存长期凭证。
- BR-37：下载 URL 不含长期 token；Cookie 为默认认证方式，P2 才提供单次短时 ticket。
- BR-38/BR-39：Host、Origin、Referer、自定义头四重校验，防止 DNS Rebinding 与 CSRF。
- BR-44：路径校验必须落到 fd 级 dev/ino，不依赖字符串前缀。
- BR-05：会话 TTL 与 Cookie `Max-Age` 同步滑动；BR-50：网络边界只承诺「来源属于选定网卡前缀」。
- 不记录文件内容；访问日志最多保留 7 天且仅本机可读。

### 7.4 可靠性

- 端口：默认 47820 占用时自动尝试 47821~47829；用户手动指定端口冲突时直接失败，不自动修改端口。
- 监听失败、连接异常、写失败均不崩溃；单连接错误不影响其他连接。
- 上传中断不产生半成品；ZIP 失败不影响已存在文件。
- 网络切换 3 秒内刷新地址；**旧连接不承诺存活**，5 秒内清理并标记「已中断」。
- 休眠唤醒自动恢复（P2）最多重试 1 次；失败提示一次。MVP 唤醒后不自动恢复，仅提示重新开启。
- 状态文件原子写入，损坏时备份并回退空列表。
- 服务停止后 1 秒内释放端口，允许立即重启。

### 7.5 技术验证清单（排期前必须完成 Spike）

| # | Spike | 验证内容 | 通过标准 | 产物 |
| --- | --- | --- | --- | --- |
| S-01 | 局域网监听 | `NWListener` 绑定 `.any` 是否触发本地网络权限/防火墙；`Info.plist` 键是否生效 | 手机可访问；拒绝时有可识别状态 | `app/Sources/CalmBar/UI/Spike/` + `/tmp/calmbar_lanshare/` 日志与截图 |
| S-02 | 大文件流式下载 | 20GB 文件单 Range 下载、内存曲线、SHA-256 | 内存增量 ≤ 40MB，吞吐达标，校验一致 | 日志 + Instruments 截图 |
| S-03 | 流式 multipart 上传 | 20GB 上传、断线、磁盘不足 | 无整包缓冲，断线无残留，校验一致 | 日志 + 目录快照 |
| S-04 | 最小 HTTP 子集 | 无 Content-Length 的 GET/HEAD、POST 缺长度、重复 Content-Length、多 Host、裸 CRLF、折叠头、超长头、Chunked、Expect、慢速、半包、粘包 | 全部按约定拒绝或超时，不误解析；浏览器首页可正常打开 | 单元测试 + 模糊测试报告 |
| S-05 | 认证与 Cookie | 无口令缺 token、错误口令、`/api/bootstrap` 初始化、Cookie 属性、30 分钟滑动刷新、跨站请求、DNS Rebinding | 未授权全部 401/403；Cookie 不可被 JS 读取；持续操作不被要求重登 | 抓包/日志 |
| S-06 | 端口冲突与回退 | 占用 47820 后启动 | 自动使用 47821 并展示 | 日志 |
| S-07a | 网络切换（**P1 必须通过**） | Wi-Fi 切换、IP 变化 | 3 秒内刷新链接；旧连接 5 秒内清理并标记「已中断」；新设备可访问 | 日志 + 截图 |
| S-07b | 休眠唤醒可行性（**P2 仅验证可行性**） | 合盖/唤醒后能否重建监听、端口可否复用 | 记录能否自动恢复及失败原因；**不作为 P0/P1 交付门槛** | 日志 |
| S-08 | 自签名防火墙复现 | 重新构建后是否再次弹窗 | 结论写入发版说明 | 截图 |
| S-09 | 路径穿越与 TOCTOU | `../`、`%2e%2e`、符号链接、并发替换 | 全部 403，fd 校验生效 | 测试用例 |
| S-10 | ditto 打包 10 万文件目录 | 耗时、内存、取消 | 可取消，无残留 | 日志 |
| S-11 | 传输任务与进度 | 多设备同时上传/下载、取消、限速 | 进度与字节一致，取消即释放 | 日志 + 截图 |
| S-12 | 来源网段边界 | 同前缀/跨前缀/VPN 同前缀/桥接/回环；IPv4 掩码、IPv6 ULA、IPv6 链路本地；能否取得入站接口标识 | 前缀校验行为符合 BR-03；无论能否取到入站接口，结论写入 BR-50 承诺边界 | 抓包/日志 |
| S-13 | 上传同卷临时文件 | 接收目录在外接盘时 `.calmbar-tmp/` 与目标是否同卷、`rename` 是否原子、ENOSPC 清理 | 外接盘上传成功且无跨卷失败；异常退出无残留 | 日志 + 目录快照 |
| S-14 | Parser 路线对比（A 自研 vs D llhttp） | 保留 `NWListener`+`NWConnection`，新增 `HTTPParserAdapter` 封装 llhttp；任意 `receive` 片段直接喂入；与 S-04 共用同一语料。**协议预期必须逐项断言**：Content-Length→正常；Chunked→501 并关闭，**不得进入 Body Consumer**（llhttp 能解析不等于产品支持）；CL+TE→400；Keep-Alive→响应后关闭；Expect→前置校验通过才 100，非法 Expect 拒绝；**背压验证**：达到高水位暂停后剩余输入不丢失，恢复时从断点继续消费 | 两路线同语料解析结果与拒绝码逐条一致；20GB 上传内存口径见 7.1（A/D 同一标准）；llhttp 在 ASan 下零越界；报告覆盖正确性/安全性/内存/性能/稳定性/维护成本/缺陷 7 个维度 | 对比报告 + 差分结果 + ASan 日志 + 内存采样 |

> Spike 代码按项目约定放在 `UI/Spike`，通过 `--spike lanshare` 启动，验收后删除，不进入主线。

---

## 8. 易用性设计原则

### 8.1 零配置快速开始

- 首次使用默认值即可用：端口 47820、接收目录 `~/Downloads/CalmBar 互传`、允许上传开、口令关。
- 用户只需两步：点「开始互传」→ 把二维码给对方。
- 不要求用户理解 IP、端口、协议、网卡；这些只在「高级」里出现。

### 8.2 用户可见配置 ≤ 4 项

| # | 配置 | 默认值 | 说明 |
| --- | --- | --- | --- |
| 1 | 接收文件夹 | `~/Downloads/CalmBar 互传` | 对方上传的文件落点 |
| 2 | 允许对方上传文件与文字 | 开 | 关闭后对方只能下载 |
| 3 | 访问口令 | 关 | 开启后显示 6 位数字，可刷新 |
| 4 | 端口（高级） | 47820 | 仅在冲突时修改 |

> 「自动启动」「IP 协议」「网卡选择」不作为用户配置：自动恢复由运行意图决定；网卡自动选择并在链接区提供「换一个网络」入口。

### 8.3 全链路无主动打扰

- 不主动弹出系统通知；连接数在窗口内展示。
- 不自动打开窗口；只有用户点击入口才打开。
- 错误只在其发生的界面内提示，30 秒内相同错误合并。
- 服务停止不弹窗，除非有正在进行的传输（需确认）。

### 8.4 小白语言规范

| 禁止出现（面向用户） | 替换为 |
| --- | --- |
| HTTP 服务 / 监听端口 | 互传服务 / 端口（高级） |
| 令牌 / Token | 访问链接（不要提 token） |
| SSE / WebSocket | 自动刷新 |
| multipart / Range | 大文件续传（部分浏览器/下载工具支持） |
| 符号链接 / canonicalize | 不在界面出现 |
| 403 / 500 / 507 | 「没有权限」「服务出错了」「磁盘空间不足」 |
| 私有网段 / RFC1918 / 网段前缀 | 「仅允许与所选网络同一网段的设备访问」 |
| 加密 / HTTPS | 「口令只控制谁能访问，不加密传输内容」 |

> 只有「高级设置」内部可以保留端口等术语，并附一句人话解释。

### 8.5 状态表达简化

- 只保留 5 种状态：已停止、启动中、运行中、受限、失败（对应 `LANShareStatus`）。
- 状态旁永远有一句「现在能做什么」：例如「运行中 · 让对方扫码即可」。
- 错误状态给一个主按钮，不同时给 3 个以上选择。

### 8.6 一致性检查表

| 检查项 | 要求 | 本文档落点 |
| --- | --- | --- |
| 面板尺寸 | 不改变 320×520，不新增分区 | 6.1、6.2 |
| 功能注册 | 走 `FeatureID` / `FeatureManager` | 2.5、9.2 |
| 权限 | `Info.plist` + `PermissionManager` | 7.2、9.2 |
| 恢复 | `RecoveryAction` + `RecoveryCoordinator` | 5.6、9.2 |
| 零依赖 | 仅系统框架与 `/usr/bin/ditto` | 2.6 |
| 文案 | 中文、无技术术语 | 8.4 |
| 错误 | 不静默失败 | BR-35、UC-10 |
| 测试 | 纯逻辑有 XCTest | 9.3 |
| 会话 | 服务端 TTL 与 Cookie `Max-Age` 同步滑动 | BR-05、UC-06 |
| 网络边界 | 只承诺「来源属于选定网卡前缀」 | BR-03、BR-50、7.3 |
| 传输计数 | 展示会话数，不展示 TCP 连接数 | A-3、6.3 |
| 上传落盘 | 临时目录与接收目录同卷 | BR-18、BR-19、S-13 |
| Content-Type | 按路由校验：JSON 仅 session/text，multipart 仅 upload | 5.7、A-31 |
| 分期边界 | 网络切换属 P1，休眠自动恢复属 P2 | 9.1、A-13/A-14 |
| 状态一致性 | 全文只使用 5 种状态 | 5.2、6.3、6.5、8.5 |
| 业务规则 | BR 以 4.12 为唯一权威定义 | 4.12 |
| 协议边界 | 只实现 5.7 声明的最小 HTTP 子集 | 5.7 |
| 认证 | 会话凭证只走 HttpOnly Cookie，URL 不含长期凭证 | BR-36、BR-37、UC-06 |
| 端口 | 统一 1024~65535，回退仅 47820~47829 | BR-48、UC-08、A-2 |

---

## 9. 实施与验收

### 9.1 分期

| 阶段 | 内容 | 退出条件 |
| --- | --- | --- |
| **P0 技术 Spike** | S-01~S-14：局域网监听、手机访问、最小 HTTP 子集、20GB 流式下载/上传、Range、认证与 Cookie、路径/TOCTOU、来源网段、10 万文件打包、同卷临时文件、Parser 路线对比（A vs llhttp） | 真实设备验证通过并归档日志；**S-07a 必须通过，S-07b 仅记录可行性、不作交付门槛**；S-14 产出对比报告后方可锁定 Parser 路线；任一核心项不通过则回到方案评审 |
| **P1 MVP（2.7.0）** | 开启/停止、链接与二维码、文件/文件夹分享、浏览器下载/上传、文字、基础会话认证、基础错误处理、独立窗口、设置页高级项、命令、基础传输任务 | 第 9.3 节 A-01~A-36 全绿（A-14 归 P2）；iPhone/Windows/Android 三类设备完成双向传输 |
| **P2 体验增强** | SSE 实时刷新、ZIP 指纹缓存、休眠唤醒自动恢复、**自动选择其他网卡/自动恢复监听**、高级网卡选择、传输速度/剩余时间/历史记录、Bonjour 发现、下载 ticket、上传续传 | 基础传输稳定后按反馈排期 |

> 分期口径：「网络变化后刷新分享地址、清理失效连接」属 **P1**；「自动切换到另一张网卡、自动恢复监听」属 **P2**，两者不得混称「网络自动切换」。

> 传输进度的分级：**P1 提供基础任务视图**（文件名、方向、已传输字节、成功/失败、取消）；**P2 才做**实时速度、剩余时间预估、历史记录与复杂任务管理。

> MVP 明确**不包含**：SSE、ZIP 缓存、自动网络恢复、Bonjour、传输历史、上传续传。避免首版承担过多底层复杂度。

### 9.2 代码落点清单

| 文件/目录 | 改动 |
| --- | --- |
| `app/Sources/CalmBar/Features/FeatureID.swift` | 新增 `case lanShare` 与 `displayName = "局域网互传"` |
| `app/Sources/CalmBar/Features/LANShareFeature.swift` | 新增 Feature，`category = .productivity` |
| `app/Sources/CalmBar/Features/FeatureManager.swift` | `register(LANShareFeature())` |
| `app/Sources/CalmBar/Services/LANShare/` | 新增 Service、HTTP Server、最小 HTTP Parser（或 S-14 结论确定后的 `HTTPParserAdapter` + vendored llhttp）、SessionManager、TransferManager、PathValidator、Store、NetworkMonitor、Zipper |
| `app/Sources/CalmBar/UI/LANShare/` | 独立窗口、分享列表、基础访问设置、传输任务/进度、二维码视图 |
| `app/Sources/CalmBar/UI/Popover/`（工具分区） | 新增入口行，不改分区高度 |
| `app/Sources/CalmBar/UI/Settings/` | 新增设置分类（`SettingsCategory`）与 detail 分支、搜索关键词 |
| `app/Sources/CalmBar/Commands/CommandCenter.swift` | 注册 3 条命令与中文别名 |
| `app/Sources/CalmBar/Core/PermissionManager.swift` | 新增 `.localNetwork` 类型与说明 |
| `app/Sources/CalmBar/Recovery/RecoveryAction.swift` | 新增 `stopLANShareServer` |
| `app/Resources/Info.plist` | `NSLocalNetworkUsageDescription`；如启用 Bonjour 再加 `NSBonjourServices` |
| `app/Resources/LANShareWeb/` | 接收端页面资源 |
| `app/build_app.sh` | 确认资源目录被打入 App Bundle |
| `app/Tests/CalmBarTests/LANShareTests.swift` | 最小 HTTP 子集（含 GET 无 Content-Length、POST 缺长度 411、重复 Content-Length 400）、multipart、Range、文件名、认证/Cookie 滑动、`/api/bootstrap` 免认证、路径与 TOCTOU、端口回退、传输任务；含 Parser 模糊测试 |
| `README.md`、`doc/release/RELEASE.md` | 用户可见说明与发版记录 |

### 9.3 验收用例

| # | 场景 | 步骤 | 预期 |
| --- | --- | --- | --- |
| A-01 | 首次开启 | 权限已授予后点击开始 | 500ms 内运行中，显示链接/二维码 |
| A-02 | 手机扫码 | iPhone Safari 扫码 | 3 秒内看到分享列表 |
| A-03 | 下载 20GB | 20GB 文件下载并校验 | 吞吐达标，内存 ≤ 40MB，SHA-256 一致 |
| A-04 | Range 协议验收 | 用 `curl -r` 或专用下载客户端发起单 Range | 206 + `Content-Range` + `ETag` 正确，最终字节完整；多 Range 416 |
| A-04b | 浏览器续传行为 | 分别在 Safari、Chrome 中中断并重试下载 | 记录是否自动续传；不支持时验收通过但**不得宣传「浏览器自动断点续传」** |
| A-05 | 文件夹下载 | 1GB/10 万文件目录 | ZIP 可解压，临时文件按 BR-15 清理 |
| A-06 | 大文件上传 | 20GB 上传；另测手机 500MB 视频 | 双方列表出现，SHA-256 一致，文件名正确 |
| A-07 | 同名上传 | 连续上传同名文件 3 次 | 生成 ` (1)(2)`，无覆盖 |
| A-08 | 文字互传 | 发送 100,000 / 100,001 字符 | 前者成功，后者 400 |
| A-09 | 列表刷新 | A 上传，B 停留在列表页 | B 3 秒内看到新条目（MVP 轮询） |
| A-10 | 口令 | 开启口令，错误 10 次 | 统一提示，锁定 60 秒，正确口令可进 |
| A-11 | 路径穿越 | `../`、`%2e%2e`、符号链接、并发替换 | 全部 403，源文件不可读 |
| A-12 | 端口冲突 | 先占用 47820 | 自动使用 47821 并展示 |
| A-13 | 网络切换（P1） | Wi-Fi A → B | 3 秒内链接刷新；旧连接 5 秒内明确失败并标记「已中断」；**不要求自动恢复** |
| A-14 | 休眠唤醒（P2） | 传输中合盖 30 秒再打开 | 自动恢复 1 次，链接可用，旧传输明确失败 |
| A-15 | 停止服务 | 传输中点击停止 | 二次确认，连接终止，会话 Cookie 立即失效 |
| A-16 | 磁盘不足 | 填满磁盘后上传 | 507，临时文件清理，无半成品 |
| A-17 | 权限拒绝 | 拒绝本地网络/防火墙 | 状态 `restricted`，可打开系统设置 |
| A-18 | 退出清理 | 退出 CalmBar | 端口释放，临时文件清理，下次启动无残留 |
| A-19 | 无局域网 | 关闭 Wi-Fi 后开启 | 提示「未连接到局域网」，不崩溃 |
| A-20 | 深色模式 | 系统切换深色 | 窗口与 Web 页面均正确适配 |
| A-21 | 无口令认证绕过 | 不带 linkToken 直接 `POST /api/session` | 401，不返回任何会话或列表 |
| A-22 | 跨站/Host 伪造 | 伪造 Origin、Host、缺少 `X-CalmBar-Client` | 全部 403；正常同源请求通过 |
| A-23 | 跨网段访问 | 从不同前缀网段/VPN 地址访问 | 403，无法建立会话 |
| A-24 | 多设备并发 | 3 台设备同时下载 + 2 台上传 | 不互相阻塞，配额生效，进度准确 |
| A-25 | 未认证初始化 | 清空 Cookie 打开首页与口令页 | `/api/bootstrap` 返回公开信息；页面能正常显示口令框；`/api/state` 未认证时 401 |
| A-26 | GET 无 Content-Length | 浏览器直接 GET `/`、`/api/items`（不带 Content-Length） | 正常 200，不返回 411 |
| A-27 | Cookie 滑动续期 | 每 10 分钟操作一次，持续 60 分钟 | 全程不掉线；Cookie `Max-Age` 随响应刷新 |
| A-28 | 上传同卷与 ENOSPC | 接收目录设为外接盘，上传大文件；再模拟磁盘写满 | 同一卷原子落盘成功；ENOSPC 返回 507 且无临时文件残留 |
| A-29 | 会话数展示 | 同一浏览器开 3 个标签页 + 另一台设备 | 显示 2 台设备（2 个会话），TCP 连接数不参与展示 |
| A-30 | 同名并发上传 | 两台设备同时上传同名文件 | 产生两个完整文件（`a.txt`、`a (1).txt`），无覆盖、无半成品、无残留占位 |
| A-31 | Content-Type 矩阵 | 分别用 `application/json` 调 `/api/session`、`/api/text`，`multipart/form-data` 调 `/api/upload` | 三者均成功；JSON 超 1MB 返回 413；错误 Content-Type 返回 415 |
| A-32 | Range 三种形式 | `bytes=a-b`、`bytes=a-`、`bytes=-n` | 均 206 且 `Content-Range` 正确；越界/多区间 416；HEAD 元信息与 GET 一致 |
| A-33 | 外部同名竞态 | 上传中在 Finder 删除占位并新建同名文件 | 用户新文件不被覆盖，上传落盘为 `a (1).txt`；崩溃恢复不误删零字节用户文件 |
| A-34 | IPv6 访问 | Safari/Chrome 打开 `http://[...]:47820/`（ULA 与链路本地各一次） | 页面可打开并完成一次下载；Host 校验通过 |
| A-35 | Expect 前置拒绝 | 未认证/无上传权限/磁盘不足/超配额时发 `Expect: 100-continue` | 均不返回 100，直接 401/403/507/429 并断开 |
| A-36 | DELETE CSRF | 注销时缺少 `X-CalmBar-Client` | 返回 403，会话仍有效 |

### 9.4 完成标准

- `swift build --disable-sandbox` 通过；`swift test --disable-sandbox` 通过，且包含 Parser 模糊测试与路径/认证安全测试。
- `--visual` 与 `--spike lanshare` 截图/日志归档，验收后 Spike 代码删除。
- 新增权限在 `Info.plist` 与权限中心可见。
- README、RELEASE.md 已同步；发版说明包含「首次使用需允许本地网络/防火墙」与「明文传输」提示。
- 无新增第三方依赖，无构建产物混入提交。

---

## 10. 附录

### A. 术语表

| 术语 | 解释 |
| --- | --- |
| 分享根 | 用户显式添加的文件或文件夹；接收端只能看到这些内容 |
| 会话令牌 | 服务启动时生成的随机串，用于证明「拿到链接的人」有权访问 |
| 运行意图 | 记录服务在休眠前是否处于运行态，用于唤醒后决定是否恢复 |
| SSE | Server-Sent Events，服务器单向推送事件；本项目只推「列表变了」 |
| Range | HTTP 分段下载，浏览器/下载器据此实现断点续传 |
| 选定网卡前缀 | 分享时选定的网卡地址 + 子网前缀；只有同前缀来源才算「同一局域网」（不按 RFC1918 粗判） |

### B. 数据对象

**A-1 LANShareItem**

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID string | 是 | 稳定主键，接收端 URL 使用 |
| `kind` | `file` / `folder` / `text` | 是 | 条目类型 |
| `name` | string | 是 | 显示名 |
| `path` | string | 否 | 真实路径（file/folder） |
| `text` | string | 否 | 文字全文（text） |
| `intro` | string | 否 | 文字摘要（前 100 字） |
| `size` | Int64 | 否 | 文件/文件夹大小；文件夹异步估算，计算完成前为 `null`（BR-53） |
| `addedAt` | Date | 是 | 添加时间 |
| `source` | `local` / `remote` | 是 | 本机添加或接收端上传 |
| `uploaderIP` | string | 否 | 远程来源 IP（脱敏展示） |
| `isValid` | Bool | 是 | 实体文件/目录是否仍可访问（支撑 BR-41） |
| `invalidReason` | string? | 否 | 失效原因：`missing` / `moved` / `permissionDenied` |

**A-2 LANShareSettings**

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `receiveDirectory` | string | `~/Downloads/CalmBar 互传` | 上传落点 |
| `port` | Int | 47820 | **1024~65535**；自动回退仅 47820~47829 |
| `passcodeEnabled` | Bool | false | 是否启用口令 |
| `passcodeVerifier` | string? | nil | HMAC 校验值；密钥存 Keychain，状态文件不含可离线枚举的哈希 |
| `allowUpload` | Bool | true | 控制文件+文字上传 |
| `serverName` | string | `<hostname>` | 页面展示名 |
| `selectedInterface` | string? | nil | 选定网卡标识；为空时自动选择 |

**A-3 LANShareSession / Status**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `status` | stopped/starting/running/restricted/failed | 服务状态（唯一枚举） |
| `port` | Int | 实际监听端口 |
| `linkToken` | string | 仅内存，停止即清空；仅用于换取 Cookie |
| `shareURL` | URL? | 当前链接（无口令时含 `#t=` Fragment） |
| `networkAddress` | string | 选定网卡 IPv4/IPv6 地址 |
| `networkPrefix` | string | 选定网卡前缀（用于来源校验） |
| `sessionCount` | Int | 活动会话数（≤5），UI 文案「约 N 台设备（N 个会话）」 |
| `connectionCount` | Int | 当前 TCP 连接数，仅内部监控与日志，不作为设备数展示 |
| `transferCount` | Int | 正在传输数 |
| `lastError` | LANShareError? | 最近一次错误 |

> **连接数 / 会话数 / 设备数定义（BR-05 配套）**
> - TCP 活动连接数：正在处理的 socket 数，`Connection: close` 下等于「正在处理的请求数」，**不可当作设备数**。
> - 活动会话数：已认证且未过期的浏览器会话数，MVP 用它做并发上限（≤5）。
> - 设备数：仅为展示估算，按「会话 IP + User-Agent 指纹」去重；同一设备多标签页共用同一 Cookie，因此只计 1 个会话；同一 IP 多台设备按不同会话分别计数。
> - MVP 窗口展示「约 N 台设备（N 个会话）」，不展示 TCP 连接数；`sessionCount` 是会话数，不是可靠物理设备数。

**A-4 ZipCacheEntry（P2）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `cacheKey` | string | P2：递归 mtime/size/inode 指纹；MVP 无缓存 |
| `archivePath` | string | 临时 ZIP 路径 |
| `createdAt` | Date | 创建时间 |
| `expiresAt` | Date | 创建 + 30 分钟（P2） |
| `refCount` | Int | 正在下载的引用数 |
| `state` | building/ready/failed | 打包状态 |

**A-5 AccessLogEntry**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `time` | Date | 时间 |
| `ip` | string | 来源 IP（脱敏） |
| `action` | string | 列表/下载/上传/文字/认证 |
| `result` | string | 成功/失败码 |
| `detail` | string | 不含令牌与绝对路径 |

**A-6 SSEEvent（P2）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `event` | string | 固定 `items_changed` |
| `data` | JSON | `{ "revision": 12 }`，不含文件内容 |

**A-7 TransferTask**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `transferID` | UUID | 任务唯一标识 |
| `itemID` | UUID? | 关联分享条目 |
| `fileName` | string | 文件名（脱敏路径） |
| `peerIP` | string | 对端 IP（脱敏展示） |
| `direction` | `download` / `upload` | 传输方向 |
| `totalBytes` | Int64 | 总字节 |
| `transferredBytes` | Int64 | 已传输字节 |
| `bytesPerSecond` | Double | 实时速度（1 秒滑动窗口） |
| `startedAt` | Date | 开始时间 |
| `state` | waiting/transferring/completed/failed/cancelled | 任务状态 |
| `error` | LANShareError? | 失败原因 |

### C. CalmBar HTTP 接口

| 方法 | 路径 | 认证 | 请求 | 响应 | 说明 |
| --- | --- | --- | --- | --- | --- |
| GET | `/` | 无 | — | HTML | 接收端页面 |
| GET | `/assets/*` | 无 | — | 静态资源 | 包内资源，禁止目录遍历 |
| GET | `/api/bootstrap` | 无 | — | `{serverName, passcodeRequired, authMode}` | 页面初始化；仅公开信息，不含列表/权限/路径 |
| POST | `/api/session` | **linkToken 或 passcode** + CSRF 头 | `application/json` | `Set-Cookie` + `{permissions}` | 两者均缺失/错误返回 401；绝不无条件签发；同样要求 `X-CalmBar-Client` |
| DELETE | `/api/session` | Cookie + CSRF 头 | — | 204 | 注销；缺少 CSRF 头返回 403 |
| GET | `/api/state` | Cookie | — | `{serverName, passcodeRequired, permissions, revision}` | 已认证后的状态刷新；未认证时不得调用 |
| GET | `/api/items?item=&path=` | Cookie | — | `{items, path, revision}` | 根列表或子目录 |
| GET | `/api/download?item=&path=` | Cookie | — | 200/206 文件流 | 支持 Range/HEAD；URL 不含长期 token |
| HEAD | `/api/download?...` | Cookie | — | 200 头 | 断点/大小探测 |
| POST | `/api/upload` | Cookie + CSRF 头 + allowUpload | `multipart/form-data` | `{item, transferID}` | 流式落盘；仅字段 `file` |
| POST | `/api/text` | Cookie + CSRF 头 + allowUpload | `application/json` | `{item}` | 文字消息；body ≤ 1MB |
| GET | `/api/events` | Cookie | — | `text/event-stream` | **P2** SSE 事件 |

**错误码**

| 状态码 | 含义 | 页面文案 |
| --- | --- | --- |
| 400 | 参数错误 | 「请求有误，请刷新页面重试」 |
| 401 | 未认证/令牌失效 | 「链接已失效，请向对方重新获取」 |
| 403 | 无权限/越权路径 | 「没有访问权限」 |
| 404 | 条目/文件不存在 | 「内容已被移除」 |
| 405 | 方法不允许 | 「不支持的操作」 |
| 409 | 状态冲突 | 「服务状态已变化，请重试」 |
| 411 | 缺少 Content-Length | 「上传请求不完整，请重试」 |
| 413 | 文件过大 | 「文件超过 20GB 上限」 |
| 416 | Range 非法 | 浏览器自动处理，不展示 |
| 429 | 限流/锁定 | 「尝试过于频繁，请稍后再试」 |
| 431 | 请求头过大 | 「请求格式异常」 |
| 500 | 服务内部错误 | 「服务出错了，请重试」 |
| 501 | 不支持的协议行为（Chunked / HTTP/2 / WebSocket） | 「当前浏览器版本不受支持」 |
| 507 | 磁盘不足 | 「对方磁盘空间不足」 |

### D. 参考资料

- 参考项目源码：`reference/file-share-master`
- 参考项目 README：`reference/file-share-master/README.md`
- CalmBar 新功能接入模板：`doc/design/CalmBar 新功能接入模板.md`
- CalmBar 工程约束：`app/AGENTS.md`
- 现有 HTTP 服务实现：`app/Sources/CalmBar/Services/AIGateway/GatewayHTTPServer.swift`
- 现有 `.any` 监听与 token 链接：`app/Sources/CalmBar/Update/UpdateRelayServer.swift`
- Apple Network.framework：`NWListener`、`NWConnection`、`NWPathMonitor`
- RFC 7233（Range Requests）、RFC 6455 之外的 SSE 规范（EventSource）

### E. 证据索引（参考实现）

| 证据 ID | 主题 | 位置 |
| --- | --- | --- |
| E-01 | 服务启动/停止 | `reference/file-share-master/shared/utils/Server.js:414-441` |
| E-02 | 路由与静态资源 | `Server.js:195-213` |
| E-03 | 网卡/IP 选择 | `reference/file-share-master/shared/utils/IpUtil.js:26-105` |
| E-04 | 链接与默认端口 | `shared/utils/Setting.js:56-58, 80-88` |
| E-05 | 分享列表存储 | `shared/utils/FileDb.js:12-74` |
| E-06 | 根列表/子目录 | `Server.js:214-245`、`shared/utils/FileUtil.js:22-43` |
| E-07 | 相对路径解析 | `Server.js:158-181` |
| E-08 | 文件下载 | `Server.js:291-320` |
| E-09 | 文件夹 ZIP | `Server.js:303-315`、`shared/utils/ZipUtil.js:10-23`、`shared/utils/FileUtil.js:89-122` |
| E-10 | 上传落盘 | `Server.js:360-380` |
| E-11 | 文字消息 | `Server.js:382-397`、`shared/utils/FileDb.js:48-60` |
| E-12 | 列表事件广播 | `Server.js:399-405` |
| E-13 | SSE 实现 | `shared/utils/SseUtil.js:5-30` |
| E-14 | JWT 与鉴权过滤 | `Server.js:20-153` |
| E-15 | 账号与路径权限 | `shared/utils/Account.js:7-30, 166-220` |
| E-16 | 分享端 UI | `page_app/src/views/DetailPage.vue:16-79, 153-226, 320-322` |
| E-17 | 接收端 UI | `page_web/src/views/FilePage.vue:144-165, 268-280, 313-362, 392-396` |
| E-18 | 平台存储适配 | `electron/src/render/utils/PlatformAdapterInstance.js:6-79`、`utools/preload/index.js:5-6` |
| E-19 | 端口变更重启 | `electron/src/render/render.js:27-42`、`utools/preload/index.js:53-69` |
| E-20 | 服务自启 | `electron/src/render/render.js:20-24`、`utools/preload/index.js:18-40` |
| E-21 | 平台 API 注入 | `electron/src/render/render.js:49-82`、`utools/preload/index.js:76-108` |
| E-22 | 依赖清单 | `shared/package.json:40-50` |
