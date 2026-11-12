import Foundation

public struct FeatureCommand: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let isDangerous: Bool
    public let requiredPermission: PermissionType?
    /// 执行前的前置检查：返回非 nil 文案时命令以失败结束，不执行 action
    public let precondition: (@MainActor @Sendable () -> String?)?
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        isDangerous: Bool = false,
        requiredPermission: PermissionType? = nil,
        precondition: (@MainActor @Sendable () -> String?)? = nil,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isDangerous = isDangerous
        self.requiredPermission = requiredPermission
        self.precondition = precondition
        self.action = action
    }
}
