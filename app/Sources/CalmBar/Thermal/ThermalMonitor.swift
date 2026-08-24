import Foundation
import Combine
import CalmBarKit

@MainActor
public final class ThermalMonitor: ObservableObject {
    public static let shared = ThermalMonitor()

    @Published public private(set) var primaryTemp: Float = 0.0
    @Published public private(set) var cpuTemp: Float = 0.0
    @Published public private(set) var gpuTemp: Float = 0.0
    @Published public private(set) var batteryTemp: Float = 0.0
    @Published public private(set) var allTemps: [TemperatureReading] = []
    @Published public private(set) var fanSnapshots: [FanSnapshot] = []
    @Published public private(set) var isSMCConnected: Bool = false
    @Published public private(set) var isFanControlAuthorized: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var currentSafetyAction: SafetyAction = .none

    private var fanController: FanController?
    private var safetyPolicy = SafetyPolicy()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

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
            self.fanController = FanController(connection: conn)
            self.isSMCConnected = true
            self.errorMessage = nil
        } catch {
            self.fanController = nil
            self.isSMCConnected = false
            self.errorMessage = error.localizedDescription
            NSLog("ThermalMonitor: SMC init error - \(error.localizedDescription)")
        }
    }

    public func checkAuthorization() {
        if getuid() == 0 {
            self.isFanControlAuthorized = true
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
            .sink { [weak self] _ in
                Task { @MainActor in
                    if AppSettings.shared.thermalEnabled {
                        self?.applyCurrentMode()
                    }
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$customFanFraction
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    if AppSettings.shared.thermalEnabled && AppSettings.shared.fanPreset == .manual {
                        self?.applyCurrentMode()
                    }
                }
            }
            .store(in: &cancellables)

        HelperClient.shared.$isHelperAvailable
            .sink { [weak self] available in
                Task { @MainActor in
                    if available || getuid() == 0 {
                        self?.isFanControlAuthorized = true
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

        if let fans = try? controller.allFans() {
            self.fanSnapshots = fans
        }

        // Evaluate safety policy
        let safetyAction = safetyPolicy.evaluate(maxTemp: maxPrimary)
        self.currentSafetyAction = safetyAction
    }

    private func writeFanFraction(_ fraction: Double) {
        Task { @MainActor in
            do {
                try await FanService.shared.setFanFraction(fraction, fanController: self.fanController)
                self.isFanControlAuthorized = true
                self.errorMessage = nil
            } catch {
                if getuid() != 0 && !self.isFanControlAuthorized {
                    self.isFanControlAuthorized = false
                }
            }
        }
    }

    public func applyCurrentMode() {
        let settings = AppSettings.shared

        // If safety critical, restore Auto
        if currentSafetyAction == .restoreAuto {
            restoreSystemControl()
            return
        }

        switch settings.fanPreset {
        case .auto:
            restoreSystemControl()

        case .manual:
            let safetyFloor = safetyPolicy.minimumFraction(forMaxTemp: primaryTemp)
            let targetFraction = max(settings.customFanFraction, safetyFloor)
            writeFanFraction(targetFraction)

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

            writeFanFraction(smoothedFraction)
        }
    }

    public func restoreSystemControl() {
        Task { @MainActor in
            try? await FanService.shared.restoreAuto(fanController: self.fanController)
        }
    }
}
