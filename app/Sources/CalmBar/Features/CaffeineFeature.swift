import Combine
import Foundation

@MainActor
public final class CaffeineFeature: CalmFeature {
    public let id: FeatureID = .caffeine
    public let title: String = "防休眠防离开"
    public let category: FeatureCategory = .system
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .accessibility,
            level: .advanced,
            reason: "仅当开启「办公软件防离开 (Keep Apps Active)」模拟微动时需要辅助功能权限"
        )
    ]

    private let manager: CaffeineManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .disabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "caffeine.toggle",
                title: "开启/关闭防休眠",
                subtitle: "保持系统与显示器常亮",
                action: { [weak self] in
                    self?.manager.toggle()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.caffeine",
            featureID: .caffeine,
            title: "防休眠",
            subtitle: manager.isActive ? "已保持清醒" : "已休眠就绪",
            iconName: "cup.and.saucer.fill",
            state: state,
            isHighlighted: manager.isActive
        )
    }

    public init(manager: CaffeineManager = .shared) {
        self.manager = manager
        updateState()

        manager.$isActive
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        if manager.isActive {
            state = .running
        } else {
            state = .disabled
        }
    }

    public func start() {
        updateState()
    }

    public func stop() {
        manager.deactivate()
        updateState()
    }

    public func cleanup() {
        manager.cleanupOnExit()
    }
}
