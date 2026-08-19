import Foundation

public struct CommandDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let iconName: String
    public let category: CommandCategory
    public let featureID: FeatureID?
    public let requiredPermissions: [PermissionType]
    public let aliases: [String]
    public let run: @MainActor () async -> CommandResult

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconName: String = "command",
        category: CommandCategory,
        featureID: FeatureID? = nil,
        requiredPermissions: [PermissionType] = [],
        aliases: [String] = [],
        run: @escaping @MainActor () async -> CommandResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.category = category
        self.featureID = featureID
        self.requiredPermissions = requiredPermissions
        self.aliases = aliases
        self.run = run
    }
}
