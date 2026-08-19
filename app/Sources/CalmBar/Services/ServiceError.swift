import Foundation

public enum ServiceError: Error, LocalizedError, Sendable, Equatable {
    case helperUnavailable
    case permissionDenied(PermissionType)
    case unsupportedHardware(String)
    case operationFailed(String)
    case connectionLost
    case invalidParameter(String)

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "特权服务未安装或不可用"
        case .permissionDenied(let perm):
            return "缺少必要权限: \(perm.title)"
        case .unsupportedHardware(let detail):
            return "硬件不支持: \(detail)"
        case .operationFailed(let reason):
            return "操作执行失败: \(reason)"
        case .connectionLost:
            return "与底层通信连接已中断"
        case .invalidParameter(let param):
            return "参数无效: \(param)"
        }
    }
}
