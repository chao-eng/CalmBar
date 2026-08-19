import Combine
import Foundation

@MainActor
public final class ClipboardFeature: CalmFeature {
    public let id: FeatureID = .clipboard
    public let title: String = "剪贴板历史"
    public let category: FeatureCategory = .productivity
    public let requiredPermissions: [FeaturePermissionRequirement] = []

    private let monitor: ClipboardMonitor
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "clipboard.history",
                title: "打开剪贴板历史",
                subtitle: "查看与搜索剪贴板历史条目",
                action: {
                    ClipboardHistoryWindowController.shared.show()
                }
            ),
            FeatureCommand(
                id: "clipboard.clear",
                title: "清空剪贴板历史",
                subtitle: "删除所有未固定的剪贴板记录",
                isDangerous: true,
                action: {
                    ClipboardHistoryManager.shared.clearAll()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.clipboard",
            featureID: .clipboard,
            title: "剪贴板",
            subtitle: "\(ClipboardHistoryManager.shared.items.count) 条记录",
            iconName: "doc.on.clipboard.fill",
            state: state
        )
    }

    public init(monitor: ClipboardMonitor = .shared) {
        self.monitor = monitor
        updateState()

        monitor.$isMonitoring
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        if AppSettings.shared.clipboardHistoryEnabled {
            state = monitor.isMonitoring ? .running : .enabled
        } else {
            state = .disabled
        }
    }

    public func start() {
        monitor.startMonitoring()
        updateState()
    }

    public func stop() {
        monitor.stopMonitoring()
        updateState()
    }

    public func cleanup() {
        monitor.stopMonitoring()
    }
}
