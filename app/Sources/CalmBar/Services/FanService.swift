import Foundation
import CalmBarKit

/// 保证 XPC 回调与超时只有一个能恢复 continuation
private final class ReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ action: () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        action()
    }
}

@MainActor
public final class FanService {
    public static let shared = FanService()

    /// 写入等待上限：覆盖联动双风扇最坏情况
    /// （每个风扇 FTST 稳定 0.5s + 解锁 3s，再留 1s 余量）
    public static let maxWriteDuration: TimeInterval = FanController.worstCaseManualModeSeconds * 2 + 1.0
    /// 恢复自动控制不涉及 FTST 解锁，使用较短超时
    public static let maxRestoreDuration: TimeInterval = 4.0

    private let helperClient: HelperClient

    public init(helperClient: HelperClient = .shared) {
        self.helperClient = helperClient
    }

    /// 联动写入：所有风扇使用同一转速比例
    public func setFanFraction(_ fraction: Double, fanController: FanController? = nil) async throws {
        try await setFanFractions([fraction], fanController: fanController)
    }

    /// 统一写入入口：
    /// - 1 个值 → 联动写入（所有风扇同比例）
    /// - 多个值 → 按索引分别写入（双风扇独立调速）
    public func setFanFractions(_ fractions: [Double], fanController: FanController? = nil) async throws {
        guard let first = fractions.first else { return }

        if fractions.count == 1 {
            if let controller = fanController, getuid() == 0 {
                do {
                    try controller.setLinkedFraction(first)
                    return
                } catch {
                    throw ServiceError.operationFailed(error.localizedDescription)
                }
            }

            guard helperClient.isHelperAvailable else {
                throw ServiceError.helperUnavailable
            }

            try await awaitHelperReply(timeout: FanService.maxWriteDuration) { completion in
                helperClient.setLinkedFraction(first, completion: completion)
            }
            return
        }

        if let controller = fanController, getuid() == 0 {
            do {
                for (index, fraction) in fractions.enumerated() {
                    try controller.setIndependentFraction(fanIndex: index, fraction: fraction)
                }
                return
            } catch {
                throw ServiceError.operationFailed(error.localizedDescription)
            }
        }

        guard helperClient.isHelperAvailable else {
            throw ServiceError.helperUnavailable
        }

        for (index, fraction) in fractions.enumerated() {
            try await awaitHelperReply(timeout: FanService.maxWriteDuration) { completion in
                helperClient.setFanFraction(UInt(index), fraction: fraction, completion: completion)
            }
        }
    }

    public func restoreAuto(fanController: FanController? = nil) async throws {
        if let controller = fanController, getuid() == 0 {
            do {
                try controller.restoreSystemControl()
                return
            } catch {
                throw ServiceError.operationFailed(error.localizedDescription)
            }
        }

        // 不再静默返回：Helper 不可用时必须让上层知道“交还系统”并未真正执行
        guard helperClient.isHelperAvailable else {
            throw ServiceError.helperUnavailable
        }

        try await awaitHelperReply(timeout: FanService.maxRestoreDuration) { completion in
            helperClient.restoreAuto(completion: completion)
        }
    }

    // MARK: - Helper 回复等待（带超时）

    private func awaitHelperReply(
        timeout seconds: TimeInterval,
        _ call: (@escaping @MainActor (Bool, String?) -> Void) -> Void
    ) async throws {
        let gate = ReplyGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resume: @MainActor (Bool, String?) -> Void = { success, message in
                gate.finish {
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(message ?? "风扇写入失败"))
                    }
                }
            }

            call(resume)

            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                gate.finish {
                    continuation.resume(throwing: ServiceError.timeout)
                }
            }
        }
    }
}
