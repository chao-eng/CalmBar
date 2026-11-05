import Foundation
import Combine
import SwiftUI
import CalmBarKit

/// 界面外观偏好：跟随系统 / 浅色 / 深色
public enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// 调试模式（--m8/--visual 等）已锁定外观时跳过，避免覆盖验收设定
    static var isDebugAppearanceLocked: Bool {
        let args = CommandLine.arguments
        return args.contains("--m8") || args.contains("--m7") || args.contains("--visual")
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Thermal Settings
    @Published public var thermalEnabled: Bool {
        didSet { defaults.set(thermalEnabled, forKey: "thermalEnabled") }
    }
    @Published public var fanPreset: FanPreset {
        didSet { defaults.set(fanPreset.rawValue, forKey: "fanPreset") }
    }
    @Published public var customFanFraction: Double {
        didSet { defaults.set(customFanFraction, forKey: "customFanFraction") }
    }
    @Published public var smartStartTemp: Double {
        didSet { defaults.set(smartStartTemp, forKey: "smartStartTemp") }
    }
    @Published public var smartFullTemp: Double {
        didSet { defaults.set(smartFullTemp, forKey: "smartFullTemp") }
    }
    @Published public var dualFanLinked: Bool {
        didSet { defaults.set(dualFanLinked, forKey: "dualFanLinked") }
    }
    @Published public var fan0CustomFraction: Double {
        didSet { defaults.set(fan0CustomFraction, forKey: "fan0CustomFraction") }
    }
    @Published public var fan1CustomFraction: Double {
        didSet { defaults.set(fan1CustomFraction, forKey: "fan1CustomFraction") }
    }
    @Published public var showTempInMenuBar: Bool {
        didSet { defaults.set(showTempInMenuBar, forKey: "showTempInMenuBar") }
    }

    // MARK: - Menu Bar Settings
    @Published public var menuBarOrganizerEnabled: Bool {
        didSet { defaults.set(menuBarOrganizerEnabled, forKey: "menuBarOrganizerEnabled") }
    }
    @Published public var autoCollapseEnabled: Bool {
        didSet { defaults.set(autoCollapseEnabled, forKey: "autoCollapseEnabled") }
    }
    @Published public var autoCollapseDelay: Double {
        didSet { defaults.set(autoCollapseDelay, forKey: "autoCollapseDelay") }
    }
    @Published public var alwaysHiddenSectionEnabled: Bool {
        didSet { defaults.set(alwaysHiddenSectionEnabled, forKey: "alwaysHiddenSectionEnabled") }
    }
    @Published public var hideSeparators: Bool {
        didSet { defaults.set(hideSeparators, forKey: "hideSeparators") }
    }
    @Published public var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: "hoverToExpand") }
    }

    // MARK: - Scroll Reverser Settings
    @Published public var scrollReverserEnabled: Bool {
        didSet { defaults.set(scrollReverserEnabled, forKey: "scrollReverserEnabled") }
    }
    @Published public var reverseMouseVertical: Bool {
        didSet { defaults.set(reverseMouseVertical, forKey: "reverseMouseVertical") }
    }
    @Published public var reverseMouseHorizontal: Bool {
        didSet { defaults.set(reverseMouseHorizontal, forKey: "reverseMouseHorizontal") }
    }
    @Published public var reverseTrackpadVertical: Bool {
        didSet { defaults.set(reverseTrackpadVertical, forKey: "reverseTrackpadVertical") }
    }
    @Published public var reverseTrackpadHorizontal: Bool {
        didSet { defaults.set(reverseTrackpadHorizontal, forKey: "reverseTrackpadHorizontal") }
    }

    // MARK: - NoTunes (Apple Music Blocker) Settings
    @Published public var noTunesEnabled: Bool {
        didSet { defaults.set(noTunesEnabled, forKey: "noTunesEnabled") }
    }
    @Published public var noTunesReplacementType: NoTunesReplacementType {
        didSet { defaults.set(noTunesReplacementType.rawValue, forKey: "noTunesReplacementType") }
    }
    @Published public var noTunesReplacementTarget: String {
        didSet { defaults.set(noTunesReplacementTarget, forKey: "noTunesReplacementTarget") }
    }
    @Published public var noTunesTerminateOnEnable: Bool {
        didSet { defaults.set(noTunesTerminateOnEnable, forKey: "noTunesTerminateOnEnable") }
    }

    // MARK: - Caffeine (Keep Awake) Settings
    @Published public var caffeineEnabled: Bool {
        didSet { defaults.set(caffeineEnabled, forKey: "caffeineEnabled") }
    }
    @Published public var caffeineDefaultDuration: Int {
        didSet { defaults.set(caffeineDefaultDuration, forKey: "caffeineDefaultDuration") }
    }
    @Published public var caffeineActivateAtLaunch: Bool {
        didSet { defaults.set(caffeineActivateAtLaunch, forKey: "caffeineActivateAtLaunch") }
    }
    @Published public var caffeineDeactivateOnManualSleep: Bool {
        didSet { defaults.set(caffeineDeactivateOnManualSleep, forKey: "caffeineDeactivateOnManualSleep") }
    }
    @Published public var caffeineKeepAppsActive: Bool {
        didSet { defaults.set(caffeineKeepAppsActive, forKey: "caffeineKeepAppsActive") }
    }
    @Published public var caffeineIdleThreshold: Double {
        didSet { defaults.set(caffeineIdleThreshold, forKey: "caffeineIdleThreshold") }
    }

    // MARK: - Battery (Charging Limit) Settings
    @Published public var batteryChargeLimitEnabled: Bool {
        didSet { defaults.set(batteryChargeLimitEnabled, forKey: "batteryChargeLimitEnabled") }
    }
    @Published public var batteryChargeLimit: Int {
        didSet { defaults.set(batteryChargeLimit, forKey: "batteryChargeLimit") }
    }
    @Published public var batterySailingModeEnabled: Bool {
        didSet { defaults.set(batterySailingModeEnabled, forKey: "batterySailingModeEnabled") }
    }
    @Published public var batterySailingDelta: Int {
        didSet { defaults.set(batterySailingDelta, forKey: "batterySailingDelta") }
    }
    @Published public var batteryTopUpActive: Bool {
        didSet { defaults.set(batteryTopUpActive, forKey: "batteryTopUpActive") }
    }
    @Published public var batteryAutoDischargeEnabled: Bool {
        didSet { defaults.set(batteryAutoDischargeEnabled, forKey: "batteryAutoDischargeEnabled") }
    }

    // MARK: - OCR (Vision Text Recognition) Settings
    @Published public var ocrEnabled: Bool {
        didSet { defaults.set(ocrEnabled, forKey: "ocrEnabled") }
    }
    @Published public var ocrQualityAccurate: Bool {
        didSet { defaults.set(ocrQualityAccurate, forKey: "ocrQualityAccurate") }
    }
    @Published public var ocrLanguageCode: String {
        didSet { defaults.set(ocrLanguageCode, forKey: "ocrLanguageCode") }
    }
    @Published public var ocrAutoCopyToClipboard: Bool {
        didSet { defaults.set(ocrAutoCopyToClipboard, forKey: "ocrAutoCopyToClipboard") }
    }
    @Published public var ocrPlaySound: Bool {
        didSet { defaults.set(ocrPlaySound, forKey: "ocrPlaySound") }
    }
    @Published public var ocrShowFloatingPreview: Bool {
        didSet { defaults.set(ocrShowFloatingPreview, forKey: "ocrShowFloatingPreview") }
    }
    @Published public var ocrAutoDismiss: Bool {
        didSet { defaults.set(ocrAutoDismiss, forKey: "ocrAutoDismiss") }
    }
    @Published public var ocrAutoDismissDelay: Double {
        didSet { defaults.set(ocrAutoDismissDelay, forKey: "ocrAutoDismissDelay") }
    }
    @Published public var ocrKeepLineBreaks: Bool {
        didSet { defaults.set(ocrKeepLineBreaks, forKey: "ocrKeepLineBreaks") }
    }
    @Published public var ocrMaxHistoryCount: Int {
        didSet { defaults.set(ocrMaxHistoryCount, forKey: "ocrMaxHistoryCount") }
    }

    // MARK: - Clipboard History Settings
    @Published public var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: "clipboardHistoryEnabled") }
    }
    @Published public var clipboardMaxCount: Int {
        didSet { defaults.set(clipboardMaxCount, forKey: "clipboardMaxCount") }
    }
    @Published public var clipboardSaveImages: Bool {
        didSet { defaults.set(clipboardSaveImages, forKey: "clipboardSaveImages") }
    }
    @Published public var clipboardFilterSensitive: Bool {
        didSet { defaults.set(clipboardFilterSensitive, forKey: "clipboardFilterSensitive") }
    }
    @Published public var clipboardHideOnBlur: Bool {
        didSet { defaults.set(clipboardHideOnBlur, forKey: "clipboardHideOnBlur") }
    }
    @Published public var clipboardIgnoredApps: [String] {
        didSet { defaults.set(clipboardIgnoredApps, forKey: "clipboardIgnoredApps") }
    }
    @Published public var clipboardQuickCopyEnabled: Bool {
        didSet { defaults.set(clipboardQuickCopyEnabled, forKey: "clipboardQuickCopyEnabled") }
    }

    // MARK: - General Settings
    @Published public var appAppearance: AppAppearance {
        didSet {
            defaults.set(appAppearance.rawValue, forKey: "appAppearance")
            applyAppearance()
        }
    }
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginHelper.setEnabled(launchAtLogin)
        }
    }
    @Published public var globalHotKeysEnabled: Bool {
        didSet {
            defaults.set(globalHotKeysEnabled, forKey: "globalHotKeysEnabled")
            HotKeyManager.shared.updateRegistrationState()
        }
    }

    // MARK: - Popover Left-Click Menu Item Visibility
    @Published public var popoverShowGauges: Bool {
        didSet { defaults.set(popoverShowGauges, forKey: "popoverShowGauges") }
    }
    @Published public var popoverShowMenuBar: Bool {
        didSet { defaults.set(popoverShowMenuBar, forKey: "popoverShowMenuBar") }
    }
    @Published public var popoverShowScrollReverser: Bool {
        didSet { defaults.set(popoverShowScrollReverser, forKey: "popoverShowScrollReverser") }
    }
    @Published public var popoverShowNoTunes: Bool {
        didSet { defaults.set(popoverShowNoTunes, forKey: "popoverShowNoTunes") }
    }
    @Published public var popoverShowCaffeine: Bool {
        didSet { defaults.set(popoverShowCaffeine, forKey: "popoverShowCaffeine") }
    }
    @Published public var popoverShowBattery: Bool {
        didSet { defaults.set(popoverShowBattery, forKey: "popoverShowBattery") }
    }
    @Published public var popoverShowGatekeeper: Bool {
        didSet { defaults.set(popoverShowGatekeeper, forKey: "popoverShowGatekeeper") }
    }
    @Published public var popoverShowOCR: Bool {
        didSet { defaults.set(popoverShowOCR, forKey: "popoverShowOCR") }
    }
    @Published public var popoverShowClipboard: Bool {
        didSet { defaults.set(popoverShowClipboard, forKey: "popoverShowClipboard") }
    }
    @Published public var popoverShowCleaner: Bool {
        didSet { defaults.set(popoverShowCleaner, forKey: "popoverShowCleaner") }
    }
    @Published public var cleanerEnabled: Bool {
        didSet { defaults.set(cleanerEnabled, forKey: "cleanerEnabled") }
    }
    @Published public var cleanerSensitivity: SearchSensitivityLevel {
        didSet { defaults.set(cleanerSensitivity.rawValue, forKey: "cleanerSensitivity") }
    }

    // MARK: - AI Translation Settings
    @Published public var translationEnabled: Bool {
        didSet { defaults.set(translationEnabled, forKey: "translationEnabled") }
    }
    @Published public var translationAPIBaseURL: String {
        didSet { defaults.set(translationAPIBaseURL, forKey: "translationAPIBaseURL") }
    }
    @Published public var translationAPIKey: String {
        didSet { defaults.set(translationAPIKey, forKey: "translationAPIKey") }
    }
    @Published public var translationModel: String {
        didSet { defaults.set(translationModel, forKey: "translationModel") }
    }
    @Published public var translationTargetLanguageCode: String {
        didSet { defaults.set(translationTargetLanguageCode, forKey: "translationTargetLanguageCode") }
    }
    @Published public var translationCustomPrompt: String {
        didSet { defaults.set(translationCustomPrompt, forKey: "translationCustomPrompt") }
    }
    @Published public var translationDoubleCopyEnabled: Bool {
        didSet { defaults.set(translationDoubleCopyEnabled, forKey: "translationDoubleCopyEnabled") }
    }
    @Published public var translationDoubleCopyInterval: Double {
        didSet { defaults.set(translationDoubleCopyInterval, forKey: "translationDoubleCopyInterval") }
    }
    @Published public var translationAutoDismiss: Bool {
        didSet { defaults.set(translationAutoDismiss, forKey: "translationAutoDismiss") }
    }
    @Published public var translationAutoDismissDelay: Double {
        didSet { defaults.set(translationAutoDismissDelay, forKey: "translationAutoDismissDelay") }
    }
    @Published public var popoverShowTranslation: Bool {
        didSet { defaults.set(popoverShowTranslation, forKey: "popoverShowTranslation") }
    }

    // MARK: - Launch Manager Settings
    @Published public var launchManagerDeveloperModeEnabled: Bool {
        didSet { defaults.set(launchManagerDeveloperModeEnabled, forKey: "launchManagerDeveloperModeEnabled") }
    }
    @Published public var launchManagerAutoBackupEnabled: Bool {
        didSet { defaults.set(launchManagerAutoBackupEnabled, forKey: "launchManagerAutoBackupEnabled") }
    }
    @Published public var launchManagerShowSystemDaemons: Bool {
        didSet { defaults.set(launchManagerShowSystemDaemons, forKey: "launchManagerShowSystemDaemons") }
    }
    @Published public var launchManagerShowAppleProtected: Bool {
        didSet { defaults.set(launchManagerShowAppleProtected, forKey: "launchManagerShowAppleProtected") }
    }
    @Published public var launchManagerScanDevPorts: Bool {
        didSet { defaults.set(launchManagerScanDevPorts, forKey: "launchManagerScanDevPorts") }
    }
    @Published public var launchManagerCrashLoopAlertThreshold: Int {
        didSet { defaults.set(launchManagerCrashLoopAlertThreshold, forKey: "launchManagerCrashLoopAlertThreshold") }
    }
    @Published public var popoverShowLaunchManager: Bool {
        didSet { defaults.set(popoverShowLaunchManager, forKey: "popoverShowLaunchManager") }
    }
    // MARK: - Popover Reserved Tabs（Phase 2 模块上线后置 true）
    @Published public var popoverShowMonitor: Bool {
        didSet { defaults.set(popoverShowMonitor, forKey: "popoverShowMonitor") }
    }
    @Published public var popoverShowAudioOutput: Bool {
        didSet { defaults.set(popoverShowAudioOutput, forKey: "popoverShowAudioOutput") }
    }
    @Published public var popoverShowRecorder: Bool {
        didSet { defaults.set(popoverShowRecorder, forKey: "popoverShowRecorder") }
    }

    // MARK: - Audio Hub Settings（PRD UC-A01 ~ UC-A04）
    @Published public var audioHubEnabled: Bool {
        didSet { defaults.set(audioHubEnabled, forKey: "audioHubEnabled") }
    }
    @Published public var audioBoostEnabled: Bool {
        didSet { defaults.set(audioBoostEnabled, forKey: "audioBoostEnabled") }
    }
    @Published public var audioBoostMaxPercent: Int {
        didSet { defaults.set(audioBoostMaxPercent, forKey: "audioBoostMaxPercent") }
    }
    @Published public var audioRoutingEnabled: Bool {
        didSet { defaults.set(audioRoutingEnabled, forKey: "audioRoutingEnabled") }
    }
    @Published public var audioRoutingFallback: AudioRoutingFallback {
        didSet { defaults.set(audioRoutingFallback.rawValue, forKey: "audioRoutingFallback") }
    }
    @Published public var audioRoutingMaxApps: Int {
        didSet { defaults.set(audioRoutingMaxApps, forKey: "audioRoutingMaxApps") }
    }
    @Published public var audioExcludedBundleIDs: [String] {
        didSet { defaults.set(audioExcludedBundleIDs, forKey: "audioExcludedBundleIDs") }
    }

    // MARK: - Screen Recorder Settings（PRD UC-R01 ~ UC-R04）
    @Published public var screenRecorderEnabled: Bool {
        didSet { defaults.set(screenRecorderEnabled, forKey: "screenRecorderEnabled") }
    }
    @Published public var recorderSaveDirectory: String {
        didSet { defaults.set(recorderSaveDirectory, forKey: "recorderSaveDirectory") }
    }
    @Published public var recorderQuality: RecorderQuality {
        didSet { defaults.set(recorderQuality.rawValue, forKey: "recorderQuality") }
    }
    @Published public var recorderFPS: Int {
        didSet { defaults.set(recorderFPS, forKey: "recorderFPS") }
    }
    @Published public var recorderCodec: RecorderCodec {
        didSet { defaults.set(recorderCodec.rawValue, forKey: "recorderCodec") }
    }
    @Published public var recorderCountdown: Int {
        didSet { defaults.set(recorderCountdown, forKey: "recorderCountdown") }
    }
    @Published public var recorderIncludeCursor: Bool {
        didSet { defaults.set(recorderIncludeCursor, forKey: "recorderIncludeCursor") }
    }
    @Published public var recorderCaptureSystemAudio: Bool {
        didSet { defaults.set(recorderCaptureSystemAudio, forKey: "recorderCaptureSystemAudio") }
    }
    @Published public var recorderCaptureMicrophone: Bool {
        didSet { defaults.set(recorderCaptureMicrophone, forKey: "recorderCaptureMicrophone") }
    }
    // MARK: - Popover Selected Tab（面板上次停留的分区）
    @Published public var popoverSelectedTab: String {
        didSet { defaults.set(popoverSelectedTab, forKey: "popoverSelectedTab") }
    }

    // MARK: - System Monitor Settings（PRD UC-M01 ~ UC-M04）
    @Published public var systemMonitorEnabled: Bool {
        didSet { defaults.set(systemMonitorEnabled, forKey: "systemMonitorEnabled") }
    }
    @Published public var systemMonitorSampleInterval: Int {
        didSet { defaults.set(systemMonitorSampleInterval, forKey: "systemMonitorSampleInterval") }
    }
    @Published public var systemMonitorHistoryWindow: Int {
        didSet { defaults.set(systemMonitorHistoryWindow, forKey: "systemMonitorHistoryWindow") }
    }
    @Published public var systemMonitorShowGPU: Bool {
        didSet { defaults.set(systemMonitorShowGPU, forKey: "systemMonitorShowGPU") }
    }
    @Published public var menuBarReadoutItems: [String] {
        didSet { defaults.set(menuBarReadoutItems, forKey: "menuBarReadoutItems") }
    }
    @Published public var monitorAlertsEnabled: Bool {
        didSet { defaults.set(monitorAlertsEnabled, forKey: "monitorAlertsEnabled") }
    }
    @Published public var monitorAlertCPU: Bool {
        didSet { defaults.set(monitorAlertCPU, forKey: "monitorAlertCPU") }
    }
    @Published public var monitorAlertMemory: Bool {
        didSet { defaults.set(monitorAlertMemory, forKey: "monitorAlertMemory") }
    }
    @Published public var monitorAlertDisk: Bool {
        didSet { defaults.set(monitorAlertDisk, forKey: "monitorAlertDisk") }
    }
    @Published public var monitorAlertBattery: Bool {
        didSet { defaults.set(monitorAlertBattery, forKey: "monitorAlertBattery") }
    }
    @Published public var monitorAlertTemperature: Bool {
        didSet { defaults.set(monitorAlertTemperature, forKey: "monitorAlertTemperature") }
    }
    @Published public var monitorAlertCPUThreshold: Double {
        didSet { defaults.set(monitorAlertCPUThreshold, forKey: "monitorAlertCPUThreshold") }
    }
    @Published public var monitorAlertCPUDuration: Int {
        didSet { defaults.set(monitorAlertCPUDuration, forKey: "monitorAlertCPUDuration") }
    }
    @Published public var monitorAlertMemoryDuration: Int {
        didSet { defaults.set(monitorAlertMemoryDuration, forKey: "monitorAlertMemoryDuration") }
    }
    @Published public var monitorAlertDiskFreeGB: Double {
        didSet { defaults.set(monitorAlertDiskFreeGB, forKey: "monitorAlertDiskFreeGB") }
    }
    @Published public var monitorAlertBatteryThreshold: Int {
        didSet { defaults.set(monitorAlertBatteryThreshold, forKey: "monitorAlertBatteryThreshold") }
    }
    @Published public var monitorAlertTemperatureThreshold: Double {
        didSet { defaults.set(monitorAlertTemperatureThreshold, forKey: "monitorAlertTemperatureThreshold") }
    }
    @Published public var monitorAlertCooldownMinutes: Int {
        didSet { defaults.set(monitorAlertCooldownMinutes, forKey: "monitorAlertCooldownMinutes") }
    }

    // MARK: - AI Gateway Settings（MiniGateway PRD）
    @Published public var aiGatewayEnabled: Bool {
        didSet { defaults.set(aiGatewayEnabled, forKey: "aiGatewayEnabled") }
    }
    @Published public var aiGatewayPort: Int {
        didSet { defaults.set(aiGatewayPort, forKey: "aiGatewayPort") }
    }
    @Published public var aiGatewayChannels: [AIGatewayChannel] {
        didSet {
            if let data = try? JSONEncoder().encode(aiGatewayChannels) {
                defaults.set(data, forKey: "aiGatewayChannels")
            }
        }
    }
    @Published public var aiGatewayModels: [AIGatewayModelRoute] {
        didSet {
            if let data = try? JSONEncoder().encode(aiGatewayModels) {
                defaults.set(data, forKey: "aiGatewayModels")
            }
        }
    }
    @Published public var aiGatewayGranularity: GatewayGranularity {
        didSet { defaults.set(aiGatewayGranularity.rawValue, forKey: "aiGatewayGranularity") }
    }

    /// BR-24：菜单栏读数最多 3 项
    public static let menuBarReadoutLimit = 3
    public static let menuBarReadoutOrder = ["temperature", "cpu", "memory", "network", "disk"]

    public func setMenuBarReadoutItem(_ id: String, enabled: Bool) {
        var items = menuBarReadoutItems
        if enabled {
            guard !items.contains(id), items.count < Self.menuBarReadoutLimit else { return }
            items.append(id)
        } else {
            items.removeAll { $0 == id }
        }
        items.sort { lhs, rhs in
            let left = Self.menuBarReadoutOrder.firstIndex(of: lhs) ?? Int.max
            let right = Self.menuBarReadoutOrder.firstIndex(of: rhs) ?? Int.max
            return left < right
        }
        menuBarReadoutItems = items
    }

    /// 将外观偏好应用到整个 App（设置页切换与启动时调用）
    public func applyAppearance() {
        guard !AppAppearance.isDebugAppearanceLocked else { return }
        switch appAppearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private init() {
        self.thermalEnabled = defaults.object(forKey: "thermalEnabled") as? Bool ?? true
        let presetStr = defaults.string(forKey: "fanPreset") ?? FanPreset.smart.rawValue
        self.fanPreset = FanPreset(rawValue: presetStr) ?? .smart
        self.customFanFraction = defaults.object(forKey: "customFanFraction") as? Double ?? 0.50
        self.smartStartTemp = defaults.object(forKey: "smartStartTemp") as? Double ?? 65.0
        self.smartFullTemp = defaults.object(forKey: "smartFullTemp") as? Double ?? 85.0
        self.dualFanLinked = defaults.object(forKey: "dualFanLinked") as? Bool ?? true
        self.fan0CustomFraction = defaults.object(forKey: "fan0CustomFraction") as? Double ?? 0.50
        self.fan1CustomFraction = defaults.object(forKey: "fan1CustomFraction") as? Double ?? 0.50
        self.showTempInMenuBar = defaults.object(forKey: "showTempInMenuBar") as? Bool ?? true

        self.menuBarOrganizerEnabled = defaults.object(forKey: "menuBarOrganizerEnabled") as? Bool ?? true
        self.autoCollapseEnabled = defaults.object(forKey: "autoCollapseEnabled") as? Bool ?? false
        self.autoCollapseDelay = defaults.object(forKey: "autoCollapseDelay") as? Double ?? 5.0
        self.alwaysHiddenSectionEnabled = defaults.object(forKey: "alwaysHiddenSectionEnabled") as? Bool ?? true
        self.hideSeparators = defaults.object(forKey: "hideSeparators") as? Bool ?? false
        self.hoverToExpand = defaults.object(forKey: "hoverToExpand") as? Bool ?? false

        self.scrollReverserEnabled = defaults.object(forKey: "scrollReverserEnabled") as? Bool ?? true
        self.reverseMouseVertical = defaults.object(forKey: "reverseMouseVertical") as? Bool ?? true
        self.reverseMouseHorizontal = defaults.object(forKey: "reverseMouseHorizontal") as? Bool ?? false
        self.reverseTrackpadVertical = defaults.object(forKey: "reverseTrackpadVertical") as? Bool ?? false
        self.reverseTrackpadHorizontal = defaults.object(forKey: "reverseTrackpadHorizontal") as? Bool ?? false

        self.noTunesEnabled = defaults.object(forKey: "noTunesEnabled") as? Bool ?? true
        let replacementTypeStr = defaults.string(forKey: "noTunesReplacementType") ?? NoTunesReplacementType.none.rawValue
        self.noTunesReplacementType = NoTunesReplacementType(rawValue: replacementTypeStr) ?? .none
        self.noTunesReplacementTarget = defaults.string(forKey: "noTunesReplacementTarget") ?? ""
        self.noTunesTerminateOnEnable = defaults.object(forKey: "noTunesTerminateOnEnable") as? Bool ?? true

        self.caffeineEnabled = defaults.object(forKey: "caffeineEnabled") as? Bool ?? false
        self.caffeineDefaultDuration = defaults.object(forKey: "caffeineDefaultDuration") as? Int ?? 0
        self.caffeineActivateAtLaunch = defaults.object(forKey: "caffeineActivateAtLaunch") as? Bool ?? false
        self.caffeineDeactivateOnManualSleep = defaults.object(forKey: "caffeineDeactivateOnManualSleep") as? Bool ?? true
        self.caffeineKeepAppsActive = defaults.object(forKey: "caffeineKeepAppsActive") as? Bool ?? false
        self.caffeineIdleThreshold = defaults.object(forKey: "caffeineIdleThreshold") as? Double ?? 90.0

        self.batteryChargeLimitEnabled = defaults.object(forKey: "batteryChargeLimitEnabled") as? Bool ?? false
        self.batteryChargeLimit = defaults.object(forKey: "batteryChargeLimit") as? Int ?? 80
        self.batterySailingModeEnabled = defaults.object(forKey: "batterySailingModeEnabled") as? Bool ?? true
        self.batterySailingDelta = defaults.object(forKey: "batterySailingDelta") as? Int ?? 5
        self.batteryTopUpActive = defaults.object(forKey: "batteryTopUpActive") as? Bool ?? false
        self.batteryAutoDischargeEnabled = defaults.object(forKey: "batteryAutoDischargeEnabled") as? Bool ?? false

        self.ocrEnabled = defaults.object(forKey: "ocrEnabled") as? Bool ?? true
        self.ocrQualityAccurate = defaults.object(forKey: "ocrQualityAccurate") as? Bool ?? true
        self.ocrLanguageCode = defaults.string(forKey: "ocrLanguageCode") ?? "auto"
        self.ocrAutoCopyToClipboard = defaults.object(forKey: "ocrAutoCopyToClipboard") as? Bool ?? true
        self.ocrPlaySound = defaults.object(forKey: "ocrPlaySound") as? Bool ?? true
        self.ocrShowFloatingPreview = defaults.object(forKey: "ocrShowFloatingPreview") as? Bool ?? true
        self.ocrAutoDismiss = defaults.object(forKey: "ocrAutoDismiss") as? Bool ?? true
        self.ocrAutoDismissDelay = defaults.object(forKey: "ocrAutoDismissDelay") as? Double ?? 10.0
        self.ocrKeepLineBreaks = defaults.object(forKey: "ocrKeepLineBreaks") as? Bool ?? true
        self.ocrMaxHistoryCount = defaults.object(forKey: "ocrMaxHistoryCount") as? Int ?? 100

        self.clipboardHistoryEnabled = defaults.object(forKey: "clipboardHistoryEnabled") as? Bool ?? true
        self.clipboardMaxCount = defaults.object(forKey: "clipboardMaxCount") as? Int ?? 200
        self.clipboardSaveImages = defaults.object(forKey: "clipboardSaveImages") as? Bool ?? true
        self.clipboardFilterSensitive = defaults.object(forKey: "clipboardFilterSensitive") as? Bool ?? true
        self.clipboardHideOnBlur = defaults.object(forKey: "clipboardHideOnBlur") as? Bool ?? false
        self.clipboardIgnoredApps = defaults.stringArray(forKey: "clipboardIgnoredApps") ?? []
        self.clipboardQuickCopyEnabled = defaults.object(forKey: "clipboardQuickCopyEnabled") as? Bool ?? true

        self.appAppearance = AppAppearance(rawValue: defaults.string(forKey: "appAppearance") ?? "") ?? .system
        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        self.globalHotKeysEnabled = defaults.object(forKey: "globalHotKeysEnabled") as? Bool ?? true

        self.popoverShowGauges = defaults.object(forKey: "popoverShowGauges") as? Bool ?? true
        self.popoverShowMenuBar = defaults.object(forKey: "popoverShowMenuBar") as? Bool ?? true
        self.popoverShowScrollReverser = defaults.object(forKey: "popoverShowScrollReverser") as? Bool ?? true
        self.popoverShowNoTunes = defaults.object(forKey: "popoverShowNoTunes") as? Bool ?? true
        self.popoverShowCaffeine = defaults.object(forKey: "popoverShowCaffeine") as? Bool ?? true
        self.popoverShowBattery = defaults.object(forKey: "popoverShowBattery") as? Bool ?? true
        self.popoverShowGatekeeper = defaults.object(forKey: "popoverShowGatekeeper") as? Bool ?? true
        self.popoverShowOCR = defaults.object(forKey: "popoverShowOCR") as? Bool ?? true
        self.popoverShowClipboard = defaults.object(forKey: "popoverShowClipboard") as? Bool ?? true
        self.popoverShowCleaner = defaults.object(forKey: "popoverShowCleaner") as? Bool ?? true
        self.cleanerEnabled = defaults.object(forKey: "cleanerEnabled") as? Bool ?? true
        self.popoverShowTranslation = defaults.object(forKey: "popoverShowTranslation") as? Bool ?? true
        let sensStr = defaults.string(forKey: "cleanerSensitivity") ?? SearchSensitivityLevel.balanced.rawValue
        self.cleanerSensitivity = SearchSensitivityLevel(rawValue: sensStr) ?? .balanced

        self.translationEnabled = defaults.object(forKey: "translationEnabled") as? Bool ?? true
        self.translationAPIBaseURL = defaults.string(forKey: "translationAPIBaseURL") ?? ""
        self.translationAPIKey = defaults.string(forKey: "translationAPIKey") ?? ""
        self.translationModel = defaults.string(forKey: "translationModel") ?? "Hy-MT2"
        self.translationTargetLanguageCode = defaults.string(forKey: "translationTargetLanguageCode") ?? "zh"
        self.translationCustomPrompt = defaults.string(forKey: "translationCustomPrompt") ?? ""
        self.translationDoubleCopyEnabled = defaults.object(forKey: "translationDoubleCopyEnabled") as? Bool ?? true
        self.translationDoubleCopyInterval = defaults.object(forKey: "translationDoubleCopyInterval") as? Double ?? 0.8
        self.translationAutoDismiss = defaults.object(forKey: "translationAutoDismiss") as? Bool ?? true
        self.translationAutoDismissDelay = defaults.object(forKey: "translationAutoDismissDelay") as? Double ?? 8.0

        self.launchManagerDeveloperModeEnabled = defaults.object(forKey: "launchManagerDeveloperModeEnabled") as? Bool ?? false
        self.launchManagerAutoBackupEnabled = defaults.object(forKey: "launchManagerAutoBackupEnabled") as? Bool ?? true
        self.launchManagerShowSystemDaemons = defaults.object(forKey: "launchManagerShowSystemDaemons") as? Bool ?? true
        self.launchManagerShowAppleProtected = defaults.object(forKey: "launchManagerShowAppleProtected") as? Bool ?? false
        self.launchManagerScanDevPorts = defaults.object(forKey: "launchManagerScanDevPorts") as? Bool ?? true
        self.launchManagerCrashLoopAlertThreshold = defaults.object(forKey: "launchManagerCrashLoopAlertThreshold") as? Int ?? 3
        self.popoverShowLaunchManager = defaults.object(forKey: "popoverShowLaunchManager") as? Bool ?? true
        // 监控模块已上线，面板分区默认展示；音频需显式启用后才展示
        self.popoverShowMonitor = defaults.object(forKey: "popoverShowMonitor") as? Bool ?? true
        self.popoverShowAudioOutput = defaults.object(forKey: "popoverShowAudioOutput") as? Bool ?? true
        self.popoverShowRecorder = defaults.object(forKey: "popoverShowRecorder") as? Bool ?? true

        self.audioHubEnabled = defaults.object(forKey: "audioHubEnabled") as? Bool ?? false
        self.audioBoostEnabled = defaults.object(forKey: "audioBoostEnabled") as? Bool ?? true
        self.audioBoostMaxPercent = defaults.object(forKey: "audioBoostMaxPercent") as? Int ?? 150
        self.audioRoutingEnabled = defaults.object(forKey: "audioRoutingEnabled") as? Bool ?? true
        self.audioRoutingFallback = AudioRoutingFallback(
            rawValue: defaults.string(forKey: "audioRoutingFallback") ?? ""
        ) ?? .followDefault
        self.audioRoutingMaxApps = defaults.object(forKey: "audioRoutingMaxApps") as? Int ?? 6
        self.audioExcludedBundleIDs = defaults.stringArray(forKey: "audioExcludedBundleIDs") ?? []

        self.screenRecorderEnabled = defaults.object(forKey: "screenRecorderEnabled") as? Bool ?? true
        self.recorderSaveDirectory = defaults.string(forKey: "recorderSaveDirectory")
            ?? ("~/Movies/CalmBar Recordings" as NSString).expandingTildeInPath
        self.recorderQuality = RecorderQuality(
            rawValue: defaults.string(forKey: "recorderQuality") ?? ""
        ) ?? .p1080
        self.recorderFPS = defaults.object(forKey: "recorderFPS") as? Int ?? 30
        self.recorderCodec = RecorderCodec(
            rawValue: defaults.string(forKey: "recorderCodec") ?? ""
        ) ?? .h264
        self.recorderCountdown = defaults.object(forKey: "recorderCountdown") as? Int ?? 3
        self.recorderIncludeCursor = defaults.object(forKey: "recorderIncludeCursor") as? Bool ?? true
        self.recorderCaptureSystemAudio = defaults.object(forKey: "recorderCaptureSystemAudio") as? Bool ?? true
        self.recorderCaptureMicrophone = defaults.object(forKey: "recorderCaptureMicrophone") as? Bool ?? false
        self.popoverSelectedTab = defaults.string(forKey: "popoverSelectedTab") ?? "thermal"

        // 系统监控（PRD §7.3）
        self.systemMonitorEnabled = defaults.object(forKey: "systemMonitorEnabled") as? Bool ?? true
        self.systemMonitorSampleInterval = defaults.object(forKey: "systemMonitorSampleInterval") as? Int ?? 1
        self.systemMonitorHistoryWindow = defaults.object(forKey: "systemMonitorHistoryWindow") as? Int ?? 60
        self.systemMonitorShowGPU = defaults.object(forKey: "systemMonitorShowGPU") as? Bool ?? true

        // BR-25：旧 showTempInMenuBar 一次性迁移为「温度」读数项
        let legacyShowTemp = defaults.object(forKey: "showTempInMenuBar") as? Bool ?? true
        self.menuBarReadoutItems = defaults.stringArray(forKey: "menuBarReadoutItems")
            ?? (legacyShowTemp ? ["temperature"] : [])

        self.monitorAlertsEnabled = defaults.object(forKey: "monitorAlertsEnabled") as? Bool ?? true
        self.monitorAlertCPU = defaults.object(forKey: "monitorAlertCPU") as? Bool ?? true
        self.monitorAlertMemory = defaults.object(forKey: "monitorAlertMemory") as? Bool ?? true
        self.monitorAlertDisk = defaults.object(forKey: "monitorAlertDisk") as? Bool ?? true
        self.monitorAlertBattery = defaults.object(forKey: "monitorAlertBattery") as? Bool ?? true
        self.monitorAlertTemperature = defaults.object(forKey: "monitorAlertTemperature") as? Bool ?? true
        self.monitorAlertCPUThreshold = defaults.object(forKey: "monitorAlertCPUThreshold") as? Double ?? 90
        self.monitorAlertCPUDuration = defaults.object(forKey: "monitorAlertCPUDuration") as? Int ?? 60
        self.monitorAlertMemoryDuration = defaults.object(forKey: "monitorAlertMemoryDuration") as? Int ?? 30
        self.monitorAlertDiskFreeGB = defaults.object(forKey: "monitorAlertDiskFreeGB") as? Double ?? 10
        self.monitorAlertBatteryThreshold = defaults.object(forKey: "monitorAlertBatteryThreshold") as? Int ?? 20
        self.monitorAlertTemperatureThreshold = defaults.object(forKey: "monitorAlertTemperatureThreshold") as? Double ?? 95
        self.monitorAlertCooldownMinutes = defaults.object(forKey: "monitorAlertCooldownMinutes") as? Int ?? 30

        // AI Gateway（MiniGateway PRD）
        self.aiGatewayEnabled = defaults.object(forKey: "aiGatewayEnabled") as? Bool ?? false
        self.aiGatewayPort = defaults.object(forKey: "aiGatewayPort") as? Int ?? 8317
        self.aiGatewayChannels = defaults.data(forKey: "aiGatewayChannels")
            .flatMap { try? JSONDecoder().decode([AIGatewayChannel].self, from: $0) } ?? []
        self.aiGatewayModels = defaults.data(forKey: "aiGatewayModels")
            .flatMap { try? JSONDecoder().decode([AIGatewayModelRoute].self, from: $0) } ?? []
        self.aiGatewayGranularity = GatewayGranularity(
            rawValue: defaults.string(forKey: "aiGatewayGranularity") ?? ""
        ) ?? .minute
    }
}

/// 路由设备断开时的回退策略（PRD BR-13）
public enum AudioRoutingFallback: String, CaseIterable, Identifiable, Sendable {
    case followDefault = "followDefault"
    case pauseApp = "pauseApp"
    case alertOnly = "alertOnly"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .followDefault: return "回退系统默认"
        case .pauseApp: return "暂停该应用"
        case .alertOnly: return "仅提醒"
        }
    }
}

/// 录制画质档位（以 16:9 基准的短边像素数描述）
public enum RecorderQuality: String, CaseIterable, Identifiable, Sendable {
    case p1080 = "p1080"
    case p1440 = "p1440"
    case p4k = "p4k"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .p1080: return "1080p"
        case .p1440: return "1440p"
        case .p4k: return "4K"
        }
    }

    public var shortEdge: CGFloat {
        switch self {
        case .p1080: return 1080
        case .p1440: return 1440
        case .p4k: return 2160
        }
    }
}

public enum RecorderCodec: String, CaseIterable, Identifiable, Sendable {
    case h264 = "h264"
    case hevc = "hevc"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        }
    }

    public var avCodec: String {
        switch self {
        case .h264: return "avc1"
        case .hevc: return "hvc1"
        }
    }
}

public enum NoTunesReplacementType: String, CaseIterable, Identifiable {
    case none = "none"
    case app = "app"
    case url = "url"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .none: return "仅拦截 (不打开任何替代)"
        case .app: return "替代打开指定应用 (App)"
        case .url: return "替代打开网页链接 (Web URL)"
        }
    }
}
