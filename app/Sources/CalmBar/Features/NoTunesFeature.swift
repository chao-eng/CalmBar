import Combine
import Foundation

@MainActor
public final class NoTunesFeature: CalmFeature {
    public let id: FeatureID = .noTunes
    public let title: String = "音乐启动拦截"
    public let category: FeatureCategory = .system
    public let requiredPermissions: [FeaturePermissionRequirement] = []

    private let manager: NoTunesManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "notunes.toggle",
                title: "切换音乐拦截状态",
                subtitle: "拦截 macOS 意外拉起 Apple Music",
                action: {
                    AppSettings.shared.noTunesEnabled.toggle()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.notunes",
            featureID: .noTunes,
            title: "音乐启动拦截",
            subtitle: AppSettings.shared.noTunesEnabled ? "已启用拦截" : "已停用",
            iconName: "music.note",
            state: state,
            isHighlighted: AppSettings.shared.noTunesEnabled
        )
    }

    public init(manager: NoTunesManager = .shared) {
        self.manager = manager
        updateState()

        manager.$isMonitoring
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        if AppSettings.shared.noTunesEnabled {
            state = manager.isMonitoring ? .running : .enabled
        } else {
            state = .disabled
        }
    }

    public func start() {
        manager.startMonitoring()
        updateState()
    }

    public func stop() {
        manager.stopMonitoring()
        updateState()
    }

    public func cleanup() {
        manager.stopMonitoring()
    }
}
