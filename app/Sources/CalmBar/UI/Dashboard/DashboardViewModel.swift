import Combine
import Foundation
import SwiftUI
import CalmBarKit

@MainActor
public final class DashboardViewModel: ObservableObject {
    public static let shared = DashboardViewModel()

    @Published public private(set) var primaryTemperature: Float = 0.0
    @Published public private(set) var fanSummary: String = "自动"
    @Published public private(set) var fanSnapshots: [FanSnapshot] = []
    @Published public private(set) var isFanControlAuthorized: Bool = false
    @Published public private(set) var batteryPercentage: Int = 100
    @Published public private(set) var batteryStatus: ChargeOperationStatus = .disabled
    @Published public private(set) var isSMCConnected: Bool = true
    @Published public private(set) var safetyAction: SafetyAction = .none
    @Published public private(set) var needsHelperAttention: Bool = false
    @Published public private(set) var helperAttentionMessage: String = ""

    @Published public private(set) var isCaffeineActive: Bool = false
    @Published public private(set) var isMenuBarCollapsed: Bool = false
    @Published public private(set) var isScrollReverserRunning: Bool = false
    @Published public private(set) var hasScrollPermission: Bool = false
    @Published public private(set) var isOCRRecognizing: Bool = false
    @Published public private(set) var clipboardCount: Int = 0

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        let thermal = ThermalMonitor.shared
        let batteryMonitor = BatteryMonitor.shared
        let chargeManager = BatteryChargeManager.shared
        let helper = HelperClient.shared
        let caffeine = CaffeineManager.shared
        let menuBar = MenuBarOrganizer.shared
        let scroll = ScrollReverserManager.shared
        let ocr = OCRManager.shared
        let clipboard = ClipboardHistoryManager.shared

        thermal.$primaryTemp
            .receive(on: RunLoop.main)
            .sink { [weak self] temp in
                self?.primaryTemperature = temp
            }
            .store(in: &cancellables)

        thermal.$fanSnapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] snaps in
                self?.fanSnapshots = snaps
            }
            .store(in: &cancellables)

        thermal.$isFanControlAuthorized
            .receive(on: RunLoop.main)
            .sink { [weak self] auth in
                self?.isFanControlAuthorized = auth
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
                    if HelperClient.isHelperInstalledOnDisk {
                        self?.helperAttentionMessage = "已授权但未响应，请在系统设置中允许后台运行"
                    } else {
                        self?.helperAttentionMessage = "特权助手未激活（温控与充电受限）"
                    }
                } else {
                    self?.needsHelperAttention = false
                    self?.helperAttentionMessage = ""
                }
            }
            .store(in: &cancellables)

        caffeine.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.isCaffeineActive = active
            }
            .store(in: &cancellables)

        menuBar.$isCollapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] collapsed in
                self?.isMenuBarCollapsed = collapsed
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(scroll.$isRunning, scroll.$hasAccessibilityPermission)
            .receive(on: RunLoop.main)
            .sink { [weak self] running, permission in
                self?.isScrollReverserRunning = running
                self?.hasScrollPermission = permission
            }
            .store(in: &cancellables)

        ocr.$isRecognizing
            .receive(on: RunLoop.main)
            .sink { [weak self] rec in
                self?.isOCRRecognizing = rec
            }
            .store(in: &cancellables)

        clipboard.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.clipboardCount = items.count
            }
            .store(in: &cancellables)
    }
}
