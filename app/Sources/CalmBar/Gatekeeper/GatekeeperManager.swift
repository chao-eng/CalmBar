import Foundation
import AppKit

@MainActor
public final class GatekeeperManager: ObservableObject {
    public static let shared = GatekeeperManager()

    @Published public var isProcessing = false
    @Published public var lastResult: UnlockResult? = nil
    @Published public var history: [UnlockResult] = []

    public struct UnlockResult: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp = Date()
        public let success: Bool
        public let path: String
        public let appName: String
        public let message: String
        public let isDeepSigned: Bool

        public init(success: Bool, path: String, appName: String, message: String, isDeepSigned: Bool) {
            self.success = success
            self.path = path
            self.appName = appName
            self.message = message
            self.isDeepSigned = isDeepSigned
        }
    }

    private init() {}

    /// 一键解除指定路径的隔离限制，并可选进行自签名修复
    @discardableResult
    public func unlockPath(_ url: URL, deepSign: Bool = false) async -> UnlockResult {
        isProcessing = true
        defer { isProcessing = false }

        let path = url.path(percentEncoded: false)
        let appName = (path as NSString).lastPathComponent

        guard FileManager.default.fileExists(atPath: path) else {
            let res = UnlockResult(
                success: false,
                path: path,
                appName: appName,
                message: "目标文件或目录不存在",
                isDeepSigned: deepSign
            )
            self.lastResult = res
            self.history.insert(res, at: 0)
            return res
        }

        // 1. 先尝试以普通权限执行 xattr -rd com.apple.quarantine
        let (directSuccess, directErr) = await runProcess(
            executable: "/usr/bin/xattr",
            args: ["-rd", "com.apple.quarantine", path]
        )

        var finalSuccess = directSuccess
        var finalMessage = ""

        if directSuccess {
            finalMessage = "已成功解除 Gatekeeper 隔离限制"
        } else {
            // 2. 普通权限失败时，若 Helper 服务就绪，则尝试通过特权 Helper 执行
            if HelperClient.shared.isHelperAvailable {
                let helperSuccess: Bool = await withCheckedContinuation { continuation in
                    HelperClient.shared.removeQuarantine(at: path, deepSign: deepSign) { success, err in
                        continuation.resume(returning: success)
                    }
                }
                if helperSuccess {
                    finalSuccess = true
                    finalMessage = "已通过特权助手成功解除隔离"
                }
            }

            // 3. 若 Helper 仍未成功，降级通过 AppleScript 请求管理员密码提权
            if !finalSuccess {
                let adminScript = "do shell script \"/usr/bin/xattr -rd com.apple.quarantine \(path.shellEscaped)\" with administrator privileges"
                let (appleScriptSuccess, appleScriptErr) = runAppleScript(adminScript)
                if appleScriptSuccess {
                    finalSuccess = true
                    finalMessage = "已通过管理员授权解除隔离"
                } else {
                    finalSuccess = false
                    finalMessage = "解除隔离失败: \(appleScriptErr ?? directErr ?? "权限不足")"
                }
            }
        }

        // 4. 如果需要深度自签名且前面步骤成功
        if finalSuccess && deepSign {
            let (signSuccess, _) = await runProcess(
                executable: "/usr/bin/codesign",
                args: ["--force", "--deep", "--sign", "-", path]
            )

            if !signSuccess {
                // 尝试管理员提权自签名
                let signAdminScript = "do shell script \"/usr/bin/codesign --force --deep --sign - \(path.shellEscaped)\" with administrator privileges"
                let (adminSignSuccess, adminSignErr) = runAppleScript(signAdminScript)
                if adminSignSuccess {
                    finalMessage += "，并已完成 Ad-hoc 自签名重签"
                } else {
                    finalMessage += " (但自签名未成功: \(adminSignErr ?? "未知错误"))"
                }
            } else {
                finalMessage += "，并已完成 Ad-hoc 自签名重签"
            }
        }

        let result = UnlockResult(
            success: finalSuccess,
            path: path,
            appName: appName,
            message: finalMessage,
            isDeepSigned: deepSign
        )

        self.lastResult = result
        self.history.insert(result, at: 0)
        return result
    }

    /// 批量解除隔离
    public func unlockPaths(_ urls: [URL], deepSign: Bool = false) async -> [UnlockResult] {
        var results: [UnlockResult] = []
        for url in urls {
            let res = await unlockPath(url, deepSign: deepSign)
            results.append(res)
        }
        return results
    }

    public func clearHistory() {
        history.removeAll()
        lastResult = nil
    }

    // MARK: - Process Execution Helper
    private func runProcess(executable: String, args: [String]) async -> (Bool, String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args

                let pipe = Pipe()
                process.standardError = pipe
                process.standardOutput = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (process.terminationStatus == 0, output))
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }

    private func runAppleScript(_ script: String) -> (Bool, String?) {
        var errorDict: NSDictionary?
        if let scriptObj = NSAppleScript(source: script) {
            _ = scriptObj.executeAndReturnError(&errorDict)
            if let error = errorDict {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "AppleScript 执行被取消或失败"
                return (false, msg)
            }
            return (true, nil)
        }
        return (false, "初始化 AppleScript 失败")
    }
}

private extension String {
    var shellEscaped: String {
        return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
