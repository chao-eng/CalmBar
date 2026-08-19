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
                action: { [weak self] in
                    self?.manager.toggleExpandCollapse()
                }
            )
        ]
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
