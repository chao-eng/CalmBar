import AppKit
import SwiftUI

@MainActor
final class SpikeWindowController {
    static let shared = SpikeWindowController()

    private var window: NSWindow?

    private init() {}

    // 通过 `--spike tabbar|height` 或环境变量 `CALMBAR_SPIKE=tabbar|height` 触发
    static func requestedMode() -> String? {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--spike"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return ProcessInfo.processInfo.environment["CALMBAR_SPIKE"]
    }

    // 返回 true 表示已进入 Spike 模式，应跳过常规启动流程
    func presentIfRequested() -> Bool {
        guard let mode = Self.requestedMode() else { return false }
        SpikeTrace.log("arguments=\(CommandLine.arguments)", mode: "boot")

        let policyOK = NSApp.setActivationPolicy(.regular)
        SpikeTrace.log("activationPolicy regular=\(policyOK) mode=\(mode)", mode: "boot")

        switch mode {
        case "tabbar":
            presentTabBarScene()
        case "height":
            SpikeHeightDriver.shared.present()
        case "scroll":
            SpikeScrollDriver.shared.present()
        case "content":
            SpikeContentDriver.shared.present()
        default:
            // 其他模式尚未实现，保留入口避免误启动到常规面板
            SpikeTrace.log("未实现的模式: \(mode)", mode: "boot")
        }
        return true
    }

    private func presentTabBarScene() {
        // `--select tools` 可指定初始选中分区，便于截取中间位置的重排效果
        let arguments = CommandLine.arguments
        let initialSelection: String
        if let index = arguments.firstIndex(of: "--select"), index + 1 < arguments.count {
            initialSelection = arguments[index + 1]
        } else {
            initialSelection = "thermal"
        }

        let hosting = NSHostingController(rootView: SpikeTabBarScene(initialSelection: initialSelection))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spike 1 · 分区栏双候选"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        // SwiftUI 首帧未完成测量，contentViewController 会把窗口压成 0 宽；此处强制回写尺寸
        window.setContentSize(NSSize(width: 780, height: 500))
        if let screen = NSScreen.main {
            let size = NSSize(width: 780, height: 500)
            let origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            SpikeTrace.log("placed on main screen frame=\(window.frame)", mode: "tabbar")
        }
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        SpikeTrace.log(
            "window visible=\(window.isVisible) onActiveSpace=\(window.isOnActiveSpace) alpha=\(window.alphaValue) occlusion=\(window.occlusionState.rawValue) frame=\(window.frame)",
            mode: "tabbar"
        )

        // 终端无屏幕录制权限时 screencapture 取不到其他 App 窗口，改为窗口自截图
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, let window = self.window else { return }
            SpikeTrace.capture(window, to: "/tmp/calmbar_spike_window.png", mode: "tabbar")
        }
    }
}
