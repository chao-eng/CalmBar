import Foundation
import CalmBarKit

@MainActor
public final class BatteryService {
    public static let shared = BatteryService()

    private let helperClient: HelperClient

    public init(helperClient: HelperClient = .shared) {
        self.helperClient = helperClient
    }

    public func setInhibition(_ inhibit: Bool) async throws {
        guard helperClient.isHelperAvailable else {
            throw ServiceError.helperUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            helperClient.setBatteryChargingInhibited(inhibit) { success, errorMsg in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(errorMsg ?? "设置充电阻断失败"))
                }
            }
        }
    }

    public func setForceDischarge(_ discharge: Bool) async throws {
        guard helperClient.isHelperAvailable else {
            throw ServiceError.helperUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            helperClient.setBatteryForceDischarge(discharge) { success, errorMsg in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(errorMsg ?? "设置强制放电失败"))
                }
            }
        }
    }

    public func readSMCStatus() async throws -> (isInhibited: Bool, isDischarging: Bool) {
        guard helperClient.isHelperAvailable else {
            throw ServiceError.helperUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            helperClient.getBatterySMCStatus { success, isInhibited, isDischarging, errorMsg in
                if success {
                    continuation.resume(returning: (isInhibited, isDischarging))
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(errorMsg ?? "读取 SMC 状态失败"))
                }
            }
        }
    }
}
