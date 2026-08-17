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
        var policy = SafetyPolicy()

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

        // Critical temp (> 98°C)
        #expect(policy.evaluate(maxTemp: 99.0) == .restoreAuto)
        #expect(policy.activeFloor == .critical)
    }
}
