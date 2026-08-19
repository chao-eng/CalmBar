import Combine
import Foundation

@MainActor
public final class GatekeeperFeature: CalmFeature {
    public let id: FeatureID = .gatekeeper
    public let title: String = "应用去隔离与自签名"
    public let category: FeatureCategory = .security
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .privilegedHelper,
            level: .optional,
            reason: "修改 /Applications 等受系统保护路径下的应用时需要特权助手免密提权"
        )
    ]

    private let manager: GatekeeperManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "gatekeeper.open",
                title: "打开应用去隔离修复工具",
                subtitle: "修复已损坏或无法验证开发者的应用",
                action: {
                    StatusBarManager.shared.openSettingsWindow(tab: .gatekeeper)
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.gatekeeper",
            featureID: .gatekeeper,
            title: "应用去隔离与自签名",
            subtitle: manager.isProcessing ? "修复中" : "就绪",
            iconName: "lock.shield",
            state: state,
            isHighlighted: manager.isProcessing
        )
    }

    public init(manager: GatekeeperManager = .shared) {
        self.manager = manager
        updateState()

        manager.$isProcessing
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        if manager.isProcessing {
            state = .running
        } else {
            state = .enabled
        }
    }

    public func start() {
        updateState()
    }

    public func stop() {
        state = .disabled
    }

    public func cleanup() {}
}
