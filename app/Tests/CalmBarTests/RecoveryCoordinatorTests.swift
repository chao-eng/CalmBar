import Foundation
import Testing
@testable import CalmBar

@Suite("Recovery Coordinator Tests")
struct RecoveryCoordinatorTests {

    @Test("Test Recovery execution on Sleep")
    @MainActor
    func testSleepRecovery() {
        let coordinator = RecoveryCoordinator()
        coordinator.performRecovery(reason: .systemSleep)

        #expect(coordinator.recentLogs.count == 1)
        let log = coordinator.recentLogs.first
        #expect(log?.reason == .systemSleep)
        #expect(log?.actionsExecuted.contains(.restoreFanAuto) == true)
        #expect(log?.actionsExecuted.contains(.restoreBatteryCharging) == true)
        #expect(log?.actionsExecuted.contains(.releasePowerAssertions) == true)
        #expect(log?.isSuccess == true)
    }

    @Test("Test Recovery execution on App Quit")
    @MainActor
    func testAppQuitRecovery() {
        let coordinator = RecoveryCoordinator()
        coordinator.performRecovery(reason: .appQuit)

        #expect(coordinator.recentLogs.count == 1)
        let log = coordinator.recentLogs.first
        #expect(log?.reason == .appQuit)
        #expect(log?.actionsExecuted.contains(.stopScrollEventTap) == true)
        #expect(log?.actionsExecuted.contains(.stopNoTunesMonitoring) == true)
        #expect(log?.actionsExecuted.contains(.stopClipboardMonitoring) == true)
        #expect(log?.actionsExecuted.contains(.unregisterHotkeys) == true)
    }

    @Test("Test Multiple Recovery runs idempotency and log capping")
    @MainActor
    func testIdempotencyAndLogRetention() {
        let coordinator = RecoveryCoordinator()
        for _ in 0..<30 {
            coordinator.performRecovery(reason: .manual)
        }

        #expect(coordinator.recentLogs.count == 20)
        #expect(coordinator.recentLogs.allSatisfy { $0.reason == .manual })
    }
}
