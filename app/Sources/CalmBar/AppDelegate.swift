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
        _ = StatusBarManager.shared
        _ = HotKeyManager.shared
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
