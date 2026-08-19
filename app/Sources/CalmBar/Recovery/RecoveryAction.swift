import Foundation

public enum RecoveryAction: String, CaseIterable, Sendable {
    case restoreFanAuto = "restoreFanAuto"
    case restoreBatteryCharging = "restoreBatteryCharging"
    case releasePowerAssertions = "releasePowerAssertions"
    case stopScrollEventTap = "stopScrollEventTap"
    case stopClipboardMonitoring = "stopClipboardMonitoring"
    case stopNoTunesMonitoring = "stopNoTunesMonitoring"
    case unregisterHotkeys = "unregisterHotkeys"

    public var displayName: String {
        switch self {
        case .restoreFanAuto: return "恢复风扇官方自动托管"
        case .restoreBatteryCharging: return "恢复默认电池充电策略"
        case .releasePowerAssertions: return "释放防休眠电源断言"
        case .stopScrollEventTap: return "停止鼠标滚轮事件拦截"
        case .stopClipboardMonitoring: return "停止剪贴板监听"
        case .stopNoTunesMonitoring: return "停止音乐启动拦截"
        case .unregisterHotkeys: return "注销全局快捷键"
        }
    }
}
