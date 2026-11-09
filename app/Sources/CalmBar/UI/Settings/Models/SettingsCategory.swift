import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case thermal
    case menuBar
    case scroll
    case noTunes
    case caffeine
    case battery
    case monitor
    case gatekeeper
    case ocr
    case translation
    case clipboard
    case cleaner
    case audio
    case recorder
    case aiGateway
    case lanShare
    case permissions
    case launchManager
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
        case .monitor: return "系统监控"
        case .gatekeeper: return "应用授权"
        case .ocr: return "文字识别"
        case .translation: return "智能翻译"
        case .clipboard: return "剪贴板"
        case .cleaner: return "清理工具"
        case .audio: return "音频控制"
        case .recorder: return "屏幕录制"
        case .aiGateway: return "AI 网关"
        case .lanShare: return "局域网互传"
        case .permissions: return "权限安全"
        case .launchManager: return "自启管理"
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
        case .monitor: return "gauge.with.needle"
        case .gatekeeper: return "lock.shield.fill"
        case .ocr: return "text.viewfinder"
        case .translation: return "character.bubble.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .cleaner: return "trash.fill"
        case .audio: return "slider.vertical.3"
        case .recorder: return "record.circle"
        case .aiGateway: return "arrow.triangle.branch"
        case .lanShare: return "wifi"
        case .permissions: return "shield.lefthalf.filled"
        case .launchManager: return "gearshape.arrow.triangle.2.circlepath"
        case .general: return "gearshape.fill"
        }
    }

    public var category: SettingsCategory {
        switch self {
        case .thermal, .battery, .monitor:
            return .hardware
        case .menuBar, .scroll, .caffeine, .noTunes, .audio:
            return .desktop
        case .clipboard, .translation, .ocr, .cleaner, .recorder, .aiGateway, .lanShare:
            return .productivity
        case .permissions, .gatekeeper, .launchManager, .general:
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
        case .monitor:
            return "实时查看 CPU、内存、磁盘与网络，并按阈值发送告警提醒"
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
        case .audio:
            return "按应用调节音量、静音与输出设备，支持音量增强"
        case .recorder:
            return "录制屏幕画面、系统声音与麦克风，支持暂停与临时文件恢复"
        case .aiGateway:
            return "本地 OpenAI 兼容 API 网关：渠道路由、故障切换与 Token / 速率统计"
        case .lanShare:
            return "在同一 Wi-Fi 下用浏览器与手机、平板互传文件与文本，无需登录账号"
        case .permissions:
            return "集中管理辅助功能与 SMC LaunchDaemon 特权后台服务"
        case .launchManager:
            return "统一纳管用户自启项、全局守护服务与本地监听端口"
        case .general:
            return "开机自启、菜单栏温度展示与全局快捷键配置"
        }
    }

    /// 图标渐变色：与菜单栏面板各功能图标颜色保持一致（由 PopoverPalette 统一派生）
    public var gradientColors: [Color] {
        switch self {
        case .thermal:
            return PopoverPalette.badgeGradient(PopoverPalette.thermalAccent)      // 面板温控分区橙
        case .battery:
            return PopoverPalette.badgeGradient(PopoverPalette.accentBlue)         // 面板守护分区电池图标蓝
        case .monitor:
            return PopoverPalette.badgeGradient(PopoverPalette.monitorAccent)      // 面板监控分区绿
        case .menuBar:
            return PopoverPalette.badgeGradient(PopoverPalette.guardianAccent)     // 守护蓝
        case .scroll:
            return PopoverPalette.badgeGradient(PopoverPalette.accentIndigo)       // 靛蓝
        case .caffeine:
            return PopoverPalette.badgeGradient(PopoverPalette.accentBrown)        // 面板咖啡杯棕
        case .noTunes:
            return PopoverPalette.badgeGradient(PopoverPalette.accentPink)         // 面板 Music 图标粉
        case .clipboard:
            return PopoverPalette.badgeGradient(PopoverPalette.accentTeal)         // 面板工具磁贴青
        case .translation:
            return PopoverPalette.badgeGradient(PopoverPalette.accentPurple)       // 面板工具磁贴紫
        case .ocr:
            return PopoverPalette.badgeGradient(PopoverPalette.accentBlue)         // 面板工具磁贴蓝
        case .cleaner:
            return PopoverPalette.badgeGradient(PopoverPalette.accentOrange)       // 面板工具磁贴橙
        case .audio:
            return PopoverPalette.badgeGradient(PopoverPalette.audioAccent)        // 面板声音分区粉
        case .recorder:
            return PopoverPalette.badgeGradient(PopoverPalette.accentRed)          // 录制红
        case .aiGateway:
            return PopoverPalette.badgeGradient(PopoverPalette.gatewayAccent)      // 面板网关分区青
        case .lanShare:
            return PopoverPalette.badgeGradient(PopoverPalette.accentTeal)
        case .permissions:
            return PopoverPalette.badgeGradient(PopoverPalette.accentBlue)
        case .gatekeeper:
            return PopoverPalette.badgeGradient(PopoverPalette.accentRed)          // 面板工具磁贴红
        case .launchManager:
            return PopoverPalette.badgeGradient(PopoverPalette.accentIndigo)       // 面板工具磁贴靛
        case .general:
            return PopoverPalette.badgeGradient(PopoverPalette.accentPurple)
        }
    }

    public var searchKeywords: [String] {
        switch self {
        case .thermal:
            return ["温控", "温度", "风扇", "SMC", "转速", "散热", "传感器", "cpu", "thermal", "fan"]
        case .battery:
            return ["电池", "充电", "80%", "健康", "循环", "充电上限", "放电", "battery", "charge"]
        case .monitor:
            return ["系统监控", "CPU", "内存", "磁盘", "网络", "告警", "阈值", "monitor", "alert", "gauge"]
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
        case .audio:
            return ["音频", "音量", "静音", "混音", "输出设备", "路由", "增强", "audio", "volume", "mute", "mixer"]
        case .recorder:
            return ["录制", "录屏", "屏幕录制", "截屏", "麦克风", "系统声音", "record", "recorder", "screen", "luping"]
        case .aiGateway:
            return ["网关", "AI", "代理", "渠道", "路由", "Token", "TPS", "gateway", "API", "OpenAI"]
        case .lanShare:
            return ["互传", "局域网", "文件传输", "文本", "Wi-Fi", "分享", "airdrop", "lanshare", "share"]
        case .permissions:
            return ["权限", "辅助功能", "特权服务", "LaunchDaemon", "permission", "accessibility"]
        case .gatekeeper:
            return ["公证", "授权", "打不开", "损坏", "隔离", "gatekeeper", "quarantine", "xattr"]
        case .launchManager:
            return ["启动项", "服务", "自启动", "常驻", "守护", "launchctl", "daemon", "agent", "ports", "duankou"]
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
            return [.thermal, .battery, .monitor]
        case .desktop:
            return [.menuBar, .scroll, .caffeine, .noTunes, .audio]
        case .productivity:
            return [.clipboard, .translation, .ocr, .cleaner, .recorder, .aiGateway, .lanShare]
        case .system:
            return [.permissions, .gatekeeper, .launchManager, .general]
        }
    }
}
