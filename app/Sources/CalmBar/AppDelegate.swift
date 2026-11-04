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
        // 视觉验收：先锁定浅色外观，深色由驱动运行中切换
        if args.contains("--visual") {
            NSApp.appearance = NSAppearance(named: .aqua)
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

        // 应用持久化的外观偏好（跟随系统/浅色/深色）
        AppSettings.shared.applyAppearance()

        // 启动 Sparkle 自动更新（版本源与公钥由 Info.plist 提供）
        // 调试驱动常以裸二进制运行，Sparkle 无法启动会弹出「无法检查更新」，自动化模式下跳过
        if Updater.canStartUpdater {
            _ = Updater.shared
        }

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

        // 色彩令牌视觉验收（临时，真实面板路径）
        VisualCheckDriver.shared.startIfRequested()
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
