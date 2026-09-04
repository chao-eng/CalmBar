import Foundation
import Testing
@testable import CalmBar
@testable import CalmBarKit

/// 无风扇仿真回归套件 —— 仅在设置了 `CALMBAR_SIMULATE_FANLESS=1` 时断言无风扇降级链路，
/// 用于在无 MacBook Air 真机的开发机上确定性验证 fanless 行为。
///
/// 运行方式：
///   CALMBAR_SIMULATE_FANLESS=1 swift test --filter FanlessSimulationTests
///
/// 注意：本套件与全量既有测试互斥（不可带环境变量跑全量，否则 CommandCenter /
/// PermissionFeature 等“有风扇”假设测试会翻车）。
@Suite("Fanless Simulation Regression Tests")
struct FanlessSimulationTests {

    private var isSimulated: Bool {
        (ProcessInfo.processInfo.environment["CALMBAR_SIMULATE_FANLESS"]?.lowercased() == "1"
            || ProcessInfo.processInfo.environment["CALMBAR_SIMULATE_FANLESS"]?.lowercased() == "true"
            || ProcessInfo.processInfo.environment["CALMBAR_SIMULATE_FANLESS"]?.lowercased() == "yes")
    }

    @Test("Simulation flag resolves to fanless when env present")
    @MainActor
    func testOverrideResolvesToFanless() {
        if !isSimulated { return } // 未在仿真态运行时跳过（无断言即通过）
        #expect(FanCapabilitySimulation.resolvedOverride() == .fanless)
    }

    @Test("ThermalMonitor reports fanless under simulation")
    @MainActor
    func testMonitorReportsFanless() {
        if !isSimulated { return }
        let monitor = ThermalMonitor.shared
        #expect(monitor.fanCapability == .fanless)
        #expect(monitor.isFanless)
        #expect(!monitor.supportsFanControl)
        #expect(!monitor.requiresHelperForThermal)
        #expect(monitor.fanSnapshots.isEmpty)
    }

    @Test("ThermalFeature exposes no fan commands nor helper requirement under simulation")
    @MainActor
    func testFeatureGatesUnderSimulation() {
        if !isSimulated { return }
        let feature = ThermalFeature()
        #expect(feature.commands.isEmpty)
        #expect(feature.requiredPermissions.isEmpty)
        #expect(feature.state == .running)
    }

    @Test("PermissionManager excludes thermal helper requirement under simulation")
    @MainActor
    func testPermissionManagerUnderSimulation() {
        if !isSimulated { return }
        let pm = PermissionManager.shared
        #expect(pm.requirements(for: .thermal).isEmpty)

        let helperFeatures = pm.affectedFeatures(for: .privilegedHelper)
        #expect(!helperFeatures.contains(.thermal))

        let helperDesc = pm.purposeDescription(for: .privilegedHelper)
        #expect(helperDesc.contains("充电"))
        #expect(helperDesc.contains("去隔离"))
        // 不再把“风扇调速”描述为助手职责，并明确温度读取无需助手
        #expect(!helperDesc.contains("SMC 风扇调速"))
        #expect(helperDesc.contains("只读"))
        #expect(helperDesc.contains("无需风扇调速"))
    }

    @Test("CommandCenter does not register fan commands under simulation")
    @MainActor
    func testCommandCenterUnderSimulation() {
        if !isSimulated { return }
        let center = CommandCenter()
        #expect(center.command(id: "thermal.restoreAuto") == nil)
        #expect(center.command(id: "thermal.fanFull") == nil)
    }
}
