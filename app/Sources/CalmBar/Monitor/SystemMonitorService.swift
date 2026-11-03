import Combine
import Foundation

// MARK: - 监控服务（采样节流 / 环形历史 / 告警入口）

@MainActor
final class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    enum Demand: Hashable {
        case panel
        case menuBar
        case alerts
    }

    enum MetricKind: String, CaseIterable, Sendable {
        case cpu
        case gpu
        case memory
        case disk
        case network
        case temperature
        case battery
    }

    @Published private(set) var snapshot: MonitorSample?
    @Published private(set) var lastError: String?
    @Published private(set) var isSampling = false
    @Published private(set) var consecutiveFailures = 0
    @Published private(set) var activeInterval: TimeInterval = 0

    private(set) var history = MonitorHistory(capacity: 3600)

    private let settings = AppSettings.shared
    private var sampler = SystemSampler()
    private var timer: Timer?
    private var demands: Set<Demand> = []
    private var lastSampleAt: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeSettings()
        observeOperationalState()
        refreshAlertsDemand()
        rebuildTimer()
    }

    // MARK: 需求管理（面板 / 菜单栏 / 告警）

    func acquire(_ demand: Demand) {
        demands.insert(demand)
        rebuildTimer()
    }

    func release(_ demand: Demand) {
        demands.remove(demand)
        rebuildTimer()
    }

    func setMenuBarDemand(_ active: Bool) {
        if active {
            demands.insert(.menuBar)
        } else {
            demands.remove(.menuBar)
        }
        rebuildTimer()
    }

    var isStale: Bool {
        guard let lastSampleAt else { return true }
        let threshold = max(6, activeInterval * 3)
        return Date().timeIntervalSince(lastSampleAt) > threshold
    }

    func samples(in range: MonitorRange) -> [MonitorSample] {
        history.downsampled(in: range)
    }

    var availableMetrics: [MetricKind] {
        guard let snapshot else { return [] }
        var metrics: [MetricKind] = [.cpu, .memory, .disk, .network]
        if settings.systemMonitorShowGPU && snapshot.gpuUsage != nil {
            metrics.insert(.gpu, at: 1)
        }
        if snapshot.cpuTemp != nil {
            metrics.append(.temperature)
        }
        if snapshot.batteryLevel != nil {
            metrics.append(.battery)
        }
        return metrics
    }

    // MARK: 采样

    private func observeSettings() {
        Publishers.MergeMany(
            settings.$systemMonitorEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$monitorAlertsEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$systemMonitorSampleInterval.map { _ in () }.eraseToAnyPublisher(),
            settings.$systemMonitorShowGPU.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshAlertsDemand()
            self?.rebuildTimer()
        }
        .store(in: &cancellables)
    }

    private func observeOperationalState() {
        SystemEventCoordinator.shared.$isOperational
            .receive(on: RunLoop.main)
            .sink { [weak self] operational in
                guard let self else { return }
                if operational {
                    self.lastSampleAt = nil
                    self.rebuildTimer()
                } else {
                    self.stopTimer()
                    MonitorAlertEngine.shared.resetTracking()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshAlertsDemand() {
        let shouldSampleForAlerts = settings.systemMonitorEnabled && settings.monitorAlertsEnabled
        if shouldSampleForAlerts {
            demands.insert(.alerts)
        } else {
            demands.remove(.alerts)
        }
    }

    private var effectiveInterval: TimeInterval {
        let configured = TimeInterval(max(1, settings.systemMonitorSampleInterval))
        // BR-19：面板关闭后降频，最低 3s
        return demands.contains(.panel) ? configured : max(3, configured)
    }

    private func rebuildTimer() {
        stopTimer()
        guard !demands.isEmpty,
              settings.systemMonitorEnabled,
              SystemEventCoordinator.shared.isOperational
        else {
            isSampling = false
            activeInterval = 0
            // 监控关闭时清空快照与历史，避免菜单栏继续展示冻结的旧读数
            if !settings.systemMonitorEnabled {
                resetSamples()
            }
            return
        }

        let interval = effectiveInterval
        activeInterval = interval
        isSampling = true

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = min(0.2, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if snapshot == nil || lastSampleAt == nil {
            tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isSampling = false
    }

    private func tick() {
        guard SystemEventCoordinator.shared.isOperational else { return }

        let thermalTemp = ThermalMonitor.shared.cpuTemp
        let cpuTemp: Double? = thermalTemp > 0 ? Double(thermalTemp) : nil
        let batteryLevel: Int? = BatteryMonitor.shared.hasBattery
            ? BatteryMonitor.shared.currentPercentage
            : nil

        let sample = sampler.sample(cpuTemp: cpuTemp, batteryLevel: batteryLevel)
        guard sample.diskTotal > 0 else {
            registerFailure("磁盘数据不可读")
            return
        }

        let recoveredFromDegrade = consecutiveFailures >= 5
        consecutiveFailures = 0
        lastError = nil
        lastSampleAt = sample.timestamp
        snapshot = sample
        history.append(sample)
        MonitorAlertEngine.shared.ingest(sample)

        // 失败降频后恢复成功需重建定时器，否则会一直停留在 5s 低频率
        if recoveredFromDegrade {
            rebuildTimer()
        }
    }

    private func resetSamples() {
        snapshot = nil
        history.removeAll()
        lastSampleAt = nil
        consecutiveFailures = 0
        lastError = nil
    }

    private func registerFailure(_ message: String) {
        consecutiveFailures += 1
        lastError = message
        guard consecutiveFailures >= 5, activeInterval < 5 else { return }
        // 连续 5 次失败自动降频，保留上一帧并标注延迟
        stopTimer()
        activeInterval = 5
        isSampling = true
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
