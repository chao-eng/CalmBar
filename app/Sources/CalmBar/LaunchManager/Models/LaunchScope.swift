import Foundation

public enum LaunchScope: String, CaseIterable, Identifiable, Sendable {
    case userAgent    // ~/Library/LaunchAgents (当前用户自启，免密)
    case systemAgent  // /Library/LaunchAgents (全局用户代理，写文件需特权，运行在用户 GUI Session)
    case systemDaemon // /Library/LaunchDaemons (系统启动即运行，写文件与运行均需特权)
    case appleSystem  // /System/Library/LaunchAgents & Daemons (SIP保护，完全只读)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .userAgent: return "用户自启项"
        case .systemAgent: return "全局自启项 (全用户)"
        case .systemDaemon: return "系统守护服务"
        case .appleSystem: return "macOS 核心项 (系统保护·只读)"
        }
    }

    public var directoryURL: URL? {
        switch self {
        case .userAgent:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        case .systemAgent:
            return URL(fileURLWithPath: "/Library/LaunchAgents")
        case .systemDaemon:
            return URL(fileURLWithPath: "/Library/LaunchDaemons")
        case .appleSystem:
            return URL(fileURLWithPath: "/System/Library/LaunchAgents")
        }
    }

    /// 修改或删除文件是否需要特权 (写入系统目录)
    public var requiresPrivilegeForFile: Bool {
        self == .systemAgent || self == .systemDaemon
    }

    /// 执行 launchctl 命令是否需要特权
    /// 注：/Library/LaunchAgents 运行在当前登录用户的 GUI Session，执行 launchctl 不需要 root
    public var requiresPrivilegeForService: Bool {
        self == .systemDaemon
    }

    public var isReadOnly: Bool {
        self == .appleSystem
    }

    public var launchdDomain: String {
        switch self {
        case .userAgent, .systemAgent:
            return "gui/\(getuid())"
        case .systemDaemon, .appleSystem:
            return "system"
        }
    }
}
