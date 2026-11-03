import SwiftUI
import AppKit
import CalmBarKit

@main
struct CalmBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // M8 回归：深色外观需在面板创建前生效
        let args = CommandLine.arguments
        if args.contains("--m8"), args.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        // M1 骨架模式：独立窗口，不启动现有面板
        if M1WindowController.shared.presentIfRequested() {
            return
        }

        // Spike 模式：只打开临时验证窗口，不启动常驻功能与菜单栏面板
        if SpikeWindowController.shared.presentIfRequested() {
            return
        }

        NSApp.setActivationPolicy(.accessory)

        // 1. Register and start all default platform features first
        let featureManager = FeatureManager.shared
        featureManager.registerDefaultFeatures()
        featureManager.startAll()

        // 2. Register all commands from Feature layer to CommandCenter
        CommandCenter.shared.registerFeatureCommands(from: featureManager)

        // 3. Setup Global Coordinators and UI Hosting
        _ = SystemEventCoordinator.shared
        _ = PermissionManager.shared
        _ = SystemMonitorService.shared
        _ = StatusBarManager.shared
        _ = HotKeyManager.shared

        // M8：生产面板接入回归（真实状态栏面板路径）
        M8SmokeDriver.shared.startIfRequested()
    }

    /// 通知权限可能在本 App 之外被修改（如跳转系统设置），回前台时复查
    public func applicationDidBecomeActive(_ notification: Notification) {
        Task { await MonitorAlertEngine.shared.refreshAuthorization() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func cleanup() {
        RecoveryCoordinator.shared.performRecovery(reason: .appQuit)
    }
}
