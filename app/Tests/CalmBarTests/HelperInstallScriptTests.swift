import Foundation
import Testing
@testable import CalmBar

@Suite("Helper install script")
struct HelperInstallScriptTests {
    @Test("安装脚本通过 sh -n 语法检查")
    @MainActor
    func scriptSyntax() throws {
        let script = HelperClient.installHelperScript(
            helperBinaryPath: "/tmp/a b'c/CalmBarHelper",
            clientRequirement: "identifier \"com.chaoeng.CalmBar\" and cdhash H\"0011\"",
            clientExecutablePath: "/Applications/A B.app/Contents/MacOS/CalmBar"
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calmbar-install-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", url.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
