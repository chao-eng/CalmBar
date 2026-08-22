import Foundation

public enum FeatureID: String, CaseIterable, Identifiable, Sendable {
    case thermal
    case battery
    case caffeine
    case clipboard
    case ocr
    case cleaner
    case scroll
    case noTunes
    case gatekeeper
    case menuBar
    case translation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .thermal: return "硬件温控"
        case .battery: return "充电保护"
        case .caffeine: return "防休眠防离开"
        case .clipboard: return "剪贴板历史"
        case .ocr: return "屏幕识字"
        case .cleaner: return "应用与缓存清理"
        case .scroll: return "滚轮方向解耦"
        case .noTunes: return "音乐启动拦截"
        case .gatekeeper: return "应用去隔离与自签名"
        case .menuBar: return "菜单栏收纳"
        case .translation: return "AI 划词翻译"
        }
    }
}
