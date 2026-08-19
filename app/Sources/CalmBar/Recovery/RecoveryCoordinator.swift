import Combine
import Foundation

@MainActor
public final class RecoveryCoordinator: ObservableObject {
    public static let shared = RecoveryCoordinator()

    @Published public private(set) var recentLogs: [RecoveryAuditLog] = []
    @Published public private(set) var lastRecoveryDate: Date?

    private let maxLogs = 20

    public init() {}

    public func performRecovery(reason: RecoveryReason) {
        var actions: [RecoveryAction] = []
        let isSuccess = true
        let errorMessage: String? = nil

        switch reason {
        case .appQuit:
            // 1. Restore fan to auto
            ThermalMonitor.shared.restoreSystemControl()
            actions.append(.restoreFanAuto)

            // 2. Restore battery default charging
            BatteryChargeManager.shared.restoreDefaultCharging()
            actions.append(.restoreBatteryCharging)

            // 3. Release caffeine power assertions
            CaffeineManager.shared.cleanupOnExit()
            actions.append(.releasePowerAssertions)

            // 4. Stop scroll reverser
            ScrollReverserManager.shared.stop()
            actions.append(.stopScrollEventTap)

            // 5. Stop NoTunes
            NoTunesManager.shared.stopMonitoring()
            actions.append(.stopNoTunesMonitoring)

            // 6. Stop Clipboard
            ClipboardMonitor.shared.stopMonitoring()
            actions.append(.stopClipboardMonitoring)

            // 7. Unregister hotkeys
            HotKeyManager.shared.unregister()
            actions.append(.unregisterHotkeys)

            // 8. FeatureManager cleanup all
            FeatureManager.shared.cleanupAll()
            actions.append(.cleanupFeature)

        case .systemSleep:
            ThermalMonitor.shared.restoreSystemControl()
            actions.append(.restoreFanAuto)

            BatteryChargeManager.shared.restoreDefaultCharging()
            actions.append(.restoreBatteryCharging)

            CaffeineManager.shared.cleanupOnExit()
            actions.append(.releasePowerAssertions)

        case .helperDisconnected:
            ThermalMonitor.shared.restoreSystemControl()
            actions.append(.restoreFanAuto)

            BatteryChargeManager.shared.restoreDefaultCharging()
            actions.append(.restoreBatteryCharging)

            actions.append(.resetHelperConnection)

        case .featureDisabled:
            actions.append(.cleanupFeature)

        case .manual:
            ThermalMonitor.shared.restoreSystemControl()
            actions.append(.restoreFanAuto)

            BatteryChargeManager.shared.restoreDefaultCharging()
            actions.append(.restoreBatteryCharging)

            CaffeineManager.shared.cleanupOnExit()
            actions.append(.releasePowerAssertions)

            FeatureManager.shared.refreshAllStates()
        }

        let message = "已完成 [\(reason.displayName)] 恢复流程，执行了 \(actions.count) 项安全动作"
        let log = RecoveryAuditLog(
            reason: reason,
            actionsExecuted: actions,
            isSuccess: isSuccess,
            message: errorMessage ?? message
        )
        addLog(log)
        self.lastRecoveryDate = Date()
    }

    public func recoverFeature(id: FeatureID) {
        if let feature = FeatureManager.shared.feature(id: id) {
            feature.cleanup()
            feature.refreshState()
            let log = RecoveryAuditLog(
                reason: .featureDisabled,
                actionsExecuted: [.cleanupFeature],
                isSuccess: true,
                message: "已清理并重置功能「\(feature.title)」"
            )
            addLog(log)
        }
    }

    private func addLog(_ log: RecoveryAuditLog) {
        recentLogs.insert(log, at: 0)
        if recentLogs.count > maxLogs {
            recentLogs.removeLast(recentLogs.count - maxLogs)
        }
    }
}
