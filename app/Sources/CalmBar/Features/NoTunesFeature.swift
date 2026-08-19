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
                action: {
                    AppSettings.shared.noTunesEnabled.toggle()
                }
            )
        ]
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
