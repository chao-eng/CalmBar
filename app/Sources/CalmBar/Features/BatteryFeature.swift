import Combine
import Foundation

@MainActor
public final class BatteryFeature: CalmFeature {
    public let id: FeatureID = .battery
    public let title: String = "充电保护"
    public let category: FeatureCategory = .hardware
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .privilegedHelper,
            level: .required,
            reason: "需要特权助手向 SMC 写入充电上限与旁路供电寄存器"
        )
    ]

    private let manager: BatteryChargeManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "battery.topUp",
                title: "临时充至 100%",
                subtitle: "暂时忽略充电限制，充至满电",
                requiredPermission: .privilegedHelper,
                action: { [weak self] in
                    self?.manager.toggleTopUp()
                }
            ),
            FeatureCommand(
                id: "battery.restoreDefault",
                title: "恢复默认充电",
                subtitle: "恢复系统默认充电逻辑",
                requiredPermission: .privilegedHelper,
                action: { [weak self] in
                    self?.manager.restoreDefaultCharging()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.battery",
            featureID: .battery,
            title: "充电保护",
            subtitle: "\(BatteryMonitor.shared.currentPercentage)%",
            iconName: "bolt.batteryblock.fill",
            state: state,
            isHighlighted: manager.operationStatus == .limitedAndBypassed
        )
    }

    public init(manager: BatteryChargeManager = .shared) {
        self.manager = manager
        updateState()

        Publishers.CombineLatest(manager.$operationStatus, manager.$isSupportedByHardware)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        guard manager.isSupportedByHardware else {
            state = .unavailable
            return
        }

        switch manager.operationStatus {
        case .disabled, .unsupported:
            state = .disabled
        case .charging, .limitedAndBypassed, .sailing, .discharging, .topUp, .unplugged:
            state = .running
        }
    }

    public func start() {
        updateState()
    }

    public func stop() {
        manager.restoreDefaultCharging()
        state = .disabled
    }

    public func cleanup() {
        manager.restoreDefaultCharging()
    }
}
