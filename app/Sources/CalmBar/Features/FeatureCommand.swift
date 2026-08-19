import Foundation

public struct FeatureCommand: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let isDangerous: Bool
    public let requiredPermission: PermissionType?
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        isDangerous: Bool = false,
        requiredPermission: PermissionType? = nil,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isDangerous = isDangerous
        self.requiredPermission = requiredPermission
        self.action = action
    }
}
