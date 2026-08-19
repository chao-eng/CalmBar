import Foundation

public enum CommandCategory: String, CaseIterable, Identifiable, Sendable {
    case general
    case system
    case hardware
    case productivity
    case input
    case cleanup

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: return "通用设置"
        case .system: return "系统控制"
        case .hardware: return "硬件温控与电源"
        case .productivity: return "效率工具"
        case .input: return "输入与交互"
        case .cleanup: return "空间清理"
        }
    }
}
