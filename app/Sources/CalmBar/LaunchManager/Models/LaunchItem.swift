import Foundation

public struct LaunchItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(scope.rawValue):\(label)" }
    public let label: String
    public let plistURL: URL
    public let scope: LaunchScope

    // 可视化与应用身份识别 (从所属 App Bundle 提取，优化小白体验)
    public var appName: String?
    public var appIconURL: URL?

    // 可执行信息
    public var program: String?
    public var programArguments: [String]
    public var workingDirectory: String?
    public var environmentVariables: [String: String]

    // 触发策略
    public var runAtLoad: Bool
    public var keepAlive: KeepAliveStrategy
    public var startInterval: Int?
    public var watchPaths: [String]

    // 日志与排障
    public var standardOutPath: String?
    public var standardErrorPath: String?

    // 运行时状态 (通过 launchctl 查询)
    public var isLoaded: Bool
    public var isDisabledByOverride: Bool
    public var pid: Int?
    public var lastExitCode: Int?

    // 统计与并发锁控制
    public var crashCountWithinWindow: Int
    public var isMutating: Bool // 变更锁，防止后台扫描覆盖乐观状态

    // 衍生计算状态
    public var isRunning: Bool { pid != nil && pid! > 0 }

    public init(
        label: String,
        plistURL: URL,
        scope: LaunchScope,
        appName: String? = nil,
        appIconURL: URL? = nil,
        program: String? = nil,
        programArguments: [String] = [],
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        runAtLoad: Bool = false,
        keepAlive: KeepAliveStrategy = .disabled,
        startInterval: Int? = nil,
        watchPaths: [String] = [],
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        isLoaded: Bool = false,
        isDisabledByOverride: Bool = false,
        pid: Int? = nil,
        lastExitCode: Int? = nil,
        crashCountWithinWindow: Int = 0,
        isMutating: Bool = false
    ) {
        self.label = label
        self.plistURL = plistURL
        self.scope = scope
        self.appName = appName
        self.appIconURL = appIconURL
        self.program = program
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.startInterval = startInterval
        self.watchPaths = watchPaths
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.isLoaded = isLoaded
        self.isDisabledByOverride = isDisabledByOverride
        self.pid = pid
        self.lastExitCode = lastExitCode
        self.crashCountWithinWindow = crashCountWithinWindow
        self.isMutating = isMutating
    }

    /// 严格的死循环崩溃判定逻辑 (遵循 BR-LM-02)
    public func isCrashLooping(alertThreshold: Int = 3) -> Bool {
        guard keepAlive.isEffectivelyActive else { return false }
        guard let exitCode = lastExitCode, exitCode != 0 else { return false }
        return !isRunning && crashCountWithinWindow >= alertThreshold
    }
}
