# AGENTS.md —— CalmBar macOS 客户端工程约束

> 范围：只约束 `app/`（Swift 主工程）。`web/` 见 `web/AGENTS.md`，`doc/` 为设计与发版资料，根 `README.md` 面向用户。
> 技术栈：Swift 6 / SwiftUI + AppKit / SwiftPM / macOS 14+；唯一外部依赖是 Sparkle。

---

## 硬性红线

| 编号 | 规则 |
| --- | --- |
| APP-01 | 版本号只改 `Resources/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`；build 号必须单调递增，改展示版本不改 build 会导致 Sparkle 不更新 |
| APP-02 | 发版前先读 `doc/release/RELEASE-SKILL.md`，按其中顺序执行；DMG 完成 EdDSA 签名后禁止重新打包 |
| APP-03 | 新功能必须走 `CalmFeature` / `FeatureID` / `FeatureManager` 体系，并在 `registerDefaultFeatures()` 中显式注册；禁止绕过 Feature 层直接挂状态栏或设置页 |
| APP-04 | 菜单栏面板窗口固定 `320×520`，Tab 切换只允许在 SwiftUI 内部动画内容高度；禁止按 Tab 修改窗口 frame |
| APP-05 | 实时音频渲染回调禁止加锁、分配内存或触碰 UI；增益/静音使用 `AtomicFloatBox` 等无锁原子量，引擎构建放到 `buildQueue` |
| APP-06 | 使用麦克风、屏幕采集、系统音频前，先在 `Info.plist` 写对应 `NS*UsageDescription`；缺失会导致系统静默拒绝 |
| APP-07 | 特权操作统一走 `HelperClient` / `CalmBarHelper` + LaunchDaemon；禁止在 UI 层拼接 `sudo` 或临时提权脚本 |
| APP-08 | 不提交 `app/build/`、`.build/`、`app/scratch/`、日志与崩溃文件；这些路径已在 `.gitignore` |
| APP-09 | 除 Sparkle 外不新增第三方依赖；确需引入时先说明用途、体积与替代方案并征得确认 |
| APP-10 | 面向用户的文案与代码注释用简体中文，类型、变量、函数名用英文；提交信息沿用仓库的 Conventional Commits 风格 |

---

## 模块边界

| 模块 | 职责 | 约束 |
| --- | --- | --- |
| `CalmBarKit` | SMC 读写、风扇控制、安全策略、Helper XPC 协议 | 不依赖 AppKit / SwiftUI，保持纯 Foundation |
| `CommandPaletteKit` | 命令面板渲染与键盘交互组件 | 不依赖具体功能模块 |
| `CalmBarHelper` | root 特权辅助工具，由 LaunchDaemon 拉起 | 只实现 `CalmBarHelperProtocol` 内定义的操作 |
| `CalmBar` | App 本体：功能、服务、窗口、设置、状态栏 | 业务逻辑不得下沉到 `CalmBarKit` |

`Sources/CalmBar/` 目录约定：

```text
Features/        CalmFeature 实现，功能生命周期、命令、权限声明
Services/        可复用系统服务（Audio、Recorder、Battery、Fan、Helper）
Thermal/         各功能内部实现（Battery、Caffeine、Clipboard、OCR…）
Monitor/         系统采样、阈值告警、菜单栏读数
LaunchManager/   启动项与常驻服务
Recovery/        异常退出、休眠唤醒后的状态恢复
UI/              面板、设置、独立窗口、通用组件
Core/            AppSettings、PermissionManager、SystemEventCoordinator
MenuBar/         状态栏、热键、菜单栏收纳
Update/          Sparkle 与更新代理
```

---

## 构建与验证

```bash
cd app
swift build --disable-sandbox     # 调试构建
swift test --disable-sandbox      # 单元测试
./build_app.sh                    # 通用 App：build/CalmBar.app
./scripts/release.sh --dry-run    # 发版预演，只打印不修改
open build/CalmBar.app            # 运行打包产物
```

- `hdiutil`、`sign_update`（读取登录钥匙串）在受限沙箱中会失败，需在普通终端执行。
- 单个架构调试可运行 `./build_app.sh arm` 或 `./build_app.sh intel`。
- 修改 UI 或面板布局后，至少运行 `swift build`；涉及纯逻辑时补 `swift test`。

### 验证驱动

| 入口 | 用途 | 说明 |
| --- | --- | --- |
| `--visual` | 真实菜单栏面板的浅色/深色截图 | 截图与日志写入 `/tmp/calmbar_visual`，用于对照 README 与视觉回归 |
| `--m8` | 状态栏面板路径回归 | 可配合 `--dark` 固定深色外观 |
| `--spike tabbar\|height\|scroll\|content` | 临时布局试验窗口 | 不启动常驻功能；验收后删除对应代码，不并入常规启动流程 |
| `--m1` ~ `--m7` | 早期骨架/尺寸试验窗口 | 仅作历史参考，不要在其上继续扩展业务 |

调试驱动、Spike 场景与 `app/scratch/` 下的探针脚本只用于验证，不得进入用户可触发的功能路径。

---

## 新增功能清单

1. `FeatureID` 增加 case 与 `displayName`。
2. 新建 `<Name>Feature.swift`，遵循 `CalmFeature`：实现 `start` / `stop` / `state`，按需提供 `commands`、`dashboardItem`。
3. 在 `FeatureManager.registerDefaultFeatures()` 注册；不要依赖自动扫描。
4. 声明 `requiredPermissions` 与用途说明；涉及新系统权限时同步 `Info.plist` 与 `PermissionManager`。
5. 设置页：`SettingsTab` 补充 title、subtitle、icon、category、渐变、搜索关键词，并在 `SettingsView` 的 detail switch 接入新 Tab。
6. 面板：需要入口时接入对应分区（温控 / 守护 / 工具 / 监控 / 声音）；新增分区要同时改 `PopoverTab`、`PopoverTabRoute`、`PopoverLayout` 与分区视图。
7. 命令：可通过命令面板执行的操作，封装为 `FeatureCommand`，不要单独再建一套命令注册。
8. 测试：在 `Tests/CalmBarTests/` 补 XCTest，覆盖状态机、阈值、路径处理等纯逻辑。
9. 文档：用户可感知的变化同步 `README.md` 与 `doc/release/RELEASE.md`；长期有效的设计写入 `doc/design/`。

---

## UI 约定

- 面板由 `StatusBarManager` 持有 `NSStatusItem` + `NSPopover`，高度来自 `PopoverLayout`；视口高度 clamp 在 `200...360`。
- 分区内容按 `PopoverContentView` → `PopoverPanelView` → `UI/Popover/<分区>` 分层；路由常量表是唯一高度事实来源，不要用首帧 `fittingSize` 推算布局。
- 颜色统一取自 `PopoverPalette`：强调色是浅色/深色双值自适应，设置页图标渐变也由同一组令牌派生；禁止在视图里散落硬编码色值。
- 设置页以 `SettingsTab` 为唯一入口，侧边栏分组由 `SettingsCategory` 决定；新增 Tab 必须补齐搜索关键词，否则搜索不到。
- 独立窗口（清理、启动项、剪贴板、音频混音、录制）各自一个 WindowController，不复用其他功能的窗口实例。

---

## 并发与稳定性

- 功能类与 UI 状态均为 `@MainActor`；只有文件扫描、音频引擎构建、屏幕采集写盘等耗时工作放到后台队列。
- 音频：按应用聚合所有 responsible PID，不能按单 PID 分组；100% 且跟随系统时不接管播放；音量范围 `0...2.0`，变更通过增益平滑过渡。
- 录制：`SCStream` 采样集中在串行 capture 队列；暂停/续录按 host time 映射；异常退出后可从临时分片恢复。
- 系统采样与清理扫描不得阻塞主线程；结果通过 `@Published` 回到主线程更新。
- 退出、休眠、崩溃恢复相关逻辑放在 `RecoveryCoordinator`，不要在各功能里散落临时补丁。

---

## 发版

- 版本唯一来源：`Resources/Info.plist`。
- 发版说明：`doc/release/RELEASE.md`，`release.sh --dry-run` 会校验对应版本章节是否存在。
- 完整流程以 `doc/release/RELEASE-SKILL.md` 为准：递增版本 → 构建通用 App → DMG → EdDSA 签名 → 上传 Release → 最后提交 `appcast.xml`。
- 不允许先发布 appcast 再上传 DMG，避免用户拿到 404 更新地址。

---

## 文档地图

| 路径 | 内容 |
| --- | --- |
| `doc/release/RELEASE.md` | 版本更新说明与概览表 |
| `doc/release/RELEASE-SKILL.md` | 发版、签名、appcast 与 GitHub Release 流程 |
| `doc/prd/` | 已落地功能的 PRD 与接入方案，作为实现依据与历史记录 |
| `doc/design/CalmBar 新功能接入模板.md` | 新增功能的 10 项准入原则，动手前必读 |
| `doc/design/无风扇机型适配方案.md` | 无风扇机型的降级与风扇控件隐藏规则 |
| `doc/guide/HyMT2部署/` | 本地翻译服务的 macOS / 跨平台部署指南 |
| `doc/archive/` | 已失效的 2.0 规划与初版 PRD，不要据此实现 |
| `doc/images/` | README 使用的静态资源 |

---

## 完成标准

- `swift build --disable-sandbox` 通过；改到纯逻辑时 `swift test --disable-sandbox` 通过。
- UI 改动经过 `--visual` 或对应回归驱动确认，不只看编译结果。
- 新增系统能力已补 `Info.plist` 权限说明，并在权限中心可见。
- 用户可感知变化已同步 README 与发版说明，文档路径没有失效链接。
- 没有混入构建产物、临时脚本或与任务无关的重构。
