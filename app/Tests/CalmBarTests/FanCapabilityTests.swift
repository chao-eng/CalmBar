import Testing
@testable import CalmBarKit

@Suite("FanCapability Hardware Model Tests")
struct FanCapabilityTests {
    @Test("FanCapability fanless semantics")
    func testFanlessSemantics() {
        let cap = FanCapability.fanless
        #expect(cap.isFanless)
        #expect(cap.fanCount == 0)
        #expect(!cap.supportsFanControl)
    }

    @Test("FanCapability hasFans semantics")
    func testHasFansSemantics() {
        let single = FanCapability.hasFans(1)
        #expect(!single.isFanless)
        #expect(single.fanCount == 1)
        #expect(single.supportsFanControl)

        let dual = FanCapability.hasFans(2)
        #expect(!dual.isFanless)
        #expect(dual.fanCount == 2)
        #expect(dual.supportsFanControl)
    }

    @Test("FanCapability unknown semantics")
    func testUnknownSemantics() {
        let cap = FanCapability.unknown
        #expect(!cap.isFanless)
        #expect(cap.fanCount == 0)
        // `.unknown`（探测失败）不视为可控制，与文档「交由上层按不可用处理」一致
        #expect(!cap.supportsFanControl)
        #expect(cap.isUnknown)
    }

    @Test("FanCapability equatable conformance")
    func testEquatable() {
        #expect(FanCapability.hasFans(2) == .hasFans(2))
        #expect(FanCapability.hasFans(1) != .hasFans(2))
        #expect(FanCapability.fanless == .fanless)
        #expect(FanCapability.fanless != .hasFans(0))
    }

    @Test("SMCHardwareConfig carries capability with unknown default")
    func testSMCHardwareConfigCapability() {
        let defaulted = SMCHardwareConfig(modeKeyFormat: SMCFanKey.modeLower, ftstAvailable: false)
        #expect(defaulted.capability == .unknown)
        // `.unknown` 默认值同样不支持风扇控制
        #expect(!defaulted.capability.supportsFanControl)

        let detected = SMCHardwareConfig(
            modeKeyFormat: SMCFanKey.modeLower,
            ftstAvailable: false,
            capability: .fanless
        )
        #expect(detected.capability == .fanless)
        #expect(!detected.capability.supportsFanControl)
    }
}
