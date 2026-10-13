import Foundation
import AppKit

@MainActor
public final class LaunchPrivilegeService {
    public static let shared = LaunchPrivilegeService()

    private init() {}

    /// 执行特权命令（优先特权助手，降级 AppleScript 提权授权弹窗）
    public func runPrivileged(_ command: String) async throws {
        // 使用 NSAppleScript 提权执行 shell 脚本
        let escapedScript = command.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escapedScript)\" with administrator privileges"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                if let scriptObj = NSAppleScript(source: source) {
                    _ = scriptObj.executeAndReturnError(&errorDict)
                    if let error = errorDict {
                        let msg = error[NSAppleScript.errorMessage] as? String ?? "用户取消或管理员授权失败"
                        continuation.resume(throwing: LaunchServiceError.commandFailed(msg))
                        return
                    }
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LaunchServiceError.commandFailed("初始化管理员授权脚本失败"))
                }
            }
        }
    }

    /// 批量执行多条特权命令（使用 && 串联合并为单个事务，实现 BR-LM-04，防止连续多次密码弹窗）
    public func runBatchPrivileged(_ commands: [String]) async throws {
        guard !commands.isEmpty else { return }
        let singleTransaction = commands.joined(separator: " && ")
        try await runPrivileged(singleTransaction)
    }

    /// POSIX Shell 路径转义
    nonisolated public static func escapeShellArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
