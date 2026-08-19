import Foundation

public enum RecoveryReason: String, CaseIterable, Sendable {
    case appQuit = "appQuit"
    case systemSleep = "systemSleep"
    case featureDisabled = "featureDisabled"
    case helperDisconnected = "helperDisconnected"
    case manual = "manual"

    public var displayName: String {
        switch self {
        case .appQuit: return "应用正常退出"
        case .systemSleep: return "系统进入睡眠"
        case .featureDisabled: return "功能手动停用"
        case .helperDisconnected: return "特权服务断开连接"
        case .manual: return "用户手动恢复"
        }
    }
}
