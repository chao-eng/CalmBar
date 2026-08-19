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

        // 1. Setup Status Bar & Popover UI first so macOS knows we are a resident menu bar app
        _ = SystemEventCoordinator.shared
        _ = PermissionManager.shared
        _ = StatusBarManager.shared
        _ = MenuBarOrganizer.shared

        // 2. Setup System Extension Handlers
        _ = HotKeyManager.shared
        _ = ScrollReverserManager.shared
        _ = NoTunesManager.shared
        _ = CaffeineManager.shared
        _ = BatteryChargeManager.shared
        _ = ClipboardMonitor.shared

        // 3. Start background thermal monitoring asynchronously after UI is anchored
        DispatchQueue.main.async {
            _ = ThermalMonitor.shared
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func cleanup() {
        ThermalMonitor.shared.restoreSystemControl()
        HotKeyManager.shared.unregister()
        ScrollReverserManager.shared.stop()
        NoTunesManager.shared.stopMonitoring()
        CaffeineManager.shared.cleanupOnExit()
        BatteryChargeManager.shared.restoreDefaultCharging()
        ClipboardMonitor.shared.stopMonitoring()
    }
}
