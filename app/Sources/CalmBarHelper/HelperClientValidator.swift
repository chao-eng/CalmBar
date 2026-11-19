import CalmBarKit
import Darwin
import Foundation
import Security

/// 校验 XPC 连接方是否为安装时授权的 CalmBar 主程序。
///
/// Helper 以 root 身份运行，仅校验 bundle id 会被 ad-hoc 签名伪造，
/// 因此安装时把主程序的 designated requirement 写入 root-only 配置文件，
/// 运行时交给 XPC 的 code signing requirement 校验连接另一端。
struct HelperClientValidator {
    static let requirementPath = CalmBarConfig.helperClientRequirementPath
    static let clientPathFile = CalmBarConfig.helperClientPathFile

    private let requirementString: String?
    private let pinnedExecutablePath: String?
    private let pathBindingRequired: Bool

    init(requirementPath: String = HelperClientValidator.requirementPath,
         clientPathFile: String = HelperClientValidator.clientPathFile) {
        let text = Self.readTrimmed(path: requirementPath)
        // 先解析一次，避免把非法 requirement 传进 XPC API。
        let parsed = text.flatMap(Self.makeRequirement)
        self.requirementString = parsed == nil ? nil : text
        self.pinnedExecutablePath = Self.readTrimmed(path: clientPathFile)
        self.pathBindingRequired = text?.contains("cdhash") == true
        if parsed == nil {
            NSLog("CalmBarHelper: 缺少客户端签名要求，XPC 将拒绝所有连接：\(requirementPath)")
        }
        if pathBindingRequired, pinnedExecutablePath == nil {
            NSLog("CalmBarHelper: ad-hoc 客户端缺少路径绑定，XPC 将拒绝所有连接：\(clientPathFile)")
        }
    }

    /// 让 XPC 在消息层按 designated requirement 校验客户端；这比在业务层
    /// 用 PID 取 SecCode 更可靠，也不存在 PID 复用窗口。
    func configure(_ connection: NSXPCConnection) -> Bool {
        guard let requirementString else { return false }
        connection.setCodeSigningRequirement(requirementString)

        // ad-hoc requirement 是 cdhash；额外绑定安装时的可执行路径，
        // 避免同一份二进制被复制到其他位置后调用 Helper。
        guard pathBindingRequired else { return true }

        let pid = connection.processIdentifier
        guard let pinnedExecutablePath,
              let clientPath = Self.executablePath(pid: pid) else {
            NSLog("CalmBarHelper: 缺少客户端路径绑定 pid=\(pid)")
            return false
        }
        let pinned = URL(fileURLWithPath: pinnedExecutablePath).resolvingSymlinksInPath().path
        let actual = URL(fileURLWithPath: clientPath).resolvingSymlinksInPath().path
        guard pinned == actual else {
            NSLog("CalmBarHelper: 客户端路径不匹配 pid=\(pid) path=\(actual)")
            return false
        }
        return true
    }

    private static func makeRequirement(_ text: String) -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    private static func readTrimmed(path: String) -> String? {
        guard let value = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
