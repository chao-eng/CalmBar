import Combine
import Foundation

@MainActor
public final class ThermalFeature: CalmFeature {
    public let id: FeatureID = .thermal
    public let title: String = "硬件温控"
    public let category: FeatureCategory = .hardware
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .privilegedHelper,
            level: .required,
            reason: "需要特权助手以向 SMC 写入目标风扇转速，未安装时仅可读取传感器温度"
        )
    ]

    private let monitor: ThermalMonitor
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .running

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "thermal.restoreAuto",
                title: "恢复风扇自动控制",
                action: { [weak self] in
                    self?.monitor.restoreSystemControl()
                    AppSettings.shared.fanPreset = .auto
                }
            )
        ]
    }

    public init(monitor: ThermalMonitor = .shared) {
        self.monitor = monitor
        updateState()

        Publishers.CombineLatest3(monitor.$isSMCConnected, monitor.$isFanControlAuthorized, monitor.$errorMessage)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    private func updateState() {
        guard monitor.isSMCConnected else {
            if let err = monitor.errorMessage {
                state = .failed(err)
            } else {
                state = .unavailable
            }
            return
        }

        if !monitor.isFanControlAuthorized {
            state = .degraded
        } else {
            state = .running
        }
    }

    public func start() {
        monitor.startPolling()
        updateState()
    }

    public func stop() {
        monitor.stopPolling()
        monitor.restoreSystemControl()
        state = .disabled
    }

    public func cleanup() {
        monitor.restoreSystemControl()
    }
}
