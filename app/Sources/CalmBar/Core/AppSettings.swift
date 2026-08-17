import Foundation
import Combine
import SwiftUI
import CalmBarKit

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Thermal Settings
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

    // MARK: - General Settings
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginHelper.setEnabled(launchAtLogin)
        }
    }

    private init() {
        let presetStr = defaults.string(forKey: "fanPreset") ?? FanPreset.smart.rawValue
        self.fanPreset = FanPreset(rawValue: presetStr) ?? .smart
        self.customFanFraction = defaults.object(forKey: "customFanFraction") as? Double ?? 0.50
        self.smartStartTemp = defaults.object(forKey: "smartStartTemp") as? Double ?? 45.0
        self.smartFullTemp = defaults.object(forKey: "smartFullTemp") as? Double ?? 80.0
        self.dualFanLinked = defaults.object(forKey: "dualFanLinked") as? Bool ?? true
        self.fan0CustomFraction = defaults.object(forKey: "fan0CustomFraction") as? Double ?? 0.50
        self.fan1CustomFraction = defaults.object(forKey: "fan1CustomFraction") as? Double ?? 0.50
        self.showTempInMenuBar = defaults.object(forKey: "showTempInMenuBar") as? Bool ?? true

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

        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
