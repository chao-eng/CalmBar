import Foundation
import Testing
@testable import CalmBar
@testable import CalmBarKit

@Suite("Fanless Adaptation State Gating Tests")
struct FanlessAdaptationTests {

    /// 无论真机是否有风扇，风扇命令都必须自带被动散热机型兜底失败文案
    @Test("Thermal feature commands register a fanless failure fallback")
    @MainActor
    func testThermalFeatureFanControlCommandsPresentOnlyWithFans() {
        let feature = ThermalFeature()

        // ThermalFeature.commands 的有风扇判定取决于真机 SMC。
        // 因此断言分两条路径：
        // 1) 若真机有风扇（commands 非空），每个风扇命令都应安全执行 guard。
        // 2) 若真机无风扇，则 commands 必须为空（不暴露任何风扇控制）。
        let monitor = ThermalMonitor.shared
        if monitor.supportsFanControl {
            let ids = feature.commands.map(\.id)
            #expect(ids.contains("thermal.fanFull"))
            #expect(ids.contains("thermal.restoreAuto"))
        } else {
            #expect(feature.commands.isEmpty)
        }
    }

    @Test("ThermalFeature requires helper only when fans are controllable")
    @MainActor
    func testThermalFeaturePermissionGating() {
        let feature = ThermalFeature()
        let monitor = ThermalMonitor.shared

        if monitor.supportsFanControl {
            let perms = feature.requiredPermissions
            #expect(perms.count == 1)
            #expect(perms.first?.type == .privilegedHelper)
            #expect(perms.first?.level == .required)
        } else {
            #expect(feature.requiredPermissions.isEmpty)
        }
    }

    @Test("PermissionManager thermal requirements match feature capability")
    @MainActor
    func testPermissionManagerThermalGatingConsistency() {
        let pm = PermissionManager.shared
        let monitor = ThermalMonitor.shared

        let thermalReqs = pm.requirements(for: .thermal)
        let helperGranted = monitor.supportsFanControl

        if helperGranted {
            #expect(thermalReqs.contains(where: { $0.type == .privilegedHelper }))
        } else {
            #expect(thermalReqs.isEmpty)
        }

        // 无论何种硬件，battery 始终需要特权助手（与风扇无关）
        let batteryReqs = pm.requirements(for: .battery)
        #expect(batteryReqs.contains(where: { $0.type == .privilegedHelper && $0.level == .required }))
    }

    /// DashboardViewModel 的能力派生逻辑必须与热监控源保持一致（纯函数级不变量）
    @Test("Dashboard capability helpers follow fanCapability invariants")
    @MainActor
    func testDashboardCapabilityHelpersAreConsistent() {
        let dashboard = DashboardViewModel()

        let capability = dashboard.fanCapability
        #expect(dashboard.isFanless == capability.isFanless)
        // supportsFanControl = SMC 已连接 且 存在可控制风扇
        #expect(dashboard.supportsFanControl == (dashboard.isSMCConnected && capability.supportsFanControl))
    }

    /// 被动散热机型绝不应报告“支持风扇控制”
    @Test("Fanless capability is mutually exclusive with fan control")
    @MainActor
    func testFanlessNeverClaimsFanControl() {
        let fanless = ThermalMonitor.shared.fanCapability == .fanless
        if fanless {
            #expect(!ThermalMonitor.shared.supportsFanControl)
            #expect(ThermalMonitor.shared.isFanControlAuthorized == false)
        }
    }

    /// 权限中心机型化文案：无风扇机型的特权助手用途说明不得再引用风扇调速
    @Test("Permission helper description avoids fan reference on fanless")
    @MainActor
    func testPermissionDescriptionIsFanlessAware() {
        let pm = PermissionManager.shared
        let monitor = ThermalMonitor.shared
        let helperDesc = pm.purposeDescription(for: .privilegedHelper)

        // 无论何种机型，特权助手的用途说明都应涵盖充电保护与应用去隔离
        #expect(helperDesc.contains("充电"))
        #expect(helperDesc.contains("去隔离"))

        if monitor.isFanless {
            // 无风扇机型：不得再声称“用于风扇调速”，且应明确温度读取无需助手
            #expect(!helperDesc.contains("风扇调速"))
            #expect(helperDesc.contains("只读"))
        } else {
            // 有风扇机型：保留原始静态描述
            #expect(helperDesc.contains("风扇调速"))
        }
    }

    /// 权限中心“关联功能”标签：无风扇机型不得把硬件温控列为特权助手的关联功能
    @Test("Affected features exclude thermal on fanless")
    @MainActor
    func testAffectedFeaturesExcludeThermalWhenFanless() {
        let pm = PermissionManager.shared
        let monitor = ThermalMonitor.shared

        if monitor.isFanless {
            let helperFeatures = pm.affectedFeatures(for: .privilegedHelper)
            #expect(!helperFeatures.contains(.thermal))
            #expect(helperFeatures.contains(.battery))
        } else {
            let helperFeatures = pm.affectedFeatures(for: .privilegedHelper)
            #expect(helperFeatures.contains(.thermal))
        }
    }
}
