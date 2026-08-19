# CalmBar 新功能接入规范与模板

> 本文档用于指导开发者和 AI Agent 为 CalmBar 平台新增工具或模块，确保所有新能力遵循统一的 Feature、Service、Permission、Command 与 Recovery 规范，不破坏底层硬件稳定性与首页交互体验。

---

## 1. 新功能设计 10 项准入原则

为 CalmBar 新增任何功能前，必须明确以下 10 项要素：

1. **Feature 元信息**：功能名称、唯一 ID（`FeatureID`）、归属分类（`FeatureCategory`）。
2. **Feature 分类**：系统控制 (`system`)、硬件安全 (`hardware`)、效率工具 (`productivity`)、输入交互 (`input`)、安全权限 (`security`)、空间清理 (`cleanup`)。
3. **Service 边界**：底层 API、XPC 或系统命令必须封装在 `Services/` 中，不直接在 UI 或 Feature 中裸写底层调用。
4. **权限声明**：是否需要系统权限（辅助功能、屏幕录制、特权助手、完全磁盘访问），缺失时是否支持优雅降级。
5. **Command 注册**：向 `CommandCenter` 注册至少 1 个可执行命令与中文别名，支持 Command Palette 快速搜索。
6. **Dashboard 准入**：默认**不直接塞进主菜单栏首页**，仅高频状态或 Quick Action 可进 Dashboard，其余通过独立窗口或设置页承载。
7. **Settings 项**：在 `AppSettings` 中定义偏好字段并在 `SettingsView` 的对应 Tab 中提供可视化配置。
8. **Recovery 恢复行为**：如果功能涉及底层拦截、进程监控、电源断言或硬件写入，必须实现 `cleanup()` 与统一恢复动作。
9. **测试清单**：必须包含数据模型单测与核心逻辑单元测试（使用 Swift Testing 框架）。
10. **用户可见失败状态**：错误必须通过 `ServiceError` 或 UI 明确告知，严禁在异常时静默失败。

---

## 2. 标准代码模板

### 2.1 步骤一：注册 FeatureID 与 Category

在 `app/Sources/CalmBar/Features/FeatureID.swift` 中追加枚举值：

```swift
public enum FeatureID: String, CaseIterable, Identifiable, Sendable {
    // ... 现有项 ...
    case myNewTool = "myNewTool"
}
```

---

### 2.2 步骤二：创建 Service 业务能力层

在 `app/Sources/CalmBar/Services/MyNewToolService.swift`：

```swift
import Foundation

@MainActor
public final class MyNewToolService {
    public static let shared = MyNewToolService()

    public init() {}

    public func performAction() async throws -> String {
        // 底层逻辑实现，例如调用系统 API 或 HelperService
        return "执行结果"
    }
}
```

---

### 2.3 步骤三：实现 CalmFeature 协议

在 `app/Sources/CalmBar/Features/MyNewToolFeature.swift`：

```swift
import Combine
import Foundation

@MainActor
public final class MyNewToolFeature: CalmFeature {
    public let id: FeatureID = .myNewTool
    public let title: String = "新工具名称"
    public let category: FeatureCategory = .productivity
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        // 若不需要权限可为空数组 []
        FeaturePermissionRequirement(
            type: .accessibility,
            level: .required,
            reason: "此功能需要辅助功能权限用于系统交互"
        )
    ]

    private let service: MyNewToolService
    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "myNewTool.action",
                title: "执行新工具操作",
                action: { [weak self] in
                    Task {
                        _ = try? await self?.service.performAction()
                    }
                }
            )
        ]
    }

    public init(service: MyNewToolService = .shared) {
        self.service = service
    }

    public func start() {
        state = .running
    }

    public func stop() {
        state = .disabled
    }

    public func cleanup() {
        stop()
    }
}
```

---

### 2.4 步骤四：在 FeatureManager 与 CommandCenter 注册

1. 在 `FeatureManager.swift` 的 `registerDefaultFeatures()` 中追加：

```swift
register(MyNewToolFeature())
```

2. 在 `CommandCenter.swift` 的 `registerBuiltInCommands()` 中追加命令：

```swift
register(CommandDescriptor(
    id: "myNewTool.action",
    title: "执行新工具操作",
    subtitle: "新工具的一句话描述",
    iconName: "wand.and.stars",
    category: .productivity,
    featureID: .myNewTool,
    requiredPermissions: [.accessibility],
    aliases: ["newtool", "xgg"],
    run: {
        do {
            let msg = try await MyNewToolService.shared.performAction()
            return .success(msg)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
))
```

---

### 2.5 步骤五：编写单元测试

在 `app/Tests/CalmBarTests/MyNewToolTests.swift`：

```swift
import Foundation
import Testing
@testable import CalmBar

@Suite("MyNewTool Module Tests")
struct MyNewToolTests {
    @Test("Test MyNewTool Feature registration and state")
    @MainActor
    func testFeatureState() {
        let feature = MyNewToolFeature()
        #expect(feature.id == .myNewTool)
        #expect(feature.title == "新工具名称")
        #expect(feature.category == .productivity)
    }
}
```

---

## 3. 未来候选功能准入清单

以下为 CalmBar 2.0 平台规划中的高价值候选扩展方向：

| 模块名称 | 归属分类 | 依赖权限 | 说明 |
| --- | --- | --- | --- |
| **网络延迟与测速 (NetworkPing)** | Productivity | 无 | 菜单栏实时显示 DNS 延迟、公网 IP 与快捷 ping 诊断 |
| **DNS 切换与刷新 (DNSFlush)** | System | Privileged Helper (可选) | 一键刷新本地 DNS 缓存 (`dscacheutil`)，切换公共 DNS |
| **Wi-Fi 强力分析 (WiFiAnalyzer)** | System | Location (macOS Wi-Fi 扫描需要) | 扫描信道拥堵度、信号强度 (RSSI) 与当前握手速率 |
| **显示器亮度与 DDC 调光 (DisplayDDC)** | Hardware | 无 / IOKit | 外接显示器免按键软件 DDC/CI 亮度和对比度无级调节 |
| **应用音量独立控制 (AudioRouter)** | System | CoreAudio Plugin | 为不同应用独立调节输出音量 |
| **系统信息看板 (SystemInfo)** | Hardware | SMC / IOKit | 详细展示芯片核心频率、显存占用、NVMe 写入量与电池充放电曲线 |
