import Foundation

public enum PermissionRequirementLevel: Sendable, Equatable {
    case required
    case optional
    case advanced
}

public struct FeaturePermissionRequirement: Sendable, Equatable {
    public let type: PermissionType
    public let level: PermissionRequirementLevel
    public let reason: String

    public init(type: PermissionType, level: PermissionRequirementLevel = .required, reason: String) {
        self.type = type
        self.level = level
        self.reason = reason
    }
}
