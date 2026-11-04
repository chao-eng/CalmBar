import SwiftUI
import CalmBarKit

// MARK: - 面板可见项三分组（PRD §7.2 / BR-23）

/// 面板可见项分组：偏好设置按此三组重新排列，键语义不变
enum PopoverVisibilityGroup: String, CaseIterable, Identifiable, Sendable {
    case thermal
    case guardian
    case tools

    var id: String { rawValue }

    /// 面板分区名（≤ 5 个汉字）
    var title: String {
        switch self {
        case .thermal: "温控"
        case .guardian: "守护"
        case .tools: "工具"
        }
    }

    /// 偏好设置分组名（PRD §8.2）
    var settingsTitle: String {
        switch self {
        case .thermal: "温控与风扇"
        case .guardian: "常驻守护"
        case .tools: "工具入口"
        }
    }

    var icon: String {
        switch self {
        case .thermal: "thermometer.medium"
        case .guardian: "shield.lefthalf.filled"
        case .tools: "square.grid.2x2"
        }
    }

    var settingsHint: String {
        switch self {
        case .thermal: "决定面板「温控」分区是否显示温度仪表与风扇卡片。"
        case .guardian: "决定面板「守护」分区显示哪些常驻守护开关。"
        case .tools: "决定面板「工具」分区显示哪些快捷入口。"
        }
    }

    // MARK: 空状态文案（PRD §5.9）

    var emptyTitle: String {
        switch self {
        case .thermal: "温控未显示"
        case .guardian: "守护项已全部隐藏"
        case .tools: "工具分区暂无已启用的入口"
        }
    }

    var emptyDetail: String {
        switch self {
        case .thermal: "可在偏好设置勾选温度仪表与风扇卡片"
        case .guardian: "勾选需要的守护开关后，这里会出现卡片"
        case .tools: "勾选需要的工具后，这里会出现快捷入口"
        }
    }

    var emptyIcon: String {
        switch self {
        case .thermal: "thermometer.slash"
        case .guardian: "shield.slash"
        case .tools: "square.grid.2x2"
        }
    }

    var items: [PopoverVisibilityItem] {
        PopoverVisibilityItem.allCases.filter { $0.group == self }
    }
}

// MARK: - 可见项（单一真源：popoverShow* 键）

enum PopoverVisibilityItem: String, CaseIterable, Identifiable, Sendable {
    case gauges
    case caffeine
    case battery
    case audioOutput
    case scrollReverser
    case noTunes
    case menuBar
    case ocr
    case translation
    case clipboard
    case cleaner
    case gatekeeper
    case launchManager
    case recorder

    var id: String { rawValue }

    var group: PopoverVisibilityGroup {
        switch self {
        case .gauges: .thermal
        case .caffeine, .battery, .audioOutput, .scrollReverser, .noTunes, .menuBar: .guardian
        case .ocr, .translation, .clipboard, .cleaner, .gatekeeper, .launchManager, .recorder: .tools
        }
    }

    /// 偏好设置行文案
    var settingsTitle: String {
        switch self {
        case .gauges: "硬件温度与风扇调控"
        case .caffeine: "系统防休眠 (保持清醒)"
        case .battery: "电池充电上限控制"
        case .audioOutput: "系统输出设备与静音"
        case .scrollReverser: "鼠标自然滚动解耦"
        case .noTunes: "Apple Music 启动拦截"
        case .menuBar: "菜单栏图标收纳"
        case .ocr: "屏幕文字与二维码识别"
        case .translation: "AI 划词翻译快捷入口"
        case .clipboard: "剪贴板历史快捷入口"
        case .cleaner: "卸载与清理快捷入口"
        case .gatekeeper: "软件去隔离与签名授权"
        case .launchManager: "自启与常驻服务管理"
        case .recorder: "屏幕录制快捷入口"
        }
    }

    /// 偏好设置行图标（沿用原 GeneralSettingsTab 图标）
    var icon: String {
        switch self {
        case .gauges: "gauge.with.needle"
        case .caffeine: "cup.and.saucer.fill"
        case .battery: "battery.100.bolt"
        case .audioOutput: "speaker.wave.2.fill"
        case .scrollReverser: "computermouse.fill"
        case .noTunes: "music.note"
        case .menuBar: "menubar.rectangle"
        case .ocr: "text.viewfinder"
        case .translation: "character.bubble.fill"
        case .clipboard: "doc.on.clipboard"
        case .cleaner: "trash"
        case .gatekeeper: "lock.shield.fill"
        case .launchManager: "gearshape.arrow.triangle.2.circlepath"
        case .recorder: "record.circle"
        }
    }

    @MainActor
    func isEnabled(_ settings: AppSettings) -> Bool {
        switch self {
        case .gauges: settings.popoverShowGauges
        case .caffeine: settings.popoverShowCaffeine
        case .battery: settings.popoverShowBattery
        case .audioOutput: settings.popoverShowAudioOutput
        case .scrollReverser: settings.popoverShowScrollReverser
        case .noTunes: settings.popoverShowNoTunes
        case .menuBar: settings.popoverShowMenuBar
        case .ocr: settings.popoverShowOCR
        case .translation: settings.popoverShowTranslation
        case .clipboard: settings.popoverShowClipboard
        case .cleaner: settings.popoverShowCleaner
        case .gatekeeper: settings.popoverShowGatekeeper
        case .launchManager: settings.popoverShowLaunchManager
        case .recorder: settings.popoverShowRecorder
        }
    }

    @MainActor
    func setEnabled(_ settings: AppSettings, _ value: Bool) {
        switch self {
        case .gauges: settings.popoverShowGauges = value
        case .caffeine: settings.popoverShowCaffeine = value
        case .battery: settings.popoverShowBattery = value
        case .audioOutput: settings.popoverShowAudioOutput = value
        case .scrollReverser: settings.popoverShowScrollReverser = value
        case .noTunes: settings.popoverShowNoTunes = value
        case .menuBar: settings.popoverShowMenuBar = value
        case .ocr: settings.popoverShowOCR = value
        case .translation: settings.popoverShowTranslation = value
        case .clipboard: settings.popoverShowClipboard = value
        case .cleaner: settings.popoverShowCleaner = value
        case .gatekeeper: settings.popoverShowGatekeeper = value
        case .launchManager: settings.popoverShowLaunchManager = value
        case .recorder: settings.popoverShowRecorder = value
        }
    }
}
