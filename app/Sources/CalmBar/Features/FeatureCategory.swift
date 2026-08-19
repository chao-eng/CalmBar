import Foundation

public enum FeatureCategory: String, CaseIterable, Identifiable, Sendable {
    case system
    case hardware
    case productivity
    case input
    case security
    case cleanup

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "系统控制"
        case .hardware: return "硬件安全"
        case .productivity: return "效率增强"
        case .input: return "输入与交互"
        case .security: return "安全与权限"
        case .cleanup: return "空间清理"
        }
    }
}
