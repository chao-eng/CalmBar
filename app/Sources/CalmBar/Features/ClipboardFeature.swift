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
                id: "clipboard.clear",
                title: "清空剪贴板历史",
                isDangerous: true,
                action: {
                    ClipboardHistoryManager.shared.clearAll()
                }
            )
        ]
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
