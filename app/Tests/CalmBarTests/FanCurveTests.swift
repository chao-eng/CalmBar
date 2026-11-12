import Foundation
import Testing
@testable import CalmBarKit
@testable import CalmBar

@Suite("Fan Curve and Thermal Safety Policy Tests")
struct FanCurveTests {
    @Test("Test Fan Curve linear interpolation")
    func testCurveLinearInterpolation() {
        let start: Float = 40.0
        let full: Float = 80.0

        let fLow = FanCurveCalculator.fraction(forCelsius: 35.0, startTemp: start, fullSpeedTemp: full)
        #expect(abs(fLow - 0.0) < 0.001)

        let fMid = FanCurveCalculator.fraction(forCelsius: 60.0, startTemp: start, fullSpeedTemp: full)
        #expect(abs(fMid - 0.5) < 0.001)

        let fHigh = FanCurveCalculator.fraction(forCelsius: 90.0, startTemp: start, fullSpeedTemp: full)
        #expect(abs(fHigh - 1.0) < 0.001)
    }

    @Test("Test Thermal Safety Policy Hysteresis and Escalation")
    func testSafetyPolicyHysteresis() {
        // 固定阈值，避免测试结果依赖运行机是否 Apple Silicon
        var policy = SafetyPolicy(config: ThermalSafetyConfig(
            criticalTemp: 98.0,
            releaseTemp: 102.0,
            hysteresisTemp: 3.0,
            releaseHoldSeconds: 30.0
        ))

        // Normal temp
        #expect(policy.evaluate(maxTemp: 50.0) == .none)
        #expect(policy.activeFloor == .none)

        // Low floor triggered (> 75°C)
        #expect(policy.evaluate(maxTemp: 76.0) == .raiseLowFloor)
        #expect(policy.activeFloor == .low)

        // Temp drops slightly to 74°C, but hysteresis is 3°C so it should stay at low
        #expect(policy.evaluate(maxTemp: 74.0) == .raiseLowFloor)
        #expect(policy.activeFloor == .low)

        // Temp drops to 70°C (below 75 - 3 = 72), should return to none
        #expect(policy.evaluate(maxTemp: 70.0) == .none)
        #expect(policy.activeFloor == .none)

        // Emergency temp (> 90°C)
        #expect(policy.evaluate(maxTemp: 91.0) == .forceEmergencyCool)
        #expect(policy.activeFloor == .emergency)

        // Critical temp (>= 98°C) 仍然由 CalmBar 控制，强制 100%
        #expect(policy.evaluate(maxTemp: 99.0) == .forceCriticalCool)
        #expect(policy.activeFloor == .critical)
        #expect(policy.minimumFraction() == 1.0)
    }

    @Test("Critical tier forces full speed instead of releasing control")
    func testCriticalTierForcesMaxCooling() {
        var policy = SafetyPolicy(config: ThermalSafetyConfig(
            criticalTemp: 98.0,
            releaseTemp: 102.0,
            releaseHoldSeconds: 30.0
        ))

        // 单次超过 100°C 不允许交还系统
        #expect(policy.evaluate(maxTemp: 101.0) == .forceCriticalCool)
        #expect(policy.minimumFraction(forMaxTemp: 101.0) == 1.0)

        // 未进入临界档时，预警档仍是 95% 下限
        let fresh = SafetyPolicy(config: policy.config)
        #expect(fresh.minimumFraction(forMaxTemp: 95.0) == 0.95)
    }

    @Test("Hard limit release requires sustained over-temperature")
    func testReleaseRequiresSustainedHardLimit() {
        var policy = SafetyPolicy(config: ThermalSafetyConfig(
            criticalTemp: 98.0,
            releaseTemp: 102.0,
            hysteresisTemp: 3.0,
            releaseHoldSeconds: 30.0
        ))
        let t0 = Date()

        #expect(policy.evaluate(maxTemp: 103.0, now: t0) == .forceCriticalCool)
        #expect(policy.evaluate(maxTemp: 103.0, now: t0.addingTimeInterval(10)) == .forceCriticalCool)
        #expect(policy.shouldReleaseControl(maxTemp: 103.0, now: t0.addingTimeInterval(10)) == false)
        #expect(policy.shouldReleaseControl(maxTemp: 103.0, now: t0.addingTimeInterval(31)) == true)
        #expect(policy.evaluate(maxTemp: 103.0, now: t0.addingTimeInterval(31)) == .restoreAuto)

        // 尖峰不算“持续超限”：回落后重新计时
        var spike = SafetyPolicy(config: ThermalSafetyConfig(
            criticalTemp: 98.0,
            releaseTemp: 102.0,
            releaseHoldSeconds: 30.0
        ))
        _ = spike.evaluate(maxTemp: 103.0, now: t0)
        _ = spike.evaluate(maxTemp: 99.0, now: t0.addingTimeInterval(5))
        #expect(spike.evaluate(maxTemp: 103.0, now: t0.addingTimeInterval(10)) == .forceCriticalCool)
    }

    @Test("Platform-specific critical and release defaults")
    func testPlatformDefaults() {
        if ThermalSafetyDefaults.isAppleSilicon {
            #expect(ThermalSafetyDefaults.criticalTemp == 105.0)
            #expect(ThermalSafetyDefaults.releaseTemp == 110.0)
        } else {
            #expect(ThermalSafetyDefaults.criticalTemp == 98.0)
            #expect(ThermalSafetyDefaults.releaseTemp == 102.0)
        }
        #expect(ThermalSafetyDefaults.releaseTemp > ThermalSafetyDefaults.criticalTemp)
    }
}
