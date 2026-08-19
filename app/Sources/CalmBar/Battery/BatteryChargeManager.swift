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
    @Published public private(set) var safetyTriggered: Bool = false

    private var hasReachedChargeLimit: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var evaluateTimer: Timer?

    private init() {
        setupObservers()
        updateTimerState()

        // Initial evaluation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.evaluateChargingPolicy()
        }
    }

    // MARK: - Timer & Energy Management

    private func updateTimerState() {
        let isEnabled = AppSettings.shared.batteryChargeLimitEnabled || AppSettings.shared.batteryTopUpActive
        let isOperational = SystemEventCoordinator.shared.isOperational

        if isEnabled && isOperational {
            if evaluateTimer == nil {
                evaluateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.evaluateChargingPolicy()
                    }
                }
            }
        } else {
            evaluateTimer?.invalidate()
            evaluateTimer = nil
        }
    }

    // MARK: - Public Actions

    /// Toggles the Battery Charge Limit feature
    public func toggleChargeLimit() {
        AppSettings.shared.batteryChargeLimitEnabled.toggle()
        updateTimerState()
        evaluateChargingPolicy()
    }

    /// Sets temporary top-up to 100% (e.g. before traveling)
    public func toggleTopUp() {
        AppSettings.shared.batteryTopUpActive.toggle()
        updateTimerState()
        evaluateChargingPolicy()
    }

    /// Restores standard macOS charging when exiting CalmBar or sleeping
    public func restoreDefaultCharging() {
        applyInhibition(false)
        applyForceDischarge(false)
    }

    // MARK: - Policy Engine (with Hardware Fail-Safe & Safety Melt)

    public func evaluateChargingPolicy() {
        let battery = BatteryMonitor.shared
        let settings = AppSettings.shared

        guard battery.hasBattery else {
            self.operationStatus = .unsupported
            self.isSupportedByHardware = false
            return
        }

        // 1. Hardware Safety Abort Check (15% Critical Low Battery or Overheat)
        let (shouldAbort, abortReason) = BatterySafetyPolicy.shouldEmergencyAbort(
            currentPercentage: battery.currentPercentage,
            batteryTempCelsius: battery.temperatureCelsius > 0 ? battery.temperatureCelsius : nil
        )

        if shouldAbort {
            self.safetyTriggered = true
            self.lastStatusMessage = abortReason ?? "底层安全熔断已触发"
            applyForceDischarge(false)
            applyInhibition(false)
            self.operationStatus = .charging
            return
        } else {
            self.safetyTriggered = false
        }

        // 2. Physical adapter check
        guard battery.isAdapterPhysicallyConnected else {
            self.operationStatus = .unplugged
            self.lastStatusMessage = "电池供电中 (\(battery.currentPercentage)%)"
            applyForceDischarge(false)
            return
        }

        // 3. Top Up mode active (charge to 100% once)
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

        // 4. Charge Limit disabled
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
                self.lastStatusMessage = "需激活特权助手以支持 SMC 充电控制"
            }
            return
        }

        Task { @MainActor in
            do {
                try await BatteryService.shared.setInhibition(inhibit)
                self.isChargingInhibited = inhibit
                BatteryMonitor.shared.refreshBatteryInfo()
            } catch {
                self.lastStatusMessage = "SMC 充电控制未响应: \(error.localizedDescription)"
            }
        }
    }

    private func applyForceDischarge(_ enabled: Bool) {
        if self.isForceDischarging == enabled { return }

        guard HelperClient.isHelperInstalledOnDisk else { return }

        Task { @MainActor in
            do {
                try await BatteryService.shared.setForceDischarge(enabled)
                self.isForceDischarging = enabled
                BatteryMonitor.shared.refreshBatteryInfo()
            } catch {
                self.lastStatusMessage = "适配器供电控制未响应: \(error.localizedDescription)"
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
            .sink { [weak self] _ in
                self?.updateTimerState()
                self?.evaluateChargingPolicy()
            }
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
            .sink { [weak self] _ in
                self?.updateTimerState()
                self?.evaluateChargingPolicy()
            }
            .store(in: &cancellables)

        AppSettings.shared.$batteryAutoDischargeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateChargingPolicy() }
            .store(in: &cancellables)

        SystemEventCoordinator.shared.$isOperational
            .receive(on: RunLoop.main)
            .sink { [weak self] operational in
                self?.updateTimerState()
                if operational {
                    self?.evaluateChargingPolicy()
                }
            }
            .store(in: &cancellables)
    }
}

