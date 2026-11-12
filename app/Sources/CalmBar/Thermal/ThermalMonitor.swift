import Foundation
import Combine
import CalmBarKit

/// 风扇控制权被交还系统的原因
public enum ControlReleaseCause: String, Sendable {
    /// 温度持续超过硬限
    case temperature
    /// 连续写入 SMC 失败
    case writeFailure
}

@MainActor
public final class ThermalMonitor: ObservableObject {
    public static let shared = ThermalMonitor()

    @Published public private(set) var primaryTemp: Float = 0.0
    @Published public private(set) var cpuTemp: Float = 0.0
    @Published public private(set) var gpuTemp: Float = 0.0
    @Published public private(set) var batteryTemp: Float = 0.0
    @Published public private(set) var allTemps: [TemperatureReading] = []
    @Published public private(set) var fanSnapshots: [FanSnapshot] = []
    @Published public private(set) var fanCapability: FanCapability = .unknown
    @Published public private(set) var isSMCConnected: Bool = false
    @Published public private(set) var isFanControlAuthorized: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var currentSafetyAction: SafetyAction = .none
    /// 非 nil 表示控制权已交还系统（温度硬限 / 连续写入失败）
    @Published public private(set) var controlReleaseCause: ControlReleaseCause? = nil
    @Published public private(set) var controlReleaseReason: String? = nil
    /// 交还动作是否已真正写入系统自动控制（Helper 不可用时为 false）
    @Published public private(set) var isControlHandoffConfirmed: Bool = false

    /// 已确认本机无内置风扇（被动散热机型，如 MacBook Air）
    public var isFanless: Bool {
        fanCapability.isFanless
    }

    /// SMC 已连接且存在可控制风扇 —— 温控调速全链路（UI / 命令 / 写入）的统一门控
    public var supportsFanControl: Bool {
        isSMCConnected && fanCapability.supportsFanControl
    }

    /// 被动散热机型：温度读取为只读操作，无需特权助手
    public var requiresHelperForThermal: Bool {
        supportsFanControl
    }

    public var isControlReleased: Bool {
        releaseTracker.isReleased
    }

    /// 交还系统时对外展示的阈值（用于文案）
    public var releaseTemp: Float {
        safetyPolicy.config.releaseTemp
    }

    /// 当前温度对应的安全转速下限（UI 展示用）
    public var safetyFloorFraction: Double {
        safetyPolicy.minimumFraction(forMaxTemp: primaryTemp)
    }

    private var fanController: FanController?
    private var safetyPolicy = SafetyPolicy()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// 连续写入失败与交还状态的纯逻辑状态机（可单测）
    private var releaseTracker = FanControlReleaseTracker()
    /// 避免定时器与滑杆操作叠加出并发写，导致转速指令乱序
    private var isWriteInFlight = false
    /// 去重并发的“恢复自动控制”请求
    private var isRestoreInFlight = false

    // Smoothing for smart mode
    private var smoothedFraction: Double = 0.0

    private init() {
        setupController()
        setupObservers()
        checkAuthorization()
        if AppSettings.shared.thermalEnabled {
            startPolling()
        }
    }

    public func setupController() {
        do {
            let conn = try SMCConnection()
            let controller = FanController(connection: conn)
            self.fanController = controller
            self.isSMCConnected = true
            self.fanCapability = controller.config.capability
            self.errorMessage = nil
            NSLog("ThermalMonitor: SMC ready - capability=\(fanCapabilityLabel(controller.config.capability))")
        } catch {
            self.fanController = nil
            self.isSMCConnected = false
            self.fanCapability = .unknown
            self.errorMessage = error.localizedDescription
            NSLog("ThermalMonitor: SMC init error - \(error.localizedDescription)")
        }
    }

    private func fanCapabilityLabel(_ capability: FanCapability) -> String {
        switch capability {
        case .unknown: return "unknown"
        case .fanless: return "fanless"
        case .hasFans(let n): return "hasFans(\(n))"
        }
    }

    public func checkAuthorization() {
        if getuid() == 0 {
            self.isFanControlAuthorized = supportsFanControl
            return
        }
        guard supportsFanControl else {
            self.isFanControlAuthorized = false
            return
        }
        HelperClient.shared.checkHelperStatus()
        self.isFanControlAuthorized = HelperClient.shared.isHelperAvailable
    }

    private func setupObservers() {
        AppSettings.shared.$thermalEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled {
                        self?.clearControlRelease()
                        self?.safetyPolicy.reset()
                        self?.startPolling()
                        self?.applyCurrentMode()
                    } else {
                        self?.stopPolling()
                        self?.restoreSystemControl()
                    }
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$fanPreset
            .dropFirst()
            .sink { [weak self] preset in
                Task { @MainActor in
                    guard let self else { return }
                    // 自动模式本就由系统控制；写入失败后切换模式视为显式重试。
                    // 温度硬限释放只能通过「重新接管」/「紧急全速」显式解除。
                    if preset == .auto || self.controlReleaseCause == .writeFailure {
                        self.clearControlRelease()
                    }
                    if AppSettings.shared.thermalEnabled {
                        self.applyCurrentMode()
                    }
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$customFanFraction
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard AppSettings.shared.thermalEnabled && AppSettings.shared.fanPreset == .manual else { return }
                    self?.applyCurrentMode()
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$fan0CustomFraction
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard AppSettings.shared.thermalEnabled && AppSettings.shared.fanPreset == .manual else { return }
                    self?.applyCurrentMode()
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$fan1CustomFraction
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard AppSettings.shared.thermalEnabled && AppSettings.shared.fanPreset == .manual else { return }
                    self?.applyCurrentMode()
                }
            }
            .store(in: &cancellables)

        HelperClient.shared.$isHelperAvailable
            .removeDuplicates()
            .sink { [weak self] available in
                Task { @MainActor in
                    if available || getuid() == 0 {
                        self?.isFanControlAuthorized = true
                        // Helper 恢复后重新尝试接管因写入失败而交还的控制权；
                        // 温度释放期间也补一次交还写入，覆盖上次恢复失败的情况
                        if self?.controlReleaseCause == .writeFailure {
                            self?.clearControlRelease()
                            if AppSettings.shared.thermalEnabled {
                                self?.applyCurrentMode()
                            }
                        } else if self?.isControlReleased == true {
                            self?.restoreSystemControl()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    public func startPolling() {
        stopPolling()
        guard AppSettings.shared.thermalEnabled else { return }
        updateReadings()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateReadings()
                self?.applyCurrentMode()
            }
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
        self.primaryTemp = 0.0
        self.cpuTemp = 0.0
        self.gpuTemp = 0.0
        self.batteryTemp = 0.0
        self.allTemps = []
        self.fanSnapshots = []
        self.currentSafetyAction = .none
        self.safetyPolicy.reset()
        self.releaseTracker.clear()
        self.controlReleaseCause = nil
        self.controlReleaseReason = nil
        self.isControlHandoffConfirmed = false
        self.smoothedFraction = 0.0
    }

    public func updateReadings() {
        guard let controller = fanController else {
            if !isSMCConnected {
                setupController()
            }
            return
        }

        let temps = controller.readTemperatures(primaryOnly: false)
        self.allTemps = temps

        let maxPrimary = controller.maxPrimaryTemperature() ?? 0.0
        self.primaryTemp = maxPrimary

        // Extract CPU, GPU, Battery (reset max values per poll cycle)
        var maxCpu: Float = 0.0
        var maxGpu: Float = 0.0
        var maxBattery: Float = 0.0

        for item in temps {
            if item.key.hasPrefix("Tp") || item.key.hasPrefix("TC") || item.key.hasPrefix("Te") {
                if item.celsius > maxCpu {
                    maxCpu = item.celsius
                }
            } else if item.key.hasPrefix("Tg") || item.key.hasPrefix("TG") {
                if item.celsius > maxGpu {
                    maxGpu = item.celsius
                }
            } else if item.key.hasPrefix("TB") {
                if item.celsius > maxBattery {
                    maxBattery = item.celsius
                }
            }
        }

        self.cpuTemp = maxCpu > 0 ? maxCpu : maxPrimary
        self.gpuTemp = maxGpu > 0 ? maxGpu : (self.cpuTemp > 0 ? max(30.0, self.cpuTemp - 4.0) : 0.0)
        self.batteryTemp = maxBattery

        if supportsFanControl, let fans = try? controller.allFans() {
            self.fanSnapshots = fans
        } else {
            self.fanSnapshots = []
        }

        // Evaluate safety policy
        let safetyAction = safetyPolicy.evaluate(maxTemp: maxPrimary)
        if isFanless {
            // 无风扇：转速下限档位与强制恢复语义不适用（无风扇可写），
            // 仅保留 warning / critical 级用于过温提醒徽标，避免界面暗示正在主动散热
            switch safetyAction {
            case .forceEmergencyCool, .forceCriticalCool, .restoreAuto:
                self.currentSafetyAction = safetyAction
            default:
                self.currentSafetyAction = .none
            }
        } else {
            self.currentSafetyAction = safetyAction
        }

        // 温度回落到硬限滞回带以下 → 重新接管
        if controlReleaseCause == .temperature, maxPrimary < safetyPolicy.releaseRecoverTemp {
            clearControlRelease()
        }
    }

    // MARK: - 写入

    private func writeFanFraction(_ fraction: Double) {
        writeFanFractions([fraction])
    }

    private func writeFanFractions(_ fractions: [Double]) {
        guard supportsFanControl, !isWriteInFlight else { return }
        isWriteInFlight = true
        Task { @MainActor in
            defer { self.isWriteInFlight = false }
            do {
                try await FanService.shared.setFanFractions(fractions, fanController: self.fanController)
                self.isFanControlAuthorized = true
                self.errorMessage = nil
                self.releaseTracker.recordWriteSuccess()
            } catch {
                if getuid() != 0 && !self.isFanControlAuthorized {
                    self.isFanControlAuthorized = false
                }
                self.errorMessage = error.localizedDescription
                if self.releaseTracker.recordWriteFailure() {
                    self.releaseControl(
                        cause: .writeFailure,
                        reason: "风扇转速连续写入失败，已交还系统自动控制"
                    )
                }
            }
        }
    }

    // MARK: - 控制权

    /// 交还系统自动控制。温度硬限与连续写入失败都会走这里，UI 据此展示「已由系统接管」。
    /// Helper 不可用时恢复会失败，此时把失败原因写进提示，避免误报已完成交接。
    public func releaseControl(cause: ControlReleaseCause, reason: String) {
        guard supportsFanControl else { return }
        guard releaseTracker.beginRelease(cause: cause) else { return }
        controlReleaseCause = cause
        controlReleaseReason = reason
        isControlHandoffConfirmed = false

        Task { @MainActor in
            // 等待正在进行的转速写入结束，避免随后的 auto 写入被旧的手动写入覆盖
            await self.awaitPendingWrite()
            do {
                try await FanService.shared.restoreAuto(fanController: self.fanController)
                guard self.releaseTracker.cause == cause else {
                    // 恢复期间用户已重新接管/关闭温控：补一次当前模式，
                    // 避免迟到的 auto 覆盖用户刚写入的转速
                    if AppSettings.shared.thermalEnabled {
                        self.applyCurrentMode()
                    }
                    return
                }
                self.releaseTracker.confirmHandoff()
                self.isControlHandoffConfirmed = true
                self.errorMessage = nil
            } catch {
                // 交接状态可能已被用户清除，避免旧任务覆盖新状态
                guard self.releaseTracker.cause == cause else {
                    if AppSettings.shared.thermalEnabled {
                        self.applyCurrentMode()
                    }
                    return
                }
                self.releaseTracker.markHandoffFailed()
                self.isControlHandoffConfirmed = false
                self.errorMessage = error.localizedDescription
                self.controlReleaseReason = "\(reason)（恢复系统自动控制失败：\(error.localizedDescription)；风扇可能停留在最后转速）"
            }
        }
    }

    /// 用户显式操作后重新接管控制权
    public func clearControlRelease() {
        guard releaseTracker.isReleased else { return }
        releaseTracker.clear()
        controlReleaseCause = nil
        controlReleaseReason = nil
        isControlHandoffConfirmed = false
        safetyPolicy.resetReleaseCountdown()
    }

    /// 紧急全速：用户显式指令优先于自动交接，重置硬限计时并立即写入 100%。
    public func forceFullSpeed() {
        guard supportsFanControl else { return }
        clearControlRelease()
        safetyPolicy.resetReleaseCountdown()
        currentSafetyAction = .none

        let settings = AppSettings.shared
        let fanCount = max(1, fanCapability.fanCount)
        if !settings.dualFanLinked, fanCount > 1 {
            settings.fan0CustomFraction = 1.0
            settings.fan1CustomFraction = 1.0
        }
        settings.customFanFraction = 1.0
        settings.fanPreset = .manual

        if settings.dualFanLinked || fanCount <= 1 {
            writeFanFraction(1.0)
        } else {
            writeFanFractions(Array(repeating: 1.0, count: fanCount))
        }
    }

    public func applyCurrentMode() {
        // 无风扇机型恒为纯温度监控：不执行任何转速策略写入
        guard supportsFanControl else { return }

        // 已交还系统：等待温度回落、Helper 恢复或用户显式重新接管
        guard !isControlReleased else { return }

        let settings = AppSettings.shared

        // 自动模式即系统控制，不存在“交还”语义
        if settings.fanPreset == .auto {
            restoreSystemControl()
            return
        }

        // 硬限持续超限 → 交还系统（由 SafetyPolicy 的计时器决定，单次尖峰不会触发）
        if safetyPolicy.shouldReleaseControl(maxTemp: primaryTemp) {
            releaseControl(
                cause: .temperature,
                reason: "核心温度持续高于 \(Int(releaseTemp))°C，已交还系统自动控制"
            )
            return
        }

        switch settings.fanPreset {
        case .auto:
            restoreSystemControl()

        case .manual:
            let safetyFloor = safetyPolicy.minimumFraction(forMaxTemp: primaryTemp)
            let fanCount = max(1, fanCapability.fanCount)
            if settings.dualFanLinked || fanCount <= 1 {
                let targetFraction = max(settings.customFanFraction, safetyFloor)
                writeFanFraction(targetFraction)
            } else {
                // 使用启动时探测到的稳定风扇数量，避免某次快照读取失败时
                // 回退到联动值覆盖用户刚设置的分风扇转速
                let fan0Fraction = max(settings.fan0CustomFraction, safetyFloor)
                let fan1Fraction = max(settings.fan1CustomFraction, safetyFloor)
                var fractions = [fan0Fraction]
                for _ in 1..<fanCount {
                    fractions.append(fan1Fraction)
                }
                writeFanFractions(fractions)
            }

        case .smart:
            let rawFraction = FanCurveCalculator.fraction(
                forCelsius: primaryTemp,
                startTemp: Float(settings.smartStartTemp),
                fullSpeedTemp: Float(settings.smartFullTemp),
                minFraction: 0.0,
                maxFraction: 1.0
            )
            let safetyFloor = safetyPolicy.minimumFraction(forMaxTemp: primaryTemp)
            let targetFraction = max(rawFraction, safetyFloor)

            // EMA smoothing (alpha = 0.4) to prevent fan hunting / noise spikes
            if smoothedFraction == 0.0 {
                smoothedFraction = targetFraction
            } else {
                smoothedFraction = smoothedFraction * 0.6 + targetFraction * 0.4
            }

            // 安全下限必须立刻生效，不能被 EMA 平滑稀释
            writeFanFraction(max(smoothedFraction, safetyFloor))
        }
    }

    public func restoreSystemControl() {
        guard supportsFanControl, !isRestoreInFlight else { return }
        isRestoreInFlight = true
        Task { @MainActor in
            defer { self.isRestoreInFlight = false }
            await self.awaitPendingWrite()
            do {
                try await FanService.shared.restoreAuto(fanController: self.fanController)
                self.errorMessage = nil
                if self.isControlReleased {
                    self.releaseTracker.confirmHandoff()
                    self.isControlHandoffConfirmed = true
                }
            } catch {
                self.errorMessage = error.localizedDescription
                if self.isControlReleased {
                    self.releaseTracker.markHandoffFailed()
                    self.isControlHandoffConfirmed = false
                }
            }
        }
    }

    /// 等待在途转速写入结束（写入有超时，最多再等 1s）
    private func awaitPendingWrite(maxWait: TimeInterval = FanService.maxWriteDuration + 1.0) async {
        var waited: TimeInterval = 0
        while isWriteInFlight, waited < maxWait {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
    }
}
