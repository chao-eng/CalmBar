import Foundation
import IOKit.pwr_mgt

// MARK: - 计划录制专用电源断言

/// 与 Caffeine 的 `SleepPreventionManager` 完全独立：
/// 关闭 Caffeine 时 `allowSleep()` 不会释放这里的断言。
/// 15 秒超时 + 10 秒刷新，App 被强杀后最迟 15 秒恢复可休眠。
@MainActor
public final class RecorderSchedulePowerAssertion {
    public static let shared = RecorderSchedulePowerAssertion()

    private var assertionID: IOPMAssertionID?
    private var refreshTimer: Timer?

    public private(set) var isHolding: Bool = false

    private init() {}

    public func acquire() {
        guard !isHolding else {
            refresh()
            return
        }
        isHolding = true
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    public func release() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let assertionID {
            IOPMAssertionRelease(assertionID)
            self.assertionID = nil
        }
        isHolding = false
    }

    private func refresh() {
        guard isHolding else { return }
        if let assertionID {
            IOPMAssertionRelease(assertionID)
            self.assertionID = nil
        }
        var newID: IOPMAssertionID = 0
        let reason = "CalmBar 定时录制保持唤醒" as CFString
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            reason,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            15.0,
            nil as CFString?,
            &newID
        )
        if result == kIOReturnSuccess {
            assertionID = newID
        }
    }
}
