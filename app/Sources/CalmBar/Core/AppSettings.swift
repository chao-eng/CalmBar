import Foundation
import Combine
import SwiftUI
import CalmBarKit

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

    // MARK: - General Settings
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginHelper.setEnabled(launchAtLogin)
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

        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false

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
