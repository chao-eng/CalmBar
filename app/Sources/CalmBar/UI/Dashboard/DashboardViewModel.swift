import Combine
import Foundation
import SwiftUI
import CalmBarKit

@MainActor
public final class DashboardViewModel: ObservableObject {
    public static let shared = DashboardViewModel()

    @Published public private(set) var primaryTemperature: Float = 0.0
    @Published public private(set) var fanSummary: String = "自动"
    @Published public private(set) var batteryPercentage: Int = 100
    @Published public private(set) var batteryStatus: ChargeOperationStatus = .disabled
    @Published public private(set) var isSMCConnected: Bool = true
    @Published public private(set) var safetyAction: SafetyAction = .none
    @Published public private(set) var needsHelperAttention: Bool = false
    @Published public private(set) var helperAttentionMessage: String = ""

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        let thermal = ThermalMonitor.shared
        let batteryMonitor = BatteryMonitor.shared
        let chargeManager = BatteryChargeManager.shared
        let helper = HelperClient.shared

        thermal.$primaryTemp
            .receive(on: RunLoop.main)
            .sink { [weak self] temp in
                self?.primaryTemperature = temp
            }
            .store(in: &cancellables)

        thermal.$isSMCConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.isSMCConnected = connected
            }
            .store(in: &cancellables)

        thermal.$currentSafetyAction
            .receive(on: RunLoop.main)
            .sink { [weak self] action in
                self?.safetyAction = action
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(batteryMonitor.$currentPercentage, chargeManager.$operationStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] percentage, status in
                self?.batteryPercentage = percentage
                self?.batteryStatus = status
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(helper.$isHelperAvailable, helper.$needsHelperUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] available, needsUpdate in
                if needsUpdate {
                    self?.needsHelperAttention = true
                    self?.helperAttentionMessage = "特权助手需更新以支持充电限制"
                } else if !available {
                    self?.needsHelperAttention = true
                    self?.helperAttentionMessage = "特权助手未激活（温控与充电受限）"
                } else {
                    self?.needsHelperAttention = false
                    self?.helperAttentionMessage = ""
                }
            }
            .store(in: &cancellables)
    }
}
