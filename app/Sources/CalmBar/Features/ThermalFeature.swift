import Combine
import Foundation

@MainActor
public final class ThermalFeature: CalmFeature {
    public let id: FeatureID = .thermal
    public let title: String = "硬件温控"
    public let category: FeatureCategory = .hardware

    public var requiredPermissions: [FeaturePermissionRequirement] {
        // 无风扇机型读温度无需特权助手
        guard monitor.requiresHelperForThermal else { return [] }
        return [
            FeaturePermissionRequirement(
                type: .privilegedHelper,
                level: .required,
                reason: "需要特权助手以向 SMC 写入目标风扇转速，未安装时仅可读取传感器温度"
            )
        ]
    }

    private let monitor: ThermalMonitor
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .running

    public var commands: [FeatureCommand] {
        // 无风扇机型不暴露任何风扇控制命令，仅保留温度监控
        guard monitor.requiresHelperForThermal else { return [] }
        return [
            FeatureCommand(
                id: "thermal.restoreAuto",
                title: "恢复风扇自动控制",
                subtitle: "将散热策略重置为系统默认",
                action: { [weak self] in
                    self?.monitor.restoreSystemControl()
                    AppSettings.shared.fanPreset = .auto
                }
            ),
            FeatureCommand(
                id: "thermal.fanFull",
                title: "风扇全速运转",
                subtitle: "紧急降温：将风扇转速设为 100%",
                isDangerous: true,
                requiredPermission: .privilegedHelper,
                action: {
                    AppSettings.shared.fanPreset = .manual
                    AppSettings.shared.customFanFraction = 1.0
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.thermal",
            featureID: .thermal,
            title: "硬件温控",
            subtitle: "\(Int(monitor.primaryTemp))°C",
            iconName: "flame.fill",
            state: state,
            isHighlighted: monitor.currentSafetyAction != .none
        )
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

    public func refreshState() {
        updateState()
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

        // 无风扇机型：纯温度监控，无需风扇控制授权即视为可用
        if !monitor.requiresHelperForThermal {
            state = .running
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
