import Combine
import Foundation

@MainActor
public final class MenuBarFeature: CalmFeature {
    public let id: FeatureID = .menuBar
    public let title: String = "菜单栏收纳"
    public let category: FeatureCategory = .system
    public let requiredPermissions: [FeaturePermissionRequirement] = []

    private let manager: MenuBarOrganizer
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .running

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "menubar.toggle",
                title: "展开/折叠菜单栏",
                subtitle: "隐藏或显示被折叠的副菜单栏图标",
                action: { [weak self] in
                    self?.manager.toggleExpandCollapse()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.menubar",
            featureID: .menuBar,
            title: "菜单栏收纳",
            subtitle: manager.isCollapsed ? "已折叠图标" : "已展开全部",
            iconName: "menubar.rectangle",
            state: state,
            isHighlighted: manager.isCollapsed
        )
    }

    public init(manager: MenuBarOrganizer = .shared) {
        self.manager = manager
        updateState()

        manager.$isCollapsed
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        state = .running
    }

    public func start() {
        updateState()
    }

    public func stop() {
        state = .disabled
    }

    public func cleanup() {}
}
