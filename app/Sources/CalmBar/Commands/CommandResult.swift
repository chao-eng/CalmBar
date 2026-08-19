import Foundation

public enum CommandResult: Equatable, Sendable {
    case success(String?)
    case cancelled
    case permissionDenied(PermissionType)
    case failure(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var message: String? {
        switch self {
        case .success(let msg):
            return msg
        case .cancelled:
            return "操作已取消"
        case .permissionDenied(let perm):
            return "缺少权限: \(perm.title)"
        case .failure(let err):
            return err
        }
    }
}
