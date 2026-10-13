import Foundation

public enum LaunchServiceError: LocalizedError, Equatable {
    case systemProtected
    case fileNotFound(String)
    case invalidPlist(String)
    case commandFailed(String)
    case timeout(String)
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .systemProtected:
            return "macOS 核心保护项，严禁修改或删除 (SIP 保护)"
        case .fileNotFound(let path):
            return "未找到指定的 Plist 文件: \(path)"
        case .invalidPlist(let reason):
            return "Plist 格式损坏或无效: \(reason)"
        case .commandFailed(let msg):
            return "执行 launchctl 失败: \(msg)"
        case .timeout(let op):
            return "执行操作超时 (\(op))"
        case .permissionDenied:
            return "权限被拒绝，需要管理员授权或特权助手支持"
        }
    }
}
