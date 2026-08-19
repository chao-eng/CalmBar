import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

public enum PermissionType: String, CaseIterable, Identifiable, Sendable {
    case accessibility = "accessibility"
    case privilegedHelper = "privilegedHelper"
    case screenRecording = "screenRecording"
    case fullDiskAccess = "fullDiskAccess"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility:
            return "辅助功能权限 (Accessibility)"
        case .privilegedHelper:
            return "特权辅助工具 (Privileged Helper)"
        case .screenRecording:
            return "屏幕录制权限 (Screen Capture)"
        case .fullDiskAccess:
            return "完全磁盘访问权限 (Full Disk Access)"
        }
    }

    public var iconName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .privilegedHelper: return "lock.shield"
        case .screenRecording: return "viewfinder"
        case .fullDiskAccess: return "internaldrive"
        }
    }

    public var purposeDescription: String {
        switch self {
        case .accessibility:
            return "用于鼠标滚轮解耦 (CGEventTap)、以及超时模拟原地 HID 闲置防离开。"
        case .privilegedHelper:
            return "用于低层硬件 SMC 风扇调速、80% 充电上限与适配器旁路供电、应用去隔离与自签名修复。"
        case .screenRecording:
            return "用于屏幕选区截屏并调用 Apple Vision 深度学习引擎进行离线文字与二维码识别。"
        case .fullDiskAccess:
            return "用于应用卸载时精准扫描深层缓存与残留、清理开发者环境多余缓存。"
        }
    }

    public var isRequiredForCore: Bool {
        switch self {
        case .accessibility, .privilegedHelper: return true
        case .screenRecording, .fullDiskAccess: return false
        }
    }
}

public struct PermissionStatus: Sendable {
    public let type: PermissionType
    public let isGranted: Bool
    public let statusMessage: String
}

@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var accessibilityGranted: Bool = false
    @Published public private(set) var helperInstalled: Bool = false
    @Published public private(set) var screenRecordingGranted: Bool = false
    @Published public private(set) var fullDiskAccessGranted: Bool = false

    private var refreshTimer: Timer?

    private init() {
        refreshAll()
        // Periodically refresh when settings window is open
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAll()
            }
        }
    }

    public func refreshAll() {
        self.accessibilityGranted = checkAccessibility()
        self.helperInstalled = checkHelper()
        self.screenRecordingGranted = checkScreenRecording()
        self.fullDiskAccessGranted = checkFullDiskAccess()
    }

    public func isGranted(_ type: PermissionType) -> Bool {
        switch type {
        case .accessibility: return accessibilityGranted
        case .privilegedHelper: return helperInstalled
        case .screenRecording: return screenRecordingGranted
        case .fullDiskAccess: return fullDiskAccessGranted
        }
    }

    // MARK: - Feature Permission Mapping

    public func requirements(for featureID: FeatureID) -> [FeaturePermissionRequirement] {
        if let feature = FeatureManager.shared.feature(id: featureID) {
            return feature.requiredPermissions
        }
        return defaultRequirements(for: featureID)
    }

    public func affectedFeatures(for permission: PermissionType) -> [FeatureID] {
        FeatureID.allCases.filter { id in
            let reqs = requirements(for: id)
            return reqs.contains(where: { $0.type == permission })
        }
    }

    public func isFeatureUsable(_ featureID: FeatureID) -> Bool {
        let reqs = requirements(for: featureID)
        for req in reqs where req.level == .required {
            if !isGranted(req.type) {
                return false
            }
        }
        return true
    }

    private func defaultRequirements(for featureID: FeatureID) -> [FeaturePermissionRequirement] {
        switch featureID {
        case .scroll:
            return [FeaturePermissionRequirement(type: .accessibility, level: .required, reason: "滚轮反转拦截")]
        case .caffeine:
            return [FeaturePermissionRequirement(type: .accessibility, level: .advanced, reason: "防离开微动仿真")]
        case .thermal:
            return [FeaturePermissionRequirement(type: .privilegedHelper, level: .required, reason: "SMC 风扇转速控制")]
        case .battery:
            return [FeaturePermissionRequirement(type: .privilegedHelper, level: .required, reason: "SMC 电池充电控制")]
        case .gatekeeper:
            return [FeaturePermissionRequirement(type: .privilegedHelper, level: .optional, reason: "系统应用免密修复")]
        case .ocr:
            return [FeaturePermissionRequirement(type: .screenRecording, level: .required, reason: "屏幕选区截屏")]
        case .cleaner:
            return [FeaturePermissionRequirement(type: .fullDiskAccess, level: .advanced, reason: "完整缓存与残留扫描")]
        case .clipboard, .noTunes, .menuBar:
            return []
        }
    }

    // MARK: - Permission Checks

    public func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    public func checkHelper() -> Bool {
        return HelperClient.isHelperInstalledOnDisk
    }

    public func checkScreenRecording() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    public func checkFullDiskAccess() -> Bool {
        // Test reading a protected user path, e.g. Safari preferences or ~/Library/Mail
        let testPath = ("~/Library/Safari" as NSString).expandingTildeInPath
        let fm = FileManager.default
        return fm.isReadableFile(atPath: testPath)
    }

    // MARK: - Request & Navigation

    public func requestOrOpenSettings(for type: PermissionType) {
        switch type {
        case .accessibility:
            let dict: [String: Bool] = ["AXTrustedCheckOptionPrompt": true]
            _ = AXIsProcessTrustedWithOptions(dict as CFDictionary)
            openSystemSettings(pane: "Privacy_Accessibility")

        case .privilegedHelper:
            HelperClient.shared.requestInstallHelper { [weak self] success, _ in
                self?.refreshAll()
            }

        case .screenRecording:
            if #available(macOS 10.15, *) {
                CGRequestScreenCaptureAccess()
            }
            openSystemSettings(pane: "Privacy_ScreenCapture")

        case .fullDiskAccess:
            openSystemSettings(pane: "Privacy_AllFiles")
        }
    }

    private func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        } else if let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallbackUrl)
        }
    }
}
