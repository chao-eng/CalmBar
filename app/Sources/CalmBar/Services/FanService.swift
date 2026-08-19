import Foundation
import CalmBarKit

@MainActor
public final class FanService {
    public static let shared = FanService()

    private let helperClient: HelperClient

    public init(helperClient: HelperClient = .shared) {
        self.helperClient = helperClient
    }

    public func setFanFraction(_ fraction: Double, fanController: FanController? = nil) async throws {
        if let controller = fanController, getuid() == 0 {
            do {
                try controller.setLinkedFraction(fraction)
                return
            } catch {
                throw ServiceError.operationFailed(error.localizedDescription)
            }
        }

        guard helperClient.isHelperAvailable else {
            throw ServiceError.helperUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            helperClient.setLinkedFraction(fraction) { success, errorMsg in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(errorMsg ?? "风扇写入失败"))
                }
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

        guard helperClient.isHelperAvailable else {
            return
        }

        return try await withCheckedThrowingContinuation { continuation in
            helperClient.restoreAuto { success, errorMsg in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(errorMsg ?? "恢复自动失败"))
                }
            }
        }
    }
}
