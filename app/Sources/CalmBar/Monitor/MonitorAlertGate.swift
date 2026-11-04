import Foundation

// MARK: - 告警类型与规则（PRD A-6 / UC-M04）

enum MonitorAlertType: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case disk
    case battery
    case temperature

    var id: String { rawValue }

    var titleZH: String {
        switch self {
        case .cpu: "CPU 使用率"
        case .memory: "内存压力"
        case .disk: "磁盘剩余"
        case .battery: "电池电量"
        case .temperature: "温度"
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .battery: "battery.25"
        case .temperature: "thermometer.medium"
        }
    }
}

struct MonitorAlertRule: Sendable {
    let type: MonitorAlertType
    var isEnabled: Bool
    /// CPU / 电池 / 温度按百分比，磁盘按 GB；内存压力不使用阈值
    var threshold: Double
    var sustainSeconds: Int
    var cooldownSeconds: Int
}

struct MonitorAlertEvent: Identifiable, Sendable {
    let type: MonitorAlertType
    let currentValue: Double
    let thresholdValue: Double
    let message: String
    let firedAt: Date

    var id: String { "\(type.rawValue)-\(firedAt.timeIntervalSince1970)" }

    var titleZH: String {
        "\(type.titleZH)提醒"
    }
}

// MARK: - 告警门控（BR-27 / BR-28 / BR-30 / BR-31）

struct MonitorAlertGate {
    private struct Tracking {
        var overCount = 0
        var overSince: Date?
        var lastFiredAt: Date?
    }

    private var rules: [MonitorAlertRule]
    private var tracking: [MonitorAlertType: Tracking] = [:]

    init(rules: [MonitorAlertRule]) {
        self.rules = rules
    }

    mutating func updateRules(_ rules: [MonitorAlertRule]) {
        self.rules = rules
        let enabled = Set(rules.filter(\.isEnabled).map(\.type))
        tracking = tracking.filter { enabled.contains($0.key) }
    }

    /// BR-29：睡眠 / 锁屏期间丢弃确认进度，唤醒后不补发
    mutating func resetTracking() {
        tracking = tracking.mapValues { Tracking(lastFiredAt: $0.lastFiredAt) }
    }

    mutating func resetAll() {
        tracking.removeAll()
    }

    /// 返回本次需要发送的告警（每个类型至多一条）
    mutating func ingest(
        _ sample: MonitorSample,
        now: Date,
        isExternalPowerConnected: Bool
    ) -> [MonitorAlertEvent] {
        var events: [MonitorAlertEvent] = []

        for rule in rules where rule.isEnabled {
            guard let breach = breach(for: rule, sample: sample, isExternalPowerConnected: isExternalPowerConnected)
            else {
                // 未越阈：清空连续确认进度，保留冷却时间
                if var state = tracking[rule.type] {
                    state.overCount = 0
                    state.overSince = nil
                    tracking[rule.type] = state
                }
                continue
            }

            var state = tracking[rule.type] ?? Tracking()
            state.overCount += 1
            if state.overSince == nil {
                state.overSince = now
            }

            var shouldFire = state.overCount >= 2
            if shouldFire, rule.sustainSeconds > 0, let since = state.overSince {
                shouldFire = now.timeIntervalSince(since) >= Double(rule.sustainSeconds)
            }
            if shouldFire, let last = state.lastFiredAt, rule.cooldownSeconds > 0 {
                shouldFire = now.timeIntervalSince(last) >= Double(rule.cooldownSeconds)
            }

            if shouldFire {
                state.lastFiredAt = now
                state.overCount = 0
                state.overSince = nil
                events.append(MonitorAlertEvent(
                    type: rule.type,
                    currentValue: breach.current,
                    thresholdValue: rule.threshold,
                    message: breach.message,
                    firedAt: now
                ))
            }
            tracking[rule.type] = state
        }

        return events
    }

    private func breach(
        for rule: MonitorAlertRule,
        sample: MonitorSample,
        isExternalPowerConnected: Bool
    ) -> (current: Double, message: String)? {
        switch rule.type {
        case .cpu:
            let percent = sample.cpuUsage * 100
            guard percent >= rule.threshold else { return nil }
            return (
                percent,
                "当前 CPU 使用率 \(Int(percent.rounded()))%，阈值 \(Int(rule.threshold))%。建议关闭占用较高的应用或检查后台任务。"
            )
        case .memory:
            guard sample.memoryPressure > .normal else { return nil }
            let value = sample.memoryPressure == .critical ? 2.0 : 1.0
            return (
                value,
                "内存压力\(sample.memoryPressure.titleZH)，建议关闭占用较高的应用，或重启长期运行的程序。"
            )
        case .disk:
            let freeGB = Double(sample.diskFree) / 1_000_000_000
            guard freeGB < rule.threshold else { return nil }
            return (
                freeGB,
                "当前磁盘可用 \(String(format: "%.1f", freeGB))GB，低于阈值 \(Int(rule.threshold))GB。建议打开清理工具释放空间。"
            )
        case .battery:
            guard !isExternalPowerConnected, let level = sample.batteryLevel else { return nil }
            guard Double(level) < rule.threshold else { return nil }
            return (
                Double(level),
                "当前电量 \(level)%，低于阈值 \(Int(rule.threshold))%。建议连接电源或降低屏幕亮度。"
            )
        case .temperature:
            guard let temp = sample.cpuTemp, temp >= rule.threshold else { return nil }
            return (
                temp,
                "当前温度 \(Int(temp.rounded()))°C，达到阈值 \(Int(rule.threshold))°C。建议检查散热通风并降低负载。"
            )
        }
    }
}
