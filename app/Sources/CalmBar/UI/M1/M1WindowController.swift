import AppKit

// MARK: - M1 启动入口：--m1 打开独立骨架窗口，不启动现有面板

@MainActor
final class M1WindowController {
    static let shared = M1WindowController()

    private init() {}

    func presentIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--m1") || args.contains("--m2") || args.contains("--m3") || args.contains("--m4") || args.contains("--m5") || args.contains("--m5-stress") || args.contains("--m6") || args.contains("--m6-empty") || args.contains("--m7") || args.contains("--m7-empty") else { return false }
        M1Driver.shared.present()
        return true
    }
}
