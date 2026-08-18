import Foundation
import Combine
import SwiftUI
import CalmBarKit

public enum ChargeOperationStatus: String, CaseIterable, Sendable {
    case disabled = "disabled"
    case charging = "charging"
    case limitedAndBypassed = "limitedAndBypassed"
    case sailing = "sailing"
    case discharging = "discharging"
    case topUp = "topUp"
    case unplugged = "unplugged"
    case unsupported = "unsupported"

    public var titleZH: String {
        switch self {
        case .disabled: return "未启用充电保护"
        case .charging: return "正在充电"
        case .limitedAndBypassed: return "已限制充电 · 旁路供电中"
        case .sailing: return "巡航回差保护中"
        case .discharging: return "正在放电至目标"
        case .topUp: return "临时充至 100%"
        case .unplugged: return "电池供电"
        case .unsupported: return "硬件不支持 SMC 充电控制"
        }
    }
}

/// Top-level coordinator for Battery Charging Limit (80% Protection) & Sailing Mode in CalmBar
@MainActor
public final class BatteryChargeManager: ObservableObject {
    public static let shared = BatteryChargeManager()

    @Published public private(set) var operationStatus: ChargeOperationStatus = .disabled
    @Published public private(set) var isChargingInhibited: Bool = false
    @Published public private(set) var isForceDischarging: Bool = false
    @Published public private(set) var lastStatusMessage: String = ""
    @Published public private(set) var isSupportedByHardware: Bool = true

    private var hasReachedChargeLimit: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var evaluateTimer: Timer?

    private init() {
        setupObservers()

        evaluateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateChargingPolicy()
            }
        }

        // Initial evaluation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.evaluateChargingPolicy()
        }
    }

    // MARK: - Public Actions

    /// Toggles the Battery Charge Limit feature
    public func toggleChargeLimit() {
        AppSettings.shared.batteryChargeLimitEnabled.toggle()
        evaluateChargingPolicy()
    }

    /// Sets temporary top-up to 100% (e.g. before traveling)
    public func toggleTopUp() {
        AppSettings.shared.batteryTopUpActive.toggle()
        evaluateChargingPolicy()
    }

    /// Restores standard macOS charging when exiting CalmBar
    public func restoreDefaultCharging() {
        applyInhibition(false)
        applyForceDischarge(false)
    }

    // MARK: - Policy Engine (mirrors Aidente's evaluate() flow)

    public func evaluateChargingPolicy() {
        let battery = BatteryMonitor.shared
        let settings = AppSettings.shared

        guard battery.hasBattery else {
            self.operationStatus = .unsupported
            return
        }

        // When force discharge is active, macOS will report isACPowered=false (since power is cut).
        // We must check if the adapter is physically connected so we don't accidentally cancel force discharge.
        guard battery.isAdapterPhysicallyConnected else {
            self.operationStatus = .unplugged
            self.lastStatusMessage = "电池供电中 (\(battery.currentPercentage)%)"
            applyForceDischarge(false)
            return
        }

        // Top Up mode active (charge to 100% once)
        if settings.batteryTopUpActive {
            if battery.currentPercentage >= 100 {
                settings.batteryTopUpActive = false
                evaluateChargingPolicy()
                return
            }
            self.operationStatus = .topUp
            self.lastStatusMessage = "充至 100% 模式 (\(battery.currentPercentage)%)"
            applyInhibition(false)
            applyForceDischarge(false)
            return
        }

        // Charge Limit disabled
        guard settings.batteryChargeLimitEnabled else {
            self.operationStatus = .disabled
            self.lastStatusMessage = "系统默认托管 (\(battery.currentPercentage)%)"
            self.hasReachedChargeLimit = false
            applyInhibition(false)
            applyForceDischarge(false)
            return
        }

        let targetLimit = settings.batteryChargeLimit
        let sailingDelta = settings.batterySailingModeEnabled ? settings.batterySailingDelta : 0
        let lowerBound = max(20, targetLimit - sailingDelta)
        let autoDischarge = settings.batteryAutoDischargeEnabled

        if battery.currentPercentage > targetLimit {
            self.hasReachedChargeLimit = true
            if autoDischarge {
                // Auto discharge mode: cut adapter power to drain on battery
                applyInhibition(false)
                applyForceDischarge(true)
                self.operationStatus = .discharging
                self.lastStatusMessage = "电量 \(battery.currentPercentage)% · 放电至 \(targetLimit)%"
            } else {
                // Normal bypass mode: keep adapter on, block charging
                applyForceDischarge(false)
                applyInhibition(true)
                self.operationStatus = .limitedAndBypassed
                self.lastStatusMessage = "已达上限 \(targetLimit)% · 旁路供电"
            }
        } else if battery.currentPercentage == targetLimit {
            self.hasReachedChargeLimit = true
            // Exactly at limit: stop discharging, keep bypass
            applyForceDischarge(false)
            applyInhibition(true)
            self.operationStatus = .limitedAndBypassed
            self.lastStatusMessage = "已达上限 \(targetLimit)% · 旁路供电"
        } else if battery.currentPercentage <= lowerBound {
            self.hasReachedChargeLimit = false
            // Below lower bound: allow charging, stop discharge
            applyForceDischarge(false)
            applyInhibition(false)
            self.operationStatus = .charging
            self.lastStatusMessage = "低于 \(lowerBound)% · 补电至 \(targetLimit)%"
        } else {
            // In sailing window (lowerBound < currentPercentage < targetLimit)
            applyForceDischarge(false)
            if settings.batterySailingModeEnabled && (self.hasReachedChargeLimit || self.isChargingInhibited) {
                self.hasReachedChargeLimit = true
                self.operationStatus = .sailing
                self.lastStatusMessage = "巡航保护 (\(battery.currentPercentage)% / \(targetLimit)%)"
                applyInhibition(true)
            } else {
                self.operationStatus = .charging
                self.lastStatusMessage = "充电中 (\(battery.currentPercentage)% → \(targetLimit)%)"
                applyInhibition(false)
            }
        }
    }

    // MARK: - SMC Control Actions

    private func applyInhibition(_ inhibit: Bool) {
        if self.isChargingInhibited == inhibit { return }

        guard HelperClient.isHelperInstalledOnDisk else {
            if inhibit {
                self.lastStatusMessage = "需一键激活特权助手以控制充电"
            }
            return
        }

        HelperClient.shared.setBatteryChargingInhibited(inhibit) { [weak self] success, err in
            guard let self = self else { return }
            if success {
                self.isChargingInhibited = inhibit
                BatteryMonitor.shared.refreshBatteryInfo()
            } else if let err = err {
                self.lastStatusMessage = "充电控制失败: \(err)"
            }
        }
    }

    private func applyForceDischarge(_ enabled: Bool) {
        if self.isForceDischarging == enabled { return }

        guard HelperClient.isHelperInstalledOnDisk else { return }

        HelperClient.shared.setBatteryForceDischarge(enabled) { [weak self] success, err in
            guard let self = self else { return }
            if success {
                self.isForceDischarging = enabled
                BatteryMonitor.shared.refreshBatteryInfo()
            } else if let err = err {
                self.lastStatusMessage = "适配器控制失败: \(err)"
            }
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        BatteryMonitor.shared.$currentPercentage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        BatteryMonitor.shared.$isAdapterPhysicallyConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        AppSettings.shared.$batteryChargeLimitEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        AppSettings.shared.$batteryChargeLimit
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        AppSettings.shared.$batterySailingModeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        AppSettings.shared.$batteryTopUpActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        AppSettings.shared.$batteryAutoDischargeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)
    }
}
