import Testing
import Foundation
@testable import CalmBar

@Suite("Gatekeeper Unlocker Tests")
struct GatekeeperTests {
    @Test("Test removing com.apple.quarantine attribute")
    func testQuarantineRemoval() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("calmbar_gatekeeper_test_\(UUID().uuidString).txt")

        // 1. Create temporary file
        try "test gatekeeper quarantine removal".write(to: testFileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: testFileURL)
        }

        let filePath = testFileURL.path

        // 2. Set com.apple.quarantine xattr
        let setAttrProcess = Process()
        setAttrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        setAttrProcess.arguments = ["-w", "com.apple.quarantine", "0081;66be0000;Safari;test", filePath]
        try setAttrProcess.run()
        setAttrProcess.waitUntilExit()

        #expect(setAttrProcess.terminationStatus == 0)

        // Verify attribute is set
        let checkAttrProcess = Process()
        checkAttrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        checkAttrProcess.arguments = ["-p", "com.apple.quarantine", filePath]
        let pipe = Pipe()
        checkAttrProcess.standardOutput = pipe
        try checkAttrProcess.run()
        checkAttrProcess.waitUntilExit()
        #expect(checkAttrProcess.terminationStatus == 0)

        // 3. Call GatekeeperManager to unlock
        let manager = await GatekeeperManager.shared
        let result = await manager.unlockPath(testFileURL, deepSign: false)

        #expect(result.success == true)

        // 4. Verify attribute is removed
        let verifyProcess = Process()
        verifyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        verifyProcess.arguments = ["-p", "com.apple.quarantine", filePath]
        try verifyProcess.run()
        verifyProcess.waitUntilExit()

        // Exit status != 0 means attribute no longer exists
        #expect(verifyProcess.terminationStatus != 0)
    }

    @Test("Test non-existent file handling")
    func testNonExistentFile() async {
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_\(UUID().uuidString)")
        let manager = await GatekeeperManager.shared
        let result = await manager.unlockPath(fakeURL, deepSign: false)

        #expect(result.success == false)
        #expect(result.message.contains("不存在"))
    }
}
