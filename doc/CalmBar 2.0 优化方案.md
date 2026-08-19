# CalmBar 2.0 渐进式优化方案

> 目标：将 CalmBar 从“功能不断增加的 macOS 小工具集合”，逐步演进为一个可持续扩展的 **macOS 全能工具箱平台**。
>
> 核心原则：**不推翻现有架构，不为了架构而重构。**

本文档面向当前 CalmBar 代码库，重点说明如何在保留 `CalmBarKit + CalmBar + CalmBarHelper + XPC + SMC` 核心能力的基础上，逐步引入 Feature / Service / Command / Permission / Recovery 等统一机制。

---

## 1. 2.0 产品定位

### 1.1 CalmBar 的定位

CalmBar 不是单一功能工具，不只是风扇控制器、电池管理器、OCR 工具、剪贴板工具或清理工具。

CalmBar 2.0 的定位是：

> **macOS 全能菜单栏工具箱平台**

它通过一个常驻菜单栏 App，承载各种高频、零散但实用的 macOS 增强能力。功能可以继续增加，但用户入口、权限模型、生命周期管理和错误恢复必须逐渐统一。

### 1.2 2.0 的产品原则

1. 功能可以持续增加。
2. 首页入口必须保持有限。
3. 低频能力通过分类、设置页、独立窗口和 Command Palette 承载。
4. 系统级能力必须可解释、可授权、可恢复。
5. 每个功能都必须有明确的生命周期、权限声明、失败提示和退出清理策略。

### 1.3 2.0 不做什么

1. 不大规模重写 `CalmBarKit`。
2. 不替换现有 SwiftUI + AppKit 混合架构。
3. 不废弃现有 Manager 单例。
4. 不把 Helper 扩展成业务层。
5. 不为了“架构整洁”打断当前功能稳定性。

---

## 2. 当前项目现状

当前项目已经具备较完整的基础能力：

```text
CalmBar/
├── app/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── CalmBar/
│   │   │   ├── AppDelegate.swift
│   │   │   ├── Core/
│   │   │   │   ├── AppSettings.swift
│   │   │   │   ├── PermissionManager.swift
│   │   │   │   ├── SystemEventCoordinator.swift
│   │   │   │   └── LaunchAtLoginHelper.swift
│   │   │   ├── Thermal/
│   │   │   ├── Battery/
│   │   │   ├── Caffeine/
│   │   │   ├── Clipboard/
│   │   │   ├── OCR/
│   │   │   ├── Cleaner/
│   │   │   ├── Gatekeeper/
│   │   │   ├── MenuBar/
│   │   │   ├── Scroll/
│   │   │   ├── NoTunes/
│   │   │   └── UI/
│   │   ├── CalmBarKit/
│   │   │   ├── SMCConnection.swift
│   │   │   ├── FanController.swift
│   │   │   ├── SMCBattery.swift
│   │   │   ├── SafetyPolicy.swift
│   │   │   └── CalmBarHelperProtocol.swift
│   │   └── CalmBarHelper/
│   │       └── CalmBarHelperMain.swift
│   └── Tests/
└── doc/
```

### 2.1 应该保留的部分

以下能力是 CalmBar 的底座，不在 2.0 阶段大规模重写：

1. `CalmBarKit`
   - `SMCConnection`
   - `FanController`
   - `SMCBattery`
   - `SafetyPolicy`
   - `CalmBarHelperProtocol`
2. `CalmBarHelper`
   - XPC 监听
   - SMC 风扇控制
   - SMC 电池控制
   - 必须通过特权进程执行的系统命令
3. `CalmBar`
   - SwiftUI + AppKit 混合架构
   - `NSStatusItem` 菜单栏形态
   - 现有独立功能目录
   - 现有测试资产

### 2.2 当前主要问题

当前代码已经按功能目录自然分组，但整体仍是“多个 Manager 单例并列启动”的形态：

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

这不是错误，反而是 2.0 渐进改造的良好起点。它的问题在于：

1. 功能生命周期分散在各个 Manager 内部。
2. App 启动顺序依赖 `AppDelegate` 手工维护。
3. 权限和功能之间没有统一声明关系。
4. UI 直接观察多个底层 Manager，首页继续增加功能会越来越重。
5. HelperClient 同时承担 XPC 连接、状态判断和部分服务门面职责。
6. 退出、睡眠、唤醒、崩溃恢复策略分散在多个位置。
7. 新增功能时缺少统一模板，容易继续复制 Manager 单例模式。

2.0 的目标不是否定这些代码，而是在它们外层补上平台化组织机制。

---

## 3. 目标架构

```text
                         CalmBar
                            │
             ┌──────────────┴──────────────┐
             │                             │
        CalmBar App                   CalmBar Helper
        用户空间                       系统级能力
             │                             │
      ┌──────┴──────┐                ┌─────┴─────┐
      │             │                │           │
   Dashboard    Command Palette     SMC        IOKit
      │             │                │           │
      └──────┬──────┘                ├── Fan     │
             │                       ├── Battery │
      FeatureManager                 └── System  │
             │
      ┌──────┴──────────────────────────────┐
      │                                     │
   Feature Layer                         Service Layer
      │                                     │
      ├── ThermalFeature                    ├── ThermalService
      ├── BatteryFeature                    ├── FanService
      ├── CaffeineFeature                   ├── BatteryService
      ├── ClipboardFeature                  ├── OCRService
      ├── OCRFeature                        ├── ClipboardService
      ├── CleanerFeature                    └── SystemService
      └── ...
```

### 3.1 Feature 决定“做什么”

Feature 是产品功能单元，负责：

1. 功能元信息：名称、分类、图标、描述、入口位置。
2. 功能生命周期：启动、暂停、恢复、停止、退出清理。
3. 用户配置：声明自己使用哪些 `AppSettings` 字段。
4. Feature 状态：启用、禁用、运行中、需要授权、失败、降级。
5. 用户操作：暴露可被 UI 和 Command Palette 调用的动作。
6. Feature UI：提供 Dashboard 卡片、设置页、独立窗口入口。
7. 权限声明：声明需要哪些权限以及权限缺失时如何降级。

### 3.2 Service 决定“怎么做”

Service 是业务能力层，负责：

1. 调用系统 API。
2. 调用 `CalmBarKit` 或 HelperClient。
3. 读取底层数据。
4. 封装状态转换。
5. 统一错误类型。
6. 为 Feature 提供稳定接口。

Service 不直接决定产品入口，不直接持有复杂 UI 状态。

### 3.3 Helper 决定“如何安全地触碰系统”

Helper 只负责高权限、系统级、必须隔离到独立进程的能力：

1. SMC 风扇读写。
2. SMC 电池充电控制。
3. IOKit 或 root 权限相关操作。
4. `xattr`、`codesign` 等必须提权的系统命令。
5. 极少数需要独立进程保护的系统操作。

Helper 不负责：

1. UI。
2. Feature 生命周期。
3. 用户配置。
4. OCR 业务。
5. Clipboard 业务。
6. Cleaner 的产品逻辑。
7. Command Palette。

---

## 4. 分层职责设计

### 4.1 Feature Layer

建议新增目录：

```text
app/Sources/CalmBar/Features/
├── Feature.swift
├── FeatureID.swift
├── FeatureCategory.swift
├── FeatureState.swift
├── FeatureManager.swift
├── FeaturePermissionRequirement.swift
├── FeatureCommand.swift
├── ThermalFeature.swift
├── BatteryFeature.swift
├── CaffeineFeature.swift
├── ClipboardFeature.swift
├── OCRFeature.swift
├── CleanerFeature.swift
├── ScrollFeature.swift
├── NoTunesFeature.swift
├── GatekeeperFeature.swift
└── MenuBarFeature.swift
```

建议协议形态：

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

第一阶段不要强制所有 Feature 完全重写。可以先让 Feature 作为现有 Manager 的薄包装：

```swift
@MainActor
final class ThermalFeature: CalmFeature {
    private let monitor = ThermalMonitor.shared

    func start() {
        monitor.startPolling()
    }

    func stop() {
        monitor.stopPolling()
        monitor.restoreSystemControl()
    }

    func cleanup() {
        monitor.restoreSystemControl()
    }
}
```

### 4.2 Service Layer

建议新增目录：

```text
app/Sources/CalmBar/Services/
├── ServiceError.swift
├── HelperService.swift
├── FanService.swift
├── ThermalService.swift
├── BatteryService.swift
├── PowerAssertionService.swift
├── ClipboardService.swift
├── OCRService.swift
├── CleanerService.swift
├── GatekeeperService.swift
├── InputDeviceService.swift
└── SystemService.swift
```

Service 的第一阶段目标是“抽出可复用门面”，不是消灭 Manager。

示例迁移关系：

| 当前类 | 2.0 初期改造 | 目标 |
| --- | --- | --- |
| `ThermalMonitor` | 内部调用 `ThermalService` / `FanService` | 保留 ObservableObject 状态 |
| `BatteryChargeManager` | 内部调用 `BatteryService` | 策略与 SMC 操作分离 |
| `CaffeineManager` | 内部调用 `PowerAssertionService` | 电源断言可复用 |
| `OCRManager` | 内部调用 `OCRService` | Vision 识别与 UI 调度分离 |
| `ClipboardMonitor` | 内部调用 `ClipboardService` | 监听、过滤、持久化逐步拆分 |
| `GatekeeperManager` | 内部调用 `GatekeeperService` | 提权命令统一走 HelperService |
| `CleanerManager` | 内部调用 `CleanerService` | 扫描、匹配、删除流程可测试 |

### 4.3 Command Layer

2.0 需要引入 Command Palette，但不要一开始做复杂插件系统。

建议新增目录：

```text
app/Sources/CalmBar/Commands/
├── CommandCenter.swift
├── CommandDescriptor.swift
├── CommandCategory.swift
├── CommandContext.swift
├── CommandResult.swift
└── CommandPaletteView.swift
```

Command 的来源有两类：

1. 系统命令：打开设置、刷新权限、显示主面板、退出 App。
2. Feature 命令：OCR 截屏、开启防休眠、切换滚轮、打开剪贴板、清理扫描、临时充满等。

建议命令模型：

```swift
public struct CommandDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: CommandCategory
    public let requiredPermissions: [PermissionType]
    public let run: @MainActor () async -> CommandResult
}
```

Command Palette 的产品作用：

1. 让功能数量增加时，首页仍保持简洁。
2. 给低频功能一个统一发现入口。
3. 让快捷键、菜单项、搜索结果复用同一套命令描述。
4. 让“权限不足”“功能不可用”“执行失败”有统一反馈。

### 4.4 Permission Layer

当前已有 `PermissionManager` 和 `PermissionType`，2.0 应保留并增强它，而不是新建另一套权限中心。

建议优化方向：

1. 从“全局权限列表”扩展为“权限与 Feature 关系”。
2. 每个 Feature 声明所需权限。
3. Permission Center 展示哪些功能依赖该权限。
4. Command Palette 执行命令前统一检查权限。
5. 权限缺失时支持降级，而不是只有失败。

示例：

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

权限关系建议：

| 权限 | 依赖功能 | 缺失时行为 |
| --- | --- | --- |
| Accessibility | Scroll、Caffeine Keep Apps Active | 禁用对应开关，保留说明和授权入口 |
| Privileged Helper | Thermal Fan、Battery Limit、Gatekeeper Deep Fix | 降级为只读状态或提示激活 Helper |
| Screen Recording | OCR 截屏 | 禁用截屏命令，保留历史查看 |
| Full Disk Access | Cleaner 深层扫描 | 允许普通扫描，提示深层扫描需要授权 |

### 4.5 Recovery Layer

当前恢复逻辑分散在 `AppDelegate.cleanup()`、`SystemEventCoordinator`、`CalmBarHelperMain` 的 XPC 失效处理里。2.0 建议新增统一 Recovery Coordinator。

建议新增目录：

```text
app/Sources/CalmBar/Recovery/
├── RecoveryCoordinator.swift
├── RecoveryAction.swift
├── RecoveryReason.swift
└── RecoveryAuditLog.swift
```

Recovery 负责：

1. App 退出时恢复风扇自动控制。
2. App 退出时恢复默认充电。
3. 系统睡眠前恢复风扇和充电。
4. Helper 连接断开时恢复底层状态。
5. Feature 停用时执行对应清理。
6. 记录最近恢复动作，方便排查。

Recovery 第一阶段可以只是把现有清理动作集中包装：

```swift
@MainActor
final class RecoveryCoordinator {
    static let shared = RecoveryCoordinator()

    func performEmergencyRecovery(reason: RecoveryReason) {
        ThermalMonitor.shared.restoreSystemControl()
        BatteryChargeManager.shared.restoreDefaultCharging()
        CaffeineManager.shared.cleanupOnExit()
        ScrollReverserManager.shared.stop()
        ClipboardMonitor.shared.stopMonitoring()
    }
}
```

后续再逐步变成 Feature 注册式恢复。

---

## 5. 首页与入口优化

### 5.1 当前风险

`PopoverContentView` 现在直接观察多个 Manager：

```swift
@ObservedObject private var thermal = ThermalMonitor.shared
@ObservedObject private var settings = AppSettings.shared
@ObservedObject private var menuBar = MenuBarOrganizer.shared
@ObservedObject private var scroll = ScrollReverserManager.shared
@ObservedObject private var helper = HelperClient.shared
@ObservedObject private var caffeine = CaffeineManager.shared
@ObservedObject private var batteryMonitor = BatteryMonitor.shared
@ObservedObject private var chargeManager = BatteryChargeManager.shared
@ObservedObject private var ocr = OCRManager.shared
@ObservedObject private var ocrHistory = OCRHistoryManager.shared
@ObservedObject private var clipboardHistory = ClipboardHistoryManager.shared
```

功能继续增加后，首页会越来越难维护。

### 5.2 2.0 首页原则

首页应该从“展示所有功能”转为“展示当前最重要状态 + 高频动作”：

1. 顶部：全局状态、温度、电池、权限异常。
2. 中部：3 到 5 个高频 Quick Actions。
3. 底部：Command Palette、设置、更多工具。
4. 低频工具进入分类页或独立窗口。

### 5.3 建议首页结构

```text
Popover
├── Header
│   ├── CalmBar 状态
│   ├── 温度摘要
│   └── 风险提示
├── Dashboard
│   ├── Thermal Summary
│   ├── Battery Summary
│   └── Permission Warning
├── Quick Actions
│   ├── OCR
│   ├── Clipboard
│   ├── Caffeine
│   ├── Command Palette
│   └── Settings
└── Footer
    ├── Helper 状态
    └── 版本/设置入口
```

### 5.4 Feature Dashboard

Feature 可以提供轻量 Dashboard Item：

```swift
public struct FeatureDashboardItem: Identifiable {
    public let id: String
    public let featureID: FeatureID
    public let title: String
    public let value: String
    public let status: FeatureState
    public let action: FeatureCommand?
}
```

这样 `PopoverContentView` 不需要直接关心每个 Manager 的内部状态，而是消费 `FeatureManager.dashboardItems`。

---

## 6. 目录演进建议

2.0 不要求一次性移动所有文件。建议分三步调整。

### 6.1 第一阶段：只新增基础目录

```text
app/Sources/CalmBar/
├── Features/
├── Services/
├── Commands/
└── Recovery/
```

现有目录保持不动。

### 6.2 第二阶段：新增功能优先使用新结构

新功能不再直接新增一个独立 Manager，而是按以下结构进入：

```text
NewFeature/
├── NewFeature.swift
├── NewFeatureService.swift
├── NewFeatureModels.swift
├── NewFeatureSettingsView.swift
└── NewFeatureDashboardView.swift
```

如果功能较大，再拆为：

```text
FeatureName/
├── Feature/
├── Services/
├── Models/
├── Views/
└── Tests/
```

### 6.3 第三阶段：成熟模块再内聚迁移

当某个模块稳定后，再考虑把散落文件内聚到统一目录。例如 Cleaner 已经较大，可以保持当前结构，不必急着移动。迁移只在满足以下条件时进行：

1. 文件移动能明显减少 import 和交叉依赖。
2. 测试覆盖足够。
3. 本阶段没有高风险功能正在开发。
4. 移动后不会影响打包脚本和资源路径。

---

## 7. 分阶段路线图

### Phase 0：架构冻结与边界标注

目标：不改行为，只明确边界。

工作项：

1. 补充 2.0 架构文档。
2. 标注当前 Manager 与未来 Feature / Service 的对应关系。
3. 列出每个功能的权限、生命周期、恢复动作。
4. 明确 Helper 能力边界。
5. 补充 README 中的架构说明链接。

验收标准：

1. 文档能指导后续新增功能。
2. 不产生运行时行为变化。
3. 没有大规模文件移动。

### Phase 1：FeatureManager 薄封装

目标：新增统一 Feature 注册表，但现有 Manager 继续工作。

工作项：

1. 新增 `FeatureID`、`FeatureCategory`、`FeatureState`。
2. 新增 `CalmFeature` 协议。
3. 新增 `FeatureManager.shared`。
4. 为现有功能建立薄包装：
   - `ThermalFeature`
   - `BatteryFeature`
   - `CaffeineFeature`
   - `ClipboardFeature`
   - `OCRFeature`
   - `CleanerFeature`
   - `ScrollFeature`
   - `NoTunesFeature`
   - `GatekeeperFeature`
   - `MenuBarFeature`
5. `AppDelegate` 从手工启动 Manager 逐步变为启动 `FeatureManager`。

验收标准：

1. App 启动行为与当前一致。
2. 退出时恢复逻辑仍然可靠。
3. 单个 Feature 可单独 `start()` / `stop()`。
4. 测试不因包装层引入行为变化。

### Phase 2：Permission 与 Feature 绑定

目标：让权限中心知道“权限服务于哪些功能”。

工作项：

1. 新增 `FeaturePermissionRequirement`。
2. 每个 Feature 声明权限依赖。
3. `PermissionManager` 增加按 Feature 查询权限状态的能力。
4. Permission Center 展示权限影响范围。
5. Quick Action 和 Command 执行前统一检查权限。

验收标准：

1. 用户能看懂每个权限的用途。
2. 权限缺失时对应功能有明确降级状态。
3. 不再在多个 UI 组件里重复写权限说明。

### Phase 3：Service Layer 抽离

目标：把系统 API、Helper 调用和业务策略逐步拆开。

优先级建议：

1. `HelperService`
   - 包装 `HelperClient` 的 XPC 调用。
   - 提供统一错误类型。
   - 避免业务层直接拼接 Helper 操作细节。
2. `FanService`
   - 包装 `FanController` 和 Helper fallback。
   - 让 `ThermalMonitor` 聚焦状态和策略。
3. `BatteryService`
   - 包装 `SMCBattery` / `BatteryMonitor` / Helper 电池控制。
   - 让 `BatteryChargeManager` 聚焦策略状态机。
4. `OCRService`
   - 抽出 Vision 识别流程。
   - UI 和历史管理只处理结果。
5. `CleanerService`
   - 抽出扫描、估算、移动废纸篓、权限降级。

验收标准：

1. Manager 代码体积下降。
2. Service 可单测。
3. Helper 失败、权限缺失、硬件不支持等错误有统一表达。
4. UI 不直接调用底层系统命令。

### Phase 4：Command Palette

目标：让功能数量增加时，用户仍能快速发现和执行功能。

工作项：

1. 新增 `CommandCenter`。
2. 每个 Feature 暴露 `commands`。
3. 新增 `CommandPaletteView`。
4. 支持搜索标题、别名、分类。
5. 支持键盘导航。
6. 支持权限缺失提示和跳转授权。
7. 支持常用命令置顶。

首批命令建议：

1. 开始 OCR 选区识别。
2. 打开 OCR 历史。
3. 打开剪贴板历史。
4. 开启/关闭防休眠。
5. 临时充至 100%。
6. 切换滚轮反转。
7. 展开/折叠菜单栏。
8. 扫描应用残留。
9. 扫描开发缓存。
10. 打开权限中心。

验收标准：

1. 功能入口不依赖首页堆叠。
2. 新增 Feature 时只需注册命令即可被发现。
3. 命令执行结果有统一反馈。

### Phase 5：Dashboard 精简

目标：把菜单栏首页变成轻量 Dashboard，而不是完整设置面板。

工作项：

1. 提取 `DashboardViewModel`。
2. 将首页模块改为消费 Feature 摘要。
3. 将复杂配置迁移到 Settings 或独立窗口。
4. 保留少量高频 Quick Actions。
5. 新增用户自定义首页项目排序与显示。

验收标准：

1. `PopoverContentView` 不再直接观察十多个 Manager。
2. 首页宽度、复杂度和心智负担下降。
3. 新功能默认不进入首页，除非被明确标记为 dashboard item。

### Phase 6：Recovery 统一化

目标：确保系统级功能在任何退出路径上可恢复。

工作项：

1. 新增 `RecoveryCoordinator`。
2. 将 `AppDelegate.cleanup()` 改为调用 Recovery。
3. `SystemEventCoordinator` 睡眠事件改为调用 Recovery。
4. Helper XPC 断开时记录恢复原因。
5. 增加恢复动作日志。

验收标准：

1. 风扇、充电、防休眠、滚轮拦截均有退出清理。
2. 睡眠、退出、崩溃恢复路径清晰。
3. 用户可在设置页看到最近一次安全恢复记录。

### Phase 7：新增功能平台化

目标：后续新增工具统一遵循 Feature / Service / Command / Permission 模板。

候选功能：

1. 网络工具。
2. DNS 工具。
3. Wi-Fi 工具。
4. 显示器工具。
5. 音频工具。
6. 文件工具。
7. 开发环境诊断。
8. 快捷操作。
9. 系统信息。

新增功能准入要求：

1. 必须有 Feature 声明。
2. 必须有权限声明。
3. 必须暴露 Command。
4. 必须声明恢复策略。
5. 必须有基础测试或可验证手册。

---

## 8. 当前模块改造建议

### 8.1 Thermal / Fan

现状：

1. `ThermalMonitor` 同时负责 SMC 初始化、轮询、温度状态、风扇策略、Helper fallback。
2. `FanController` 和 `SafetyPolicy` 已在 `CalmBarKit`，应保留。

建议：

1. 保留 `ThermalMonitor` 作为 UI 可观察状态。
2. 新增 `ThermalFeature` 管生命周期。
3. 新增 `FanService` 管写入风扇、恢复自动、Helper fallback。
4. 新增 `ThermalService` 管温度读取。
5. `SafetyPolicy` 继续留在 `CalmBarKit`。

优先收益：

1. 温控策略更容易测试。
2. Helper 不可用时的降级更清晰。
3. Dashboard 可以直接消费 Feature 摘要。

### 8.2 Battery

现状：

1. `BatteryChargeManager` 已经具备较清晰的状态机。
2. SMC 写入通过 `HelperClient` 完成。
3. `BatteryMonitor` 和 `BatteryChargeManager` 职责仍有交叉。

建议：

1. 保留 `BatteryChargeManager` 的策略状态机。
2. 新增 `BatteryService` 封装 SMC 操作与硬件支持检测。
3. 将 `applyInhibition` / `applyForceDischarge` 逐步下沉到 Service。
4. `BatteryFeature` 声明 Helper 权限、Dashboard 摘要和 Command。

优先收益：

1. 电池安全策略更容易复用。
2. Helper 错误和硬件不支持能统一显示。
3. Top Up、Sailing、Limit 都能成为 Command。

### 8.3 Clipboard

现状：

1. Clipboard 模块已经拆出 Models、Core、History、SecurityFilter。
2. 功能复杂度较高，适合先纳入 Feature，不急于重构内部。

建议：

1. 新增 `ClipboardFeature`，只包装启动、停止、打开历史、清空历史等动作。
2. 新增 `ClipboardService` 时优先封装粘贴板读写、内容归一化和敏感过滤。
3. OCR 后台索引可后续与 `OCRService` 共享能力。

优先收益：

1. Clipboard 可以从首页挪到 Command Palette 和独立窗口。
2. 隐私过滤可以与权限中心、隐私说明联动。

### 8.4 OCR

现状：

1. OCR 已有 `OCRManager`、`OCRHistoryManager`、`ScreenCaptureUtility`、Floating Preview。
2. 权限依赖是 Screen Recording。

建议：

1. 新增 `OCRFeature`。
2. 新增 `OCRService` 封装 Vision 文本和条码识别。
3. 截屏权限缺失时允许查看历史，但禁用新识别命令。
4. OCR 命令进入 Command Palette，减少首页拥挤。

优先收益：

1. OCR 可被 Clipboard 图片索引复用。
2. Vision 识别逻辑更容易测试和性能分析。

### 8.5 Cleaner

现状：

1. Cleaner 已经是较大的模块，包含 AppCleaner、DevCleaner、Models、UI。
2. Full Disk Access 是可选增强权限。

建议：

1. 保留现有 Cleaner 目录结构。
2. 新增 `CleanerFeature`，统一命令和权限声明。
3. 新增 `CleanerService` 聚合扫描、估算、删除、降级策略。
4. 普通权限下允许扫描用户可读路径；Full Disk Access 缺失时提示深层扫描不完整。

优先收益：

1. Cleaner 不挤占菜单栏首页。
2. 扫描能力可以作为 Command 触发。
3. 权限缺失时的解释更可信。

### 8.6 Caffeine

现状：

1. Caffeine 已有防休眠和 Activity Simulator。
2. 它同时依赖 IOKit 和辅助功能权限。

建议：

1. 新增 `CaffeineFeature`。
2. 新增 `PowerAssertionService`。
3. 将 Keep Apps Active 作为 Caffeine 的高级子能力。
4. 缺少 Accessibility 时只禁用微动，不影响基础防休眠。

优先收益：

1. 权限降级更自然。
2. 睡眠/锁屏/退出恢复策略更统一。

### 8.7 Scroll

现状：

1. Scroll Reverser 依赖 CGEventTap 和 Accessibility。
2. 属于典型后台事件能力。

建议：

1. 新增 `ScrollFeature`。
2. 新增 `InputDeviceService` 或 `ScrollEventService`。
3. `ScrollFeature` 暴露启停和方向切换命令。
4. 权限缺失时显示授权入口。

### 8.8 NoTunes

现状：

1. NoTunes 基于系统应用生命周期通知。
2. 权限需求低，适合作为轻量 Feature 模板。

建议：

1. 新增 `NoTunesFeature`，作为 Feature 迁移的低风险试点。
2. 暴露启停和替代目标打开命令。
3. 保持现有 `NoTunesManager` 不动。

### 8.9 Gatekeeper

现状：

1. Gatekeeper 通过 Helper 执行 `xattr` 和 `codesign`。
2. 属于高风险系统命令能力。

建议：

1. 新增 `GatekeeperFeature`。
2. 新增 `GatekeeperService`，统一命令执行结果。
3. Helper 只执行已明确传入的路径和参数，不理解产品逻辑。
4. UI 必须展示目标路径、操作类型、失败原因。

---

## 9. Helper 边界规范

### 9.1 Helper 可以做

1. `FanController` 写入风扇目标。
2. 恢复风扇 Auto。
3. `SMCBattery` 写入充电阻断和强制放电。
4. 读取 SMC 支持状态。
5. 对指定路径执行去隔离。
6. 对指定路径执行 Ad-hoc 自签名。
7. 未来必要的 root 权限系统命令。

### 9.2 Helper 不应该做

1. 不保存用户设置。
2. 不决定 Feature 是否启用。
3. 不判断 UI 展示。
4. 不做 OCR、Clipboard、Cleaner 的业务编排。
5. 不扫描用户文件系统并作复杂产品判断。
6. 不持久化历史记录。

### 9.3 XPC 协议演进原则

1. 优先添加小而明确的方法。
2. 不传 SwiftUI 或 App 层模型。
3. 参数必须可序列化、可验证。
4. 返回统一错误字符串或后续升级为错误结构。
5. 所有破坏性或高权限操作必须由 App 层先完成用户确认。

---

## 10. 设置与持久化优化

当前 `AppSettings` 很完整，但字段继续增加后会变成全局配置大类。

2.0 建议：

1. 短期保留 `AppSettings.shared`。
2. 新增 `FeatureSettingsKey` 或分组访问方法。
3. 新 Feature 的设置字段必须写入明确分区。
4. Settings UI 按 Feature 分类读取设置。
5. 后续再考虑拆成多个 Settings Store。

推荐演进：

```text
Phase 1: AppSettings 继续作为唯一 UserDefaults 门面
Phase 2: 每个 Feature 声明使用哪些 settings keys
Phase 3: SettingsView 通过 Feature 列表生成分类入口
Phase 4: 高复杂模块再拆分独立 SettingsStore
```

不要一开始就拆 `AppSettings`，因为它现在是很多功能的稳定连接点。

---

## 11. 测试策略

当前项目已有多类测试：

1. `FanCurveTests`
2. `BatterySafetyTests`
3. `ClipboardTests`
4. `OCRTests`
5. `CleanerTests`
6. `GatekeeperTests`
7. `ScrollClassificationTests`
8. `SMCTests`
9. `PopoverVisibilitySettingsTests`

2.0 应补充以下测试类型：

### 11.1 Feature 测试

1. Feature 注册数量正确。
2. Feature ID 唯一。
3. Feature 权限声明正确。
4. Feature Command 不重复。
5. Feature 停止时调用清理动作。

### 11.2 Service 测试

1. Service 错误映射。
2. Helper 不可用时的降级。
3. 硬件不支持时的状态。
4. 权限缺失时的返回结果。

### 11.3 Recovery 测试

1. App 退出触发恢复。
2. 睡眠前触发恢复。
3. Feature 停用触发恢复。
4. 重复恢复动作幂等。

### 11.4 Command 测试

1. 命令搜索。
2. 权限拦截。
3. 执行结果。
4. Command 与 Feature 关系。

---

## 12. 2.0 最小可交付范围

CalmBar 2.0 不必一次完成所有改造。建议最小可交付范围是：

1. `FeatureManager` 已接管 App 启动列表。
2. 所有现有功能都有 Feature 包装。
3. 权限中心能展示权限影响的功能。
4. Command Palette 可执行首批 8 到 10 个命令。
5. `RecoveryCoordinator` 接管退出和睡眠恢复。
6. 首页减少直接观察的 Manager 数量。
7. Helper 边界文档化，并保持现有 XPC 能力稳定。

---

## 13. 推荐实施顺序

最推荐的顺序：

1. 文档冻结：确认本方案中的边界和术语。
2. 建立 Feature 基础类型，不改行为。
3. 为 NoTunes、Scroll、Caffeine 做低风险 Feature 包装。
4. 为 Thermal、Battery 做 Feature 包装，但保留原 Manager。
5. 建立 Permission 与 Feature 的映射。
6. 建立 CommandCenter 和 Command Palette。
7. 抽 HelperService、FanService、BatteryService。
8. 首页改造为 Dashboard + Quick Actions。
9. RecoveryCoordinator 接管恢复路径。
10. 新功能强制走 Feature 模板。

不推荐的顺序：

1. 一开始移动大量文件。
2. 一开始删除 Manager 单例。
3. 一开始重写 `AppSettings`。
4. 一开始重写 Helper。
5. 一开始把 Command Palette 做成插件系统。

---

## 14. 风险与控制

### 14.1 风险：抽象层增加但行为没有改善

控制方式：

1. 每一层都必须对应实际问题。
2. 没有复用价值的 Service 不抽。
3. Feature 第一阶段只做薄包装。

### 14.2 风险：系统级能力回归

控制方式：

1. SMC、Helper、XPC 不大改。
2. Thermal 和 Battery 改造必须保留恢复测试。
3. 所有恢复动作保持幂等。

### 14.3 风险：首页变得过度复杂

控制方式：

1. 首页只放摘要和高频动作。
2. 设置放 Settings。
3. 低频动作放 Command Palette。

### 14.4 风险：新功能继续无序增长

控制方式：

1. 新功能必须声明 Feature。
2. 新功能必须声明权限。
3. 新功能必须注册 Command。
4. 新功能必须说明 Recovery 行为。

---

## 15. 结论

CalmBar 2.0 的核心不是“重构成一个漂亮架构”，而是让当前已经成型的 macOS 工具集合具备长期扩展能力。

现有 `CalmBarKit + CalmBarHelper + XPC + SMC` 是项目最有价值的底座，应该保留。2.0 的优化重点应放在外层组织机制：

1. 用 Feature 管“做什么”。
2. 用 Service 管“怎么做”。
3. 用 Command Palette 管“如何发现和执行”。
4. 用 Permission 管“为什么要授权，以及授权影响什么”。
5. 用 Recovery 管“出问题时如何安全回到系统默认状态”。

这样 CalmBar 可以继续增加功能，同时不把菜单栏首页、AppDelegate、AppSettings 和 Helper 变成无法维护的巨型入口。
