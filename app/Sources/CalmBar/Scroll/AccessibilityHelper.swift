import AppKit
import ApplicationServices
import IOKit

@MainActor
public enum AccessibilityHelper {
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public static var isInputMonitoringGranted: Bool {
        if #available(macOS 10.15, *) {
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
        return true
    }

    public static var isProcessTrusted: Bool {
        isAccessibilityTrusted || isInputMonitoringGranted
    }

    public static func requestAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if #available(macOS 10.15, *) {
            DispatchQueue.global(qos: .userInitiated).async {
                IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            }
        }
    }

    public static func openSystemSettingsAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openSystemSettingsInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
