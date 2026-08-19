import Testing
import Foundation
@testable import CalmBarKit
@testable import CalmBar

@Suite("Battery Safety and Permission Center Tests")
struct BatterySafetyTests {
    @Test("Test Battery Safety Policy critical low percentage abort")
    func testLowBatteryAbort() {
        let result15 = BatterySafetyPolicy.shouldEmergencyAbort(currentPercentage: 15, batteryTempCelsius: 32.0)
        #expect(result15.abort == true)
        #expect(result15.reason?.contains("熔断") == true)

        let result10 = BatterySafetyPolicy.shouldEmergencyAbort(currentPercentage: 10, batteryTempCelsius: 30.0)
        #expect(result10.abort == true)

        let result50 = BatterySafetyPolicy.shouldEmergencyAbort(currentPercentage: 50, batteryTempCelsius: 30.0)
        #expect(result50.abort == false)
    }

    @Test("Test Battery Safety Policy over-temperature abort")
    func testHighTemperatureAbort() {
        let resultOverheat = BatterySafetyPolicy.shouldEmergencyAbort(currentPercentage: 70, batteryTempCelsius: 46.5)
        #expect(resultOverheat.abort == true)
        #expect(resultOverheat.reason?.contains("过热") == true)

        let resultNormal = BatterySafetyPolicy.shouldEmergencyAbort(currentPercentage: 70, batteryTempCelsius: 38.0)
        #expect(resultNormal.abort == false)
    }

    @Test("Test PermissionType enumeration and attributes")
    @MainActor
    func testPermissionTypes() {
        let types = PermissionType.allCases
        #expect(types.count == 4)
        #expect(types.contains(.accessibility))
        #expect(types.contains(.privilegedHelper))
        #expect(types.contains(.screenRecording))
        #expect(types.contains(.fullDiskAccess))

        for t in types {
            #expect(!t.title.isEmpty)
            #expect(!t.purposeDescription.isEmpty)
            #expect(!t.iconName.isEmpty)
        }
    }
}
