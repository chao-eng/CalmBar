import Foundation

/// 风扇控制权交还的纯状态机：连续写入失败计数、交还原因与交接确认。
///
/// 不依赖 SMC / Helper / 定时器，便于单元测试。`ThermalMonitor` 负责把这里的
/// 状态同步到 `@Published` 属性，并执行实际的 SMC 写入与恢复。
public struct FanControlReleaseTracker: Sendable {
    public let failureThreshold: Int
    public private(set) var consecutiveWriteFailures: Int = 0
    public private(set) var cause: ControlReleaseCause?
    public private(set) var handoffConfirmed: Bool = false

    public init(failureThreshold: Int = 3) {
        self.failureThreshold = max(1, failureThreshold)
    }

    public var isReleased: Bool {
        cause != nil
    }

    /// 写入成功：清零连续失败计数（已建立的交还状态保持不变）
    public mutating func recordWriteSuccess() {
        consecutiveWriteFailures = 0
    }

    /// 写入失败：返回是否达到交还阈值
    public mutating func recordWriteFailure() -> Bool {
        consecutiveWriteFailures += 1
        return consecutiveWriteFailures >= failureThreshold
    }

    /// 建立交还状态；同一原因重复调用返回 false（幂等）
    public mutating func beginRelease(cause: ControlReleaseCause) -> Bool {
        guard self.cause != cause else { return false }
        self.cause = cause
        handoffConfirmed = false
        return true
    }

    public mutating func confirmHandoff() {
        handoffConfirmed = true
    }

    public mutating func markHandoffFailed() {
        handoffConfirmed = false
    }

    /// 用户显式重新接管
    public mutating func clear() {
        cause = nil
        handoffConfirmed = false
        consecutiveWriteFailures = 0
    }

    /// Helper 恢复可用后重试，不改变当前交还原因
    public mutating func resetFailureCount() {
        consecutiveWriteFailures = 0
    }
}
