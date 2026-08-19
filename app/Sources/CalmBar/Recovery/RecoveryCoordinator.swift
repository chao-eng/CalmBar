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

        // 1. Restore fan to auto
        ThermalMonitor.shared.restoreSystemControl()
        actions.append(.restoreFanAuto)

        // 2. Restore battery default charging
        BatteryChargeManager.shared.restoreDefaultCharging()
        actions.append(.restoreBatteryCharging)

        // 3. Release caffeine power assertions
        CaffeineManager.shared.cleanupOnExit()
        actions.append(.releasePowerAssertions)

        if reason == .appQuit {
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
        }

        let log = RecoveryAuditLog(
            reason: reason,
            actionsExecuted: actions,
            isSuccess: true,
            message: "成功执行 \(actions.count) 项安全恢复动作"
        )
        addLog(log)
        self.lastRecoveryDate = Date()
    }

    private func addLog(_ log: RecoveryAuditLog) {
        recentLogs.insert(log, at: 0)
        if recentLogs.count > maxLogs {
            recentLogs.removeLast(recentLogs.count - maxLogs)
        }
    }
}
