import Testing
@testable import CalmBarKit
@testable import CalmBar

@Suite("SMC Data Format Tests")
struct SMCTests {
    @Test("Test Float byte conversion")
    func testSMCDataFormatFloat() {
        let testFloat: Float = 55.5
        var floatBytes = [UInt8](repeating: 0, count: 4)
        withUnsafeBytes(of: testFloat) { buf in
            for i in 0..<4 { floatBytes[i] = buf[i] }
        }

        let decoded = SMCDataFormat.float(from: floatBytes, size: 4)
        #expect(abs(decoded - 55.5) < 0.001)
    }

    @Test("Test SP78 fixed point format conversion")
    func testSMCDataFormatSP78() {
        let temp: Float = 45.0
        let rawVal = Int16(temp * 256.0)
        let bytes: [UInt8] = [UInt8(rawVal >> 8), UInt8(rawVal & 0xFF)]
        let decoded = SMCDataFormat.float(from: bytes, size: 2)
        #expect(abs(decoded - 45.0) < 0.01)
    }

    @Test("Test Float roundtrip encoding and decoding")
    func testSMCDataFormatRoundTrip() {
        let original: Float = 62.0
        let encoded = SMCDataFormat.bytes(from: original, size: 4)
        let decoded = SMCDataFormat.float(from: encoded, size: 4)
        #expect(abs(decoded - original) < 0.001)
    }
}
