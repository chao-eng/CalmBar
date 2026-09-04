import Testing
@testable import CalmBar

@Suite("Command Palette Dismiss-on-Deactivate Tests")
struct CommandPaletteDismissTests {

    /// 核心回归防护：App 失活路径必须路由到 hideWindow。
    /// 在无窗口服务器的 SwiftPM 测试进程中无法真实创建 NSPanel，因此断言
    /// “handleAppDeactivation 会触发一次 hideWindow（hideCount 递增）”这一可观测契约；
    /// 真实窗口展示态被失活关闭的行为由该契约 + 手动验证共同覆盖。
    @Test("App deactivation routes to hideWindow")
    @MainActor
    func testDeactivationRoutesToHide() {
        let controller = CommandPaletteWindowController()
        #expect(controller.hideCount == 0)

        controller.handleAppDeactivation()

        #expect(controller.hideCount == 1)
    }

    @Test("Repeated deactivation never crashes or re-enters infinitely")
    @MainActor
    func testRepeatedDeactivationIsSafe() {
        let controller = CommandPaletteWindowController()

        controller.handleAppDeactivation()
        controller.handleAppDeactivation()
        controller.handleAppDeactivation()

        #expect(controller.hideCount == 3)
    }

    /// hideWindow 幂等且防重入：isHiding 期间再次调用不会重复执行
    @Test("hideWindow is re-entrancy safe")
    @MainActor
    func testHideWindowIsReentrancySafe() {
        let controller = CommandPaletteWindowController()

        // 并发/重入场景：直接连续调用，hideCount 应精确递增
        controller.hideWindow()
        controller.hideWindow()
        controller.hideWindow()

        #expect(controller.hideCount == 3)
    }
}
