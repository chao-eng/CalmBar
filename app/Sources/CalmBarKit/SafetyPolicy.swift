import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 温控安全阈值默认值。
///
/// Apple Silicon 的 `Tp*` / `Tg*` 是芯片结温，持续负载下 95~105°C 属于常态，
/// 因此「临界档」与「交还系统」硬限都比 Intel 机型更高：
/// - 临界档：仍然由 CalmBar 强制 100% 转速，不放弃控制权；
/// - 硬限：连续超限 `releaseHoldSeconds` 后才交还系统自动控制。
public enum ThermalSafetyDefaults {
    /// 运行期判断是否为 Apple Silicon（Rosetta 下 `#if arch` 会误判，故用 sysctl）
    public static let isAppleSilicon: Bool = {
        #if canImport(Darwin)
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        #endif
        return false
    }()

    /// 进入临界档（强制 100%）的温度
    public static let criticalTemp: Float = isAppleSilicon ? 105.0 : 98.0

    /// 硬限：持续超过该温度才把控制权交还系统
    public static let releaseTemp: Float = isAppleSilicon ? 110.0 : 102.0
}

public struct ThermalSafetyConfig: Sendable, Codable {
    public var startTemp: Float
    public var fullSpeedTemp: Float
    public var lowFloorTemp: Float
    public var highFloorTemp: Float
    public var warningTemp: Float
    /// 临界档：CalmBar 仍持有控制权，强制 100% 转速
    public var criticalTemp: Float
    /// 硬限：连续超过该温度达到 `releaseHoldSeconds` 后交还系统
    public var releaseTemp: Float
    public var hysteresisTemp: Float
    /// 超过硬限后需要持续多久才真正交还系统（秒）
    public var releaseHoldSeconds: TimeInterval

    public init(
        startTemp: Float = 45.0,
        fullSpeedTemp: Float = 80.0,
        lowFloorTemp: Float = 75.0,
        highFloorTemp: Float = 85.0,
        warningTemp: Float = 90.0,
        criticalTemp: Float = ThermalSafetyDefaults.criticalTemp,
        releaseTemp: Float = ThermalSafetyDefaults.releaseTemp,
        hysteresisTemp: Float = 3.0,
        releaseHoldSeconds: TimeInterval = 30.0
    ) {
        self.startTemp = startTemp
        self.fullSpeedTemp = fullSpeedTemp
        self.lowFloorTemp = lowFloorTemp
        self.highFloorTemp = highFloorTemp
        self.warningTemp = warningTemp
        self.criticalTemp = criticalTemp
        self.releaseTemp = releaseTemp
        self.hysteresisTemp = hysteresisTemp
        self.releaseHoldSeconds = releaseHoldSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case startTemp, fullSpeedTemp, lowFloorTemp, highFloorTemp
        case warningTemp, criticalTemp, releaseTemp, hysteresisTemp, releaseHoldSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThermalSafetyConfig()
        self.init(
            startTemp: try c.decodeIfPresent(Float.self, forKey: .startTemp) ?? fallback.startTemp,
            fullSpeedTemp: try c.decodeIfPresent(Float.self, forKey: .fullSpeedTemp) ?? fallback.fullSpeedTemp,
            lowFloorTemp: try c.decodeIfPresent(Float.self, forKey: .lowFloorTemp) ?? fallback.lowFloorTemp,
            highFloorTemp: try c.decodeIfPresent(Float.self, forKey: .highFloorTemp) ?? fallback.highFloorTemp,
            warningTemp: try c.decodeIfPresent(Float.self, forKey: .warningTemp) ?? fallback.warningTemp,
            criticalTemp: try c.decodeIfPresent(Float.self, forKey: .criticalTemp) ?? fallback.criticalTemp,
            releaseTemp: try c.decodeIfPresent(Float.self, forKey: .releaseTemp) ?? fallback.releaseTemp,
            hysteresisTemp: try c.decodeIfPresent(Float.self, forKey: .hysteresisTemp) ?? fallback.hysteresisTemp,
            releaseHoldSeconds: try c.decodeIfPresent(TimeInterval.self, forKey: .releaseHoldSeconds) ?? fallback.releaseHoldSeconds
        )
    }
}

public enum SafetyAction: String, Sendable, Codable {
    case none
    case raiseLowFloor
    case raiseHighFloor
    /// 预警档（≥ warningTemp）：保证 95% 下限
    case forceEmergencyCool
    /// 临界档（≥ criticalTemp）：强制 100%，控制权仍在 CalmBar
    case forceCriticalCool
    /// 硬限持续超限：交还系统自动控制
    case restoreAuto
}

public enum SafetyFloorTier: Int, Sendable, Comparable {
    case none = 0
    case low = 1
    case high = 2
    case emergency = 3
    case critical = 4

    public static func < (lhs: SafetyFloorTier, rhs: SafetyFloorTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SafetyPolicy: Sendable {
    public var config: ThermalSafetyConfig
    public private(set) var activeFloor: SafetyFloorTier = .none

    /// 首次超过硬限的时间戳；回落即清零，用于「持续超限」判定
    private var overReleaseSince: Date?

    public init(config: ThermalSafetyConfig = ThermalSafetyConfig()) {
        self.config = config
    }

    public mutating func evaluate(maxTemp: Float?, now: Date = Date()) -> SafetyAction {
        guard let maxTemp else {
            activeFloor = .none
            overReleaseSince = nil
            return .none
        }

        // 硬限释放：只有「持续」超过 releaseTemp 才交还系统，
        // 单次尖峰仍然由 CalmBar 强制 100% 压制。
        if maxTemp >= config.releaseTemp {
            if let since = overReleaseSince {
                if now.timeIntervalSince(since) >= config.releaseHoldSeconds {
                    activeFloor = .critical
                    return .restoreAuto
                }
            } else {
                overReleaseSince = now
            }
        } else {
            overReleaseSince = nil
        }

        let h = config.hysteresisTemp
        var target: SafetyFloorTier = .none

        if maxTemp >= config.criticalTemp
            || (activeFloor >= .critical && maxTemp >= config.criticalTemp - h)
        {
            target = .critical
        } else if maxTemp >= config.warningTemp
            || (activeFloor >= .emergency && maxTemp >= config.warningTemp - h)
        {
            target = .emergency
        } else if maxTemp >= config.highFloorTemp
            || (activeFloor >= .high && maxTemp >= config.highFloorTemp - h)
        {
            target = .high
        } else if maxTemp >= config.lowFloorTemp
            || (activeFloor >= .low && maxTemp >= config.lowFloorTemp - h)
        {
            target = .low
        }

        activeFloor = target
        switch target {
        case .critical: return .forceCriticalCool
        case .emergency: return .forceEmergencyCool
        case .high: return .raiseHighFloor
        case .low: return .raiseLowFloor
        case .none: return .none
        }
    }

    public func minimumFraction(forMaxTemp maxTemp: Float? = nil) -> Double {
        let tier: SafetyFloorTier
        if activeFloor != .none {
            tier = activeFloor
        } else if let t = maxTemp {
            if t >= config.criticalTemp { tier = .critical }
            else if t >= config.warningTemp { tier = .emergency }
            else if t >= config.highFloorTemp { tier = .high }
            else if t >= config.lowFloorTemp { tier = .low }
            else { tier = .none }
        } else {
            tier = .none
        }

        switch tier {
        case .critical: return 1.0
        case .emergency: return 0.95
        case .high: return 0.75
        case .low: return 0.45
        case .none: return 0.0
        }
    }

    /// 是否已满足「持续超过硬限」的交还条件（不改变档位状态）
    public func shouldReleaseControl(maxTemp: Float?, now: Date = Date()) -> Bool {
        guard let maxTemp, maxTemp >= config.releaseTemp else { return false }
        guard let since = overReleaseSince else { return false }
        return now.timeIntervalSince(since) >= config.releaseHoldSeconds
    }

    /// 硬限回落后的恢复阈值，避免在硬限附近反复接管/放权
    public var releaseRecoverTemp: Float {
        config.releaseTemp - config.hysteresisTemp
    }

    /// 重置硬限计时（用户显式强制散热时调用）
    public mutating func resetReleaseCountdown() {
        overReleaseSince = nil
    }

    public mutating func reset() {
        activeFloor = .none
        overReleaseSince = nil
    }
}

public enum FanCurveCalculator {
    /// Linear interpolation with clamping and safety floor
    public static func fraction(
        forCelsius temp: Float,
        startTemp: Float = 45.0,
        fullSpeedTemp: Float = 80.0,
        minFraction: Double = 0.0,
        maxFraction: Double = 1.0
    ) -> Double {
        if temp <= startTemp {
            return minFraction
        }
        if temp >= fullSpeedTemp {
            return maxFraction
        }
        let span = max(1.0, fullSpeedTemp - startTemp)
        let ratio = Double((temp - startTemp) / span)
        return minFraction + ratio * (maxFraction - minFraction)
    }
}

/// Hardware safety constraints for battery charging & discharge protection
public struct BatterySafetyPolicy: Sendable {
    /// Absolute minimum battery percentage below which force discharge must terminate immediately
    public static let absoluteMinimumPercentage: Int = 15

    /// Maximum safe battery temperature in Celsius; above this, stop inhibiting/discharging to prevent thermal runaway
    public static let maxBatteryTemperatureCelsius: Double = 45.0

    /// Evaluates whether an active discharge or charging inhibit must be aborted for hardware safety
    public static func shouldEmergencyAbort(currentPercentage: Int, batteryTempCelsius: Double? = nil) -> (abort: Bool, reason: String?) {
        if currentPercentage <= absoluteMinimumPercentage {
            return (true, "电池电量过低 (\(currentPercentage)%)，已触发底层安全熔断，立即恢复充电")
        }
        if let temp = batteryTempCelsius, temp >= maxBatteryTemperatureCelsius {
            return (true, "电池温度过高 (\(String(format: "%.1f", temp))°C)，已触发过热安全保护，恢复官方充电策略")
        }
        return (false, nil)
    }
}
