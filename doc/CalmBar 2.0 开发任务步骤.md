# CalmBar 2.0 开发任务步骤

> 用途：本文件用于交付给其他 AI 或开发者执行 CalmBar 2.0 渐进式改造任务。
>
> 依据：[CalmBar 2.0 渐进式优化方案](./CalmBar%202.0%20优化方案.md)

---

## 1. 执行总则

### 1.1 核心目标

将当前 CalmBar 从“多个功能 Manager 并列启动的 macOS 小工具集合”，逐步改造成具备长期扩展能力的 **macOS 全能菜单栏工具箱平台**。

本轮开发不追求一次性完成全部架构升级，而是按阶段交付可编译、可测试、可回滚的小步改造。

### 1.2 必须遵守

1. 不推翻现有架构。
2. 不大规模移动现有文件。
3. 不删除现有 Manager 单例。
4. 不重写 `CalmBarKit`、`CalmBarHelper`、XPC、SMC 底层能力。
5. 不把 Helper 扩展成业务层。
6. 每个任务都必须保持 App 可编译。
7. 每个任务结束后必须运行至少一次基础验证。

### 1.3 优先保留

以下文件和能力默认视为稳定底座：

```text
app/Sources/CalmBarKit/SMCConnection.swift
app/Sources/CalmBarKit/FanController.swift
app/Sources/CalmBarKit/SMCBattery.swift
app/Sources/CalmBarKit/SafetyPolicy.swift
app/Sources/CalmBarKit/CalmBarHelperProtocol.swift
app/Sources/CalmBarHelper/CalmBarHelperMain.swift
app/Sources/CalmBar/Thermal/HelperClient.swift
```

除非任务明确要求，否则不要修改它们。

### 1.4 推荐验证命令

在仓库根目录执行：

```bash
cd app
swift test
swift build
```

如涉及打包脚本，再执行：

```bash
cd app
bash build_app.sh
```

---

## 2. 当前代码入口

执行任务前，先阅读以下文件：

```text
README.md
doc/CalmBar 2.0 优化方案.md
app/Package.swift
app/Sources/CalmBar/AppDelegate.swift
app/Sources/CalmBar/Core/AppSettings.swift
app/Sources/CalmBar/Core/PermissionManager.swift
app/Sources/CalmBar/Core/SystemEventCoordinator.swift
app/Sources/CalmBar/UI/PopoverContentView.swift
app/Sources/CalmBar/Thermal/HelperClient.swift
```

当前启动模式集中在 `AppDelegate.applicationDidFinishLaunching`：

```swift
_ = SystemEventCoordinator.shared
_ = PermissionManager.shared
_ = StatusBarManager.shared
_ = MenuBarOrganizer.shared
_ = HotKeyManager.shared
_ = ScrollReverserManager.shared
_ = NoTunesManager.shared
_ = CaffeineManager.shared
_ = BatteryChargeManager.shared
_ = ClipboardMonitor.shared
_ = ThermalMonitor.shared
```

2.0 改造的第一目标不是删除这些启动逻辑，而是逐步把它们纳入 `FeatureManager` 管理。

---

## 3. 交付节奏

推荐按以下顺序拆成多个独立 PR 或多个独立提交：

```text
Task 00: 基线确认与文档对齐
Task 01: Feature 基础类型
Task 02: FeatureManager 注册表
Task 03: 低风险 Feature 薄包装
Task 04: 系统级 Feature 薄包装
Task 05: Permission 与 Feature 绑定
Task 06: CommandCenter 基础能力
Task 07: Command Palette 初版 UI
Task 08: Service Layer 第一批抽离
Task 09: Dashboard 首页瘦身
Task 10: RecoveryCoordinator 统一恢复
Task 11: 新增功能模板与文档收尾
```

每个任务都应独立可编译，不要把多个阶段混在一次大改里。

---

## 4. 任务卡片

### Task 00：基线确认与文档对齐

目标：确认当前项目状态，不改运行行为。

涉及文件：

```text
README.md
doc/CalmBar 2.0 优化方案.md
doc/CalmBar 2.0 开发任务步骤.md
```

执行步骤：

1. 阅读 2.0 优化方案。
2. 对照当前目录确认已有功能模块。
3. 在 README 中补充 2.0 架构方案文档链接。
4. 不修改 App 启动逻辑。
5. 不修改任何 Swift 业务代码。

验收标准：

1. 文档链接清晰。
2. `swift test` 通过或说明失败原因。
3. 没有行为改动。

建议提交信息：

```text
docs: add CalmBar 2.0 development roadmap
```

---

### Task 01：Feature 基础类型

目标：新增 Feature Layer 的基础类型，不接管现有逻辑。

新增目录：

```text
app/Sources/CalmBar/Features/
```

新增文件：

```text
app/Sources/CalmBar/Features/FeatureID.swift
app/Sources/CalmBar/Features/FeatureCategory.swift
app/Sources/CalmBar/Features/FeatureState.swift
app/Sources/CalmBar/Features/FeaturePermissionRequirement.swift
app/Sources/CalmBar/Features/FeatureCommand.swift
app/Sources/CalmBar/Features/CalmFeature.swift
```

建议内容：

```swift
public enum FeatureID: String, CaseIterable, Identifiable, Sendable {
    case thermal
    case battery
    case caffeine
    case clipboard
    case ocr
    case cleaner
    case scroll
    case noTunes
    case gatekeeper
    case menuBar

    public var id: String { rawValue }
}
```

```swift
public enum FeatureCategory: String, CaseIterable, Identifiable, Sendable {
    case system
    case hardware
    case productivity
    case input
    case security
    case cleanup

    public var id: String { rawValue }
}
```

```swift
public enum FeatureState: Equatable, Sendable {
    case unavailable
    case disabled
    case enabled
    case running
    case suspended
    case needsPermission
    case degraded
    case failed(String)
}
```

```swift
public struct FeaturePermissionRequirement: Sendable {
    public let type: PermissionType
    public let level: PermissionRequirementLevel
    public let reason: String
}

public enum PermissionRequirementLevel: Sendable {
    case required
    case optional
    case advanced
}
```

```swift
@MainActor
public protocol CalmFeature: ObservableObject {
    var id: FeatureID { get }
    var title: String { get }
    var category: FeatureCategory { get }
    var requiredPermissions: [FeaturePermissionRequirement] { get }
    var state: FeatureState { get }
    var commands: [FeatureCommand] { get }

    func start()
    func stop()
    func suspend()
    func resume()
    func cleanup()
}
```

注意事项：

1. `FeaturePermissionRequirement` 可以引用现有 `PermissionType`。
2. 不要修改 `PermissionManager` 行为。
3. `FeatureCommand` 初期可以是轻量结构，不要依赖 CommandCenter。

验收标准：

1. 新增类型可编译。
2. 未接入任何运行路径。
3. `swift build` 通过。

建议提交信息：

```text
feat: add feature foundation types
```

---

### Task 02：FeatureManager 注册表

目标：新增统一 Feature 注册表，先不改变 App 行为。

新增文件：

```text
app/Sources/CalmBar/Features/FeatureManager.swift
app/Tests/CalmBarTests/FeatureManagerTests.swift
```

建议实现：

1. `FeatureManager.shared` 为 `@MainActor ObservableObject`。
2. 提供 `features: [any CalmFeature]` 或类型擦除包装。
3. 提供按 ID 查询能力。
4. 提供统一 `startAll()`、`cleanupAll()`。
5. 暂时不在 `AppDelegate` 中接管启动。

建议接口：

```swift
@MainActor
public final class FeatureManager: ObservableObject {
    public static let shared = FeatureManager()

    public private(set) var features: [FeatureID: any CalmFeature] = [:]

    public func register(_ feature: any CalmFeature)
    public func feature(id: FeatureID) -> (any CalmFeature)?
    public func startAll()
    public func cleanupAll()
}
```

测试要求：

1. Feature ID 不重复。
2. 注册后可按 ID 查询。
3. `startAll()` 会调用每个 Feature 的 `start()`。
4. `cleanupAll()` 会调用每个 Feature 的 `cleanup()`。

验收标准：

1. `swift test` 通过。
2. App 启动行为不变。

建议提交信息：

```text
feat: add feature manager registry
```

---

### Task 03：低风险 Feature 薄包装

目标：先选择低风险后台能力作为 Feature 包装试点。

新增文件：

```text
app/Sources/CalmBar/Features/NoTunesFeature.swift
app/Sources/CalmBar/Features/ScrollFeature.swift
app/Sources/CalmBar/Features/CaffeineFeature.swift
```

包装对象：

```text
app/Sources/CalmBar/NoTunes/NoTunesManager.swift
app/Sources/CalmBar/Scroll/ScrollReverserManager.swift
app/Sources/CalmBar/Caffeine/CaffeineManager.swift
```

执行步骤：

1. 为每个 Feature 填写 `id`、`title`、`category`、`requiredPermissions`、`state`。
2. `start()` 内部调用现有 Manager 的启动或初始化逻辑。
3. `stop()` 内部调用现有 Manager 的停止方法。
4. `cleanup()` 内部调用现有安全清理方法。
5. 注册到 `FeatureManager`，但暂不替换 `AppDelegate` 原启动逻辑。

权限要求：

| Feature | 权限 |
| --- | --- |
| NoTunesFeature | 无必需权限 |
| ScrollFeature | Accessibility required |
| CaffeineFeature | Accessibility advanced，仅 Keep Apps Active 需要 |

验收标准：

1. 包装层不改变现有行为。
2. 缺少 Accessibility 时 ScrollFeature 状态能表达 `needsPermission` 或 `degraded`。
3. `swift test` 通过。

建议提交信息：

```text
feat: wrap low-risk managers as features
```

---

### Task 04：系统级 Feature 薄包装

目标：将其余现有功能纳入 Feature 概念，但仍保留现有 Manager。

新增文件：

```text
app/Sources/CalmBar/Features/ThermalFeature.swift
app/Sources/CalmBar/Features/BatteryFeature.swift
app/Sources/CalmBar/Features/ClipboardFeature.swift
app/Sources/CalmBar/Features/OCRFeature.swift
app/Sources/CalmBar/Features/CleanerFeature.swift
app/Sources/CalmBar/Features/GatekeeperFeature.swift
app/Sources/CalmBar/Features/MenuBarFeature.swift
```

包装对象：

```text
app/Sources/CalmBar/Thermal/ThermalMonitor.swift
app/Sources/CalmBar/Battery/BatteryChargeManager.swift
app/Sources/CalmBar/Clipboard/Core/ClipboardMonitor.swift
app/Sources/CalmBar/OCR/OCRManager.swift
app/Sources/CalmBar/Cleaner/Managers/CleanerManager.swift
app/Sources/CalmBar/Gatekeeper/GatekeeperManager.swift
app/Sources/CalmBar/MenuBar/MenuBarOrganizer.swift
```

权限要求：

| Feature | 权限 |
| --- | --- |
| ThermalFeature | Privileged Helper required for fan write，读温度可 degraded |
| BatteryFeature | Privileged Helper required for charging limit |
| ClipboardFeature | 无必需权限 |
| OCRFeature | Screen Recording required for new capture |
| CleanerFeature | Full Disk Access advanced |
| GatekeeperFeature | Privileged Helper required for protected paths/deep fix |
| MenuBarFeature | 无必需权限 |

执行步骤：

1. 每个 Feature 只做薄包装，不改 Manager 内部逻辑。
2. `ThermalFeature.cleanup()` 必须恢复风扇 Auto。
3. `BatteryFeature.cleanup()` 必须恢复默认充电。
4. `ClipboardFeature.stop()` 必须停止监听。
5. `OCRFeature` 权限缺失时保留历史入口，但禁用新截图命令。
6. `CleanerFeature` 权限缺失时允许普通扫描，提示深层扫描能力降级。

验收标准：

1. 现有 UI 行为不变。
2. 所有 Feature 已注册。
3. `swift test` 通过。

建议提交信息：

```text
feat: register existing CalmBar tools as features
```

---

### Task 05：Permission 与 Feature 绑定

目标：让权限中心能够解释“权限影响哪些功能”。

修改文件：

```text
app/Sources/CalmBar/Core/PermissionManager.swift
app/Sources/CalmBar/UI/Components/PermissionCenterView.swift
app/Sources/CalmBar/Features/*.swift
app/Tests/CalmBarTests/PermissionFeatureTests.swift
```

执行步骤：

1. 在 `PermissionManager` 中新增按 Feature 查询权限状态的方法。
2. 在 `PermissionManager` 中新增按 Permission 查询受影响 Feature 的方法。
3. 修改 Permission Center，显示每项权限影响的功能列表。
4. 保留现有权限检测方式。
5. 权限缺失时不要弹出强制授权，只展示状态和入口。

建议接口：

```swift
public func requirements(for featureID: FeatureID) -> [FeaturePermissionRequirement]
public func affectedFeatures(for permission: PermissionType) -> [FeatureID]
public func isFeatureUsable(_ featureID: FeatureID) -> Bool
```

测试要求：

1. Accessibility 影响 Scroll 和 Caffeine 高级能力。
2. Privileged Helper 影响 Thermal、Battery、Gatekeeper。
3. Screen Recording 影响 OCR。
4. Full Disk Access 影响 Cleaner 深层扫描。

验收标准：

1. Permission Center 能解释权限用途。
2. 权限缺失不导致 App 崩溃。
3. `swift test` 通过。

建议提交信息：

```text
feat: map permissions to features
```

---

### Task 06：CommandCenter 基础能力

目标：建立统一命令模型，但先不做完整 UI。

新增目录：

```text
app/Sources/CalmBar/Commands/
```

新增文件：

```text
app/Sources/CalmBar/Commands/CommandDescriptor.swift
app/Sources/CalmBar/Commands/CommandCategory.swift
app/Sources/CalmBar/Commands/CommandResult.swift
app/Sources/CalmBar/Commands/CommandCenter.swift
app/Tests/CalmBarTests/CommandCenterTests.swift
```

建议模型：

```swift
public struct CommandDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: CommandCategory
    public let featureID: FeatureID?
    public let requiredPermissions: [PermissionType]
    public let aliases: [String]
    public let run: @MainActor () async -> CommandResult
}
```

首批命令：

1. 打开设置。
2. 打开权限中心。
3. 开始 OCR 选区识别。
4. 打开 OCR 历史。
5. 打开剪贴板历史。
6. 开启/关闭防休眠。
7. 临时充至 100%。
8. 切换滚轮反转。
9. 展开/折叠菜单栏。
10. 扫描应用残留。
11. 扫描开发缓存。

执行步骤：

1. `CommandCenter` 从 `FeatureManager` 收集命令。
2. 支持按标题、别名、分类搜索。
3. 执行前检查权限。
4. 返回统一 `CommandResult`。
5. 暂时通过测试验证，不要求 UI 接入。

验收标准：

1. 命令可以注册、搜索、执行。
2. 权限不足时返回明确结果。
3. `swift test` 通过。

建议提交信息：

```text
feat: add command center foundation
```

---

### Task 07：Command Palette 初版 UI

目标：提供可用的命令搜索与执行入口。

新增文件：

```text
app/Sources/CalmBar/Commands/CommandPaletteView.swift
app/Sources/CalmBar/Commands/CommandPaletteWindowController.swift
```

修改文件：

```text
app/Sources/CalmBar/UI/PopoverContentView.swift
app/Sources/CalmBar/MenuBar/HotKeyManager.swift
```

执行步骤：

1. 新增 Command Palette 窗口或浮层。
2. 支持搜索输入。
3. 支持上下键选择。
4. 支持回车执行。
5. 支持权限缺失状态展示。
6. 在 Popover 加入 Command Palette 入口。
7. 可选：增加全局快捷键。

UI 要求：

1. 不做营销页。
2. 不把所有功能继续堆到首页。
3. 命令列表要能键盘操作。
4. 权限不足命令不能静默失败。

验收标准：

1. 用户可以从菜单栏打开 Command Palette。
2. 用户可以搜索并执行首批命令。
3. `swift build` 通过。

建议提交信息：

```text
feat: add command palette
```

---

### Task 08：Service Layer 第一批抽离

目标：先抽离最能降低耦合的 Service，不重写所有模块。

新增目录：

```text
app/Sources/CalmBar/Services/
```

第一批新增文件：

```text
app/Sources/CalmBar/Services/ServiceError.swift
app/Sources/CalmBar/Services/HelperService.swift
app/Sources/CalmBar/Services/FanService.swift
app/Sources/CalmBar/Services/BatteryService.swift
```

修改文件：

```text
app/Sources/CalmBar/Thermal/ThermalMonitor.swift
app/Sources/CalmBar/Battery/BatteryChargeManager.swift
app/Sources/CalmBar/Thermal/HelperClient.swift
```

执行步骤：

1. 新增 `ServiceError`，统一 helper unavailable、permission denied、unsupported hardware、operation failed。
2. 新增 `HelperService`，薄包装 `HelperClient`。
3. 新增 `FanService`，封装设置风扇比例、恢复 Auto。
4. 新增 `BatteryService`，封装充电阻断、强制放电、SMC 状态读取。
5. 将 `ThermalMonitor.writeFanFraction()` 逐步改为调用 `FanService`。
6. 将 `BatteryChargeManager.applyInhibition()` 和 `applyForceDischarge()` 逐步改为调用 `BatteryService`。

注意事项：

1. 不修改 `CalmBarHelperProtocol`，除非确实需要新增 XPC 方法。
2. 不改变当前错误文案的用户含义。
3. 不改变风扇和充电安全策略。

验收标准：

1. Thermal 与 Battery 行为保持一致。
2. Helper 未安装时仍能给出原有提示。
3. `BatterySafetyTests`、`FanCurveTests` 通过。
4. `swift test` 通过。

建议提交信息：

```text
refactor: introduce helper fan and battery services
```

---

### Task 09：Dashboard 首页瘦身

目标：减少 `PopoverContentView` 对底层 Manager 的直接依赖。

新增文件：

```text
app/Sources/CalmBar/UI/Dashboard/DashboardViewModel.swift
app/Sources/CalmBar/UI/Dashboard/FeatureDashboardItem.swift
```

修改文件：

```text
app/Sources/CalmBar/UI/PopoverContentView.swift
app/Sources/CalmBar/Features/*.swift
```

执行步骤：

1. 新增 `FeatureDashboardItem`。
2. 每个 Feature 可选提供 Dashboard 摘要。
3. 新增 `DashboardViewModel` 聚合首页展示数据。
4. `PopoverContentView` 优先读取 Dashboard ViewModel。
5. 保留现有复杂 UI 区块，逐步迁移，不一次删除。
6. 首页保留 3 到 5 个高频 Quick Actions。

建议首页保留：

1. 温度/风扇摘要。
2. 电池摘要。
3. 权限异常提示。
4. OCR 快捷入口。
5. Clipboard 快捷入口。
6. Command Palette 入口。
7. 设置入口。

验收标准：

1. `PopoverContentView` 直接观察的 Manager 数量下降。
2. 首页仍能完成当前高频操作。
3. 低频功能可通过设置或 Command Palette 找到。
4. `swift build` 通过。

建议提交信息：

```text
refactor: route popover through dashboard model
```

---

### Task 10：RecoveryCoordinator 统一恢复

目标：集中管理退出、睡眠、Feature 停用时的安全恢复。

新增目录：

```text
app/Sources/CalmBar/Recovery/
```

新增文件：

```text
app/Sources/CalmBar/Recovery/RecoveryCoordinator.swift
app/Sources/CalmBar/Recovery/RecoveryReason.swift
app/Sources/CalmBar/Recovery/RecoveryAction.swift
app/Sources/CalmBar/Recovery/RecoveryAuditLog.swift
app/Tests/CalmBarTests/RecoveryCoordinatorTests.swift
```

修改文件：

```text
app/Sources/CalmBar/AppDelegate.swift
app/Sources/CalmBar/Core/SystemEventCoordinator.swift
app/Sources/CalmBarHelper/CalmBarHelperMain.swift
```

执行步骤：

1. 新增 `RecoveryReason`：appQuit、systemSleep、featureDisabled、helperDisconnected、manual。
2. 新增 `RecoveryCoordinator.performRecovery(reason:)`。
3. 将 `AppDelegate.cleanup()` 改为调用 Recovery。
4. 将 `SystemEventCoordinator.handleWillSleep()` 改为调用 Recovery。
5. Recovery 初期直接调用现有 Manager 清理方法。
6. 确保恢复动作幂等。
7. 记录最近一次恢复动作，可先使用内存日志。

第一版恢复动作：

```text
ThermalMonitor.shared.restoreSystemControl()
BatteryChargeManager.shared.restoreDefaultCharging()
CaffeineManager.shared.cleanupOnExit()
ScrollReverserManager.shared.stop()
ClipboardMonitor.shared.stopMonitoring()
NoTunesManager.shared.stopMonitoring()
HotKeyManager.shared.unregister()
```

验收标准：

1. App 退出仍恢复风扇和充电。
2. 系统睡眠前仍恢复风扇和充电。
3. 重复调用 Recovery 不崩溃。
4. `swift test` 通过。

建议提交信息：

```text
feat: centralize safety recovery handling
```

---

### Task 11：新增功能模板与文档收尾

目标：为后续新增工具建立统一准入模板。

新增文件：

```text
doc/CalmBar 新功能接入模板.md
```

模板必须包含：

1. Feature 名称。
2. Feature 分类。
3. Service 边界。
4. 权限声明。
5. Command 列表。
6. Dashboard 是否展示。
7. Settings 项。
8. Recovery 行为。
9. 测试清单。
10. 用户可见失败状态。

执行步骤：

1. 编写新功能接入模板。
2. 在 README 或 2.0 方案中链接模板。
3. 对照现有 Feature 检查是否满足模板。
4. 补充未来候选功能列表：网络、DNS、Wi-Fi、显示器、音频、文件、系统信息等。

验收标准：

1. 其他 AI 可以根据模板新增功能。
2. 新功能不会默认挤进首页。
3. 新功能必须注册 Feature、Permission、Command、Recovery。

建议提交信息：

```text
docs: add feature integration template
```

---

## 5. 任务执行检查清单

每个开发任务完成后，执行者必须回答以下问题：

```text
1. 本任务是否改变运行行为？如果改变，改变点是什么？
2. 是否修改了 CalmBarKit / Helper / XPC？如果修改，原因是什么？
3. 是否新增或改变权限需求？
4. 是否新增用户可见入口？
5. 是否影响 App 启动顺序？
6. 是否影响退出、睡眠、崩溃恢复？
7. 是否运行 swift test / swift build？
8. 哪些测试失败？失败是否与本任务相关？
9. 是否存在未完成的 TODO？
```

---

## 6. 禁止事项

以下行为默认禁止，除非用户明确要求：

1. 一次性移动大量模块目录。
2. 删除现有 Manager 单例。
3. 重写 `AppSettings`。
4. 重写 `CalmBarHelperMain`。
5. 改变 `CalmBarHelperProtocol` 的现有方法语义。
6. 将 OCR、Clipboard、Cleaner 业务逻辑放进 Helper。
7. 在首页继续堆叠所有新增功能入口。
8. 在权限缺失时静默失败。
9. 在没有测试的情况下修改风扇、充电、安全恢复逻辑。
10. 将 Command Palette 做成复杂插件系统。

---

## 7. 推荐给其他 AI 的任务提示词

可以按任务复制以下提示词给其他 AI：

```text
你正在开发 CalmBar，一个 Swift 6 + SwiftUI + AppKit 的 macOS 菜单栏工具箱项目。

请先阅读：
- README.md
- doc/CalmBar 2.0 优化方案.md
- doc/CalmBar 2.0 开发任务步骤.md
- app/Sources/CalmBar/AppDelegate.swift
- app/Sources/CalmBar/Core/PermissionManager.swift
- app/Sources/CalmBar/Core/AppSettings.swift

本次只执行 Task XX：<任务名称>。

要求：
1. 不推翻现有架构。
2. 不删除现有 Manager 单例。
3. 不大规模移动文件。
4. 保持 CalmBarKit、Helper、XPC、SMC 核心能力稳定。
5. 每一步都要保持项目可编译。
6. 完成后运行 cd app && swift test，必要时运行 swift build。
7. 最终说明修改文件、行为变化、测试结果和剩余风险。
```

---

## 8. 总结

CalmBar 2.0 的开发任务应按“小步交付、稳定优先、外层治理先行”的方式推进。

最先交付的是 Feature 注册、权限映射和命令系统；随后再抽 Service、瘦首页、统一 Recovery。这样既能保护现有功能，又能让 CalmBar 后续继续扩展为真正的 macOS 全能工具箱平台。
