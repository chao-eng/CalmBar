import Foundation

public struct RecoveryAuditLog: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let reason: RecoveryReason
    public let actionsExecuted: [RecoveryAction]
    public let isSuccess: Bool
    public let message: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        reason: RecoveryReason,
        actionsExecuted: [RecoveryAction],
        isSuccess: Bool = true,
        message: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.reason = reason
        self.actionsExecuted = actionsExecuted
        self.isSuccess = isSuccess
        self.message = message
    }
}
