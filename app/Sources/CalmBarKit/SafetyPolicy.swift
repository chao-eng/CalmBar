import Foundation

public struct ThermalSafetyConfig: Sendable, Codable {
    public var startTemp: Float
    public var fullSpeedTemp: Float
    public var lowFloorTemp: Float
    public var highFloorTemp: Float
    public var warningTemp: Float
    public var criticalTemp: Float
    public var hysteresisTemp: Float

    public init(
        startTemp: Float = 45.0,
        fullSpeedTemp: Float = 80.0,
        lowFloorTemp: Float = 75.0,
        highFloorTemp: Float = 85.0,
        warningTemp: Float = 90.0,
        criticalTemp: Float = 98.0,
        hysteresisTemp: Float = 3.0
    ) {
        self.startTemp = startTemp
        self.fullSpeedTemp = fullSpeedTemp
        self.lowFloorTemp = lowFloorTemp
        self.highFloorTemp = highFloorTemp
        self.warningTemp = warningTemp
        self.criticalTemp = criticalTemp
        self.hysteresisTemp = hysteresisTemp
    }
}

public enum SafetyAction: String, Sendable, Codable {
    case none
    case raiseLowFloor
    case raiseHighFloor
    case forceEmergencyCool
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

    public init(config: ThermalSafetyConfig = ThermalSafetyConfig()) {
        self.config = config
    }

    public mutating func evaluate(maxTemp: Float?) -> SafetyAction {
        guard let maxTemp else { return .none }

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
        case .critical: return .restoreAuto
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
            if t >= config.warningTemp { tier = .emergency }
            else if t >= config.highFloorTemp { tier = .high }
            else if t >= config.lowFloorTemp { tier = .low }
            else { tier = .none }
        } else {
            tier = .none
        }

        switch tier {
        case .critical, .emergency: return 0.95
        case .high: return 0.75
        case .low: return 0.45
        case .none: return 0.0
        }
    }

    public mutating func reset() {
        activeFloor = .none
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

