import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case thermal
    case menuBar
    case scroll
    case noTunes
    case caffeine
    case battery
    case gatekeeper
    case ocr
    case translation
    case clipboard
    case cleaner
    case permissions
    case general

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .thermal: return "硬件温控"
        case .menuBar: return "菜单收纳"
        case .scroll: return "滚动手势"
        case .noTunes: return "音乐拦截"
        case .caffeine: return "防休眠"
        case .battery: return "充电管理"
        case .gatekeeper: return "应用授权"
        case .ocr: return "文字识别"
        case .translation: return "智能翻译"
        case .clipboard: return "剪贴板"
        case .cleaner: return "清理工具"
        case .permissions: return "权限安全"
        case .general: return "通用设置"
        }
    }

    public var icon: String {
        switch self {
        case .thermal: return "flame.fill"
        case .menuBar: return "menubar.rectangle"
        case .scroll: return "computermouse.fill"
        case .noTunes: return "music.note"
        case .caffeine: return "cup.and.saucer.fill"
        case .battery: return "battery.100.bolt"
        case .gatekeeper: return "lock.shield.fill"
        case .ocr: return "text.viewfinder"
        case .translation: return "character.bubble.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .cleaner: return "trash.fill"
        case .permissions: return "shield.lefthalf.filled"
        case .general: return "gearshape.fill"
        }
    }

    public var category: SettingsCategory {
        switch self {
        case .thermal, .battery:
            return .hardware
        case .menuBar, .scroll, .caffeine, .noTunes:
            return .desktop
        case .clipboard, .translation, .ocr, .cleaner:
            return .productivity
        case .permissions, .gatekeeper, .general:
            return .system
        }
    }

    public var subtitleZH: String {
        switch self {
        case .thermal:
            return "持续监控 CPU / GPU 与电池传感器温度，有风扇机型支持智能调速"
        case .menuBar:
            return "折叠隐藏不常用的菜单栏图标，保持桌面整洁清爽"
        case .scroll:
            return "解耦鼠标与触控板自然滚动方向，支持独立反转滚轮"
        case .noTunes:
            return "拦截蓝牙耳机连接或按键误触时 Apple Music 自动弹起"
        case .caffeine:
            return "临时阻止系统与屏幕进入睡眠休眠，保持工作常亮"
        case .battery:
            return "设定 80% 充电上限与回差巡航，延长锂电池使用寿命"
        case .gatekeeper:
            return "一键清除应用已损坏与未受信任警告，绕过 macOS 公证拦截"
        case .ocr:
            return "高精度离线屏幕文字与二维码截图识别，支持自动复制与浮窗"
        case .translation:
            return "基于 HY-MT2 / OpenAI 兼容大模型的即时划词与剪贴板翻译"
        case .clipboard:
            return "记录剪贴板历史文本与图片，支持搜索、固定与快速粘贴"
        case .cleaner:
            return "深度扫描并清理应用残留、开发构建缓存与垃圾文件"
        case .permissions:
            return "集中管理辅助功能与 SMC LaunchDaemon 特权后台服务"
        case .general:
            return "开机自启、菜单栏温度展示与全局快捷键配置"
        }
    }

    public var gradientColors: [Color] {
        switch self {
        case .thermal:
            return [Color.red, Color.orange]
        case .battery:
            return [Color(red: 0.18, green: 0.8, blue: 0.44), Color(red: 0.12, green: 0.65, blue: 0.35)]
        case .menuBar:
            return [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.45, blue: 0.9)]
        case .scroll:
            return [Color(red: 0.35, green: 0.4, blue: 0.95), Color(red: 0.25, green: 0.3, blue: 0.8)]
        case .caffeine:
            return [Color(red: 0.85, green: 0.55, blue: 0.25), Color(red: 0.7, green: 0.4, blue: 0.15)]
        case .noTunes:
            return [Color(red: 0.95, green: 0.25, blue: 0.5), Color(red: 0.8, green: 0.15, blue: 0.4)]
        case .clipboard:
            return [Color(red: 0.6, green: 0.35, blue: 0.9), Color(red: 0.45, green: 0.2, blue: 0.8)]
        case .translation:
            return [Color(red: 0.15, green: 0.7, blue: 0.75), Color(red: 0.1, green: 0.55, blue: 0.65)]
        case .ocr:
            return [Color(red: 0.95, green: 0.5, blue: 0.1), Color(red: 0.85, green: 0.38, blue: 0.05)]
        case .cleaner:
            return [Color(red: 0.9, green: 0.3, blue: 0.3), Color(red: 0.75, green: 0.2, blue: 0.2)]
        case .permissions:
            return [Color(red: 0.45, green: 0.5, blue: 0.58), Color(red: 0.35, green: 0.4, blue: 0.48)]
        case .gatekeeper:
            return [Color(red: 0.5, green: 0.55, blue: 0.6), Color(red: 0.38, green: 0.42, blue: 0.48)]
        case .general:
            return [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.42, green: 0.42, blue: 0.46)]
        }
    }

    public var searchKeywords: [String] {
        switch self {
        case .thermal:
            return ["温控", "温度", "风扇", "SMC", "转速", "散热", "传感器", "cpu", "thermal", "fan"]
        case .battery:
            return ["电池", "充电", "80%", "健康", "循环", "充电上限", "放电", "battery", "charge"]
        case .menuBar:
            return ["菜单栏", "收纳", "折叠", "隐藏", "图标", "bartender", "menubar", "hide"]
        case .scroll:
            return ["鼠标", "滚轮", "反转", "触控板", "自然滚动", "手势", "scroll", "mouse"]
        case .noTunes:
            return ["音乐", "Apple Music", "Spotify", "拦截", "耳机", "notunes", "music"]
        case .caffeine:
            return ["防休眠", "睡眠", "保持清醒", "屏幕常亮", "caffeine", "awake", "sleep"]
        case .clipboard:
            return ["剪贴板", "历史", "复制", "粘贴", "clipboard", "history", "paste"]
        case .translation:
            return ["翻译", "AI", "划词", "大模型", "HY-MT2", "OpenAI", "API", "translate"]
        case .ocr:
            return ["文字识别", "OCR", "截图", "识别", "提取文字", "二维码", "vision"]
        case .cleaner:
            return ["清理", "卸载", "垃圾", "缓存", "磁盘", "cleaner", "trash"]
        case .permissions:
            return ["权限", "辅助功能", "特权服务", "LaunchDaemon", "permission", "accessibility"]
        case .gatekeeper:
            return ["公证", "授权", "打不开", "损坏", "隔离", "gatekeeper", "quarantine", "xattr"]
        case .general:
            return ["通用", "开机自启", "快捷键", "关于", "外观", "general", "shortcut"]
        }
    }

    public func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if titleZH.lowercased().contains(q) { return true }
        if subtitleZH.lowercased().contains(q) { return true }
        if rawValue.lowercased().contains(q) { return true }
        return searchKeywords.contains(where: { $0.lowercased().contains(q) })
    }
}

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case hardware = "硬件与系统"
    case desktop = "桌面与交互"
    case productivity = "生产力工具"
    case system = "安全与偏好"

    public var id: String { rawValue }

    public var tabs: [SettingsTab] {
        switch self {
        case .hardware:
            return [.thermal, .battery]
        case .desktop:
            return [.menuBar, .scroll, .caffeine, .noTunes]
        case .productivity:
            return [.clipboard, .translation, .ocr, .cleaner]
        case .system:
            return [.permissions, .gatekeeper, .general]
        }
    }
}
