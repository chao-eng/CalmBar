import Foundation

@MainActor
public final class LaunchctlService {
    public static let shared = LaunchctlService()

    public init() {}

    /// 获取当前用户域注册的 launchd 任务状态 [Label: (pid, exitCode)]
    public func listAll() async throws -> [String: (pid: Int?, exitCode: Int?)] {
        let output = try ShellRunner.run("/bin/launchctl", arguments: ["list"])
        return parseListOutput(output)
    }

    /// 获取系统域 (system domain) 注册的守护进程状态 [Label: (pid, exitCode)]
    public func listSystemServices() async -> [String: (pid: Int?, exitCode: Int?)] {
        guard let output = try? ShellRunner.run("/bin/launchctl", arguments: ["print", "system"]) else {
            return [:]
        }
        return parsePrintSystemOutput(output)
    }

    /// 获取某作用域下禁用的标签集合
    public func fetchDisabledLabels(domain: String) async throws -> Set<String> {
        guard let output = try? ShellRunner.run("/bin/launchctl", arguments: ["print-disabled", domain]) else {
            return []
        }
        return parseDisabledOutput(output)
    }

    /// 原子重载任务 (实现 BR-LM-01 与现代 launchctl 重载规范，合并特权事务杜绝多次密码弹窗)
    public func reloadAtomic(item: LaunchItem) async throws {
        guard !item.scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let domain = item.scope.launchdDomain
        let path = item.plistURL.path

        if item.scope.requiresPrivilegeForService {
            let escapedPath = LaunchPrivilegeService.escapeShellArg(path)
            let escapedTarget = LaunchPrivilegeService.escapeShellArg("\(domain)/\(item.label)")
            let script = """
            /bin/launchctl bootout \(domain) \(escapedPath) 2>/dev/null || /bin/launchctl bootout \(escapedTarget) 2>/dev/null || true ; /bin/launchctl bootstrap \(domain) \(escapedPath) ; /bin/launchctl kickstart -k \(escapedTarget) 2>/dev/null || true
            """
            try await LaunchPrivilegeService.shared.runPrivileged(script)
        } else {
            // 1. 若当前已装载，先优雅卸载 (忽略已未加载错误)
            if item.isLoaded {
                _ = try? ShellRunner.run("/bin/launchctl", arguments: ["bootout", domain, path])
                _ = try? ShellRunner.run("/bin/launchctl", arguments: ["bootout", "\(domain)/\(item.label)"])
            }

            // 2. 重新装载
            _ = try ShellRunner.run("/bin/launchctl", arguments: ["bootstrap", domain, path])

            // 3. 唤醒任务 (kickstart -k)
            _ = try? ShellRunner.run("/bin/launchctl", arguments: ["kickstart", "-k", "\(domain)/\(item.label)"])
        }
    }

    /// 加载任务 (Bootstrap)
    public func bootstrap(_ plistURL: URL, scope: LaunchScope) async throws {
        guard !scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let domain = scope.launchdDomain
        try await runScoped(arguments: ["bootstrap", domain, plistURL.path], scope: scope)
    }

    /// 卸载任务 (Bootout via Plist Path)
    public func bootout(_ plistURL: URL, scope: LaunchScope) async throws {
        guard !scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let domain = scope.launchdDomain
        try await runScoped(arguments: ["bootout", domain, plistURL.path], scope: scope)
    }

    /// 卸载任务 (Bootout via Label Target)
    public func bootout(label: String, scope: LaunchScope) async throws {
        guard !scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let target = "\(scope.launchdDomain)/\(label)"
        try await runScoped(arguments: ["bootout", target], scope: scope)
    }

    /// 立即启动 / 重启 (Kickstart)
    public func kickstart(label: String, scope: LaunchScope) async throws {
        guard !scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let target = "\(scope.launchdDomain)/\(label)"
        try await runScoped(arguments: ["kickstart", "-k", target], scope: scope)
    }

    /// 优雅终结进程 (SIGTERM -> 异步等待 1.5s -> SIGKILL)
    public func killGracefully(item: LaunchItem) async throws {
        guard !item.scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let target = "\(item.scope.launchdDomain)/\(item.label)"
        _ = try? await runScoped(arguments: ["kill", "SIGTERM", target], scope: item.scope)

        // 异步等待 1.5 秒确认
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let active = try? await listAll()
        if let current = active?[item.label], current.pid != nil {
            _ = try? await runScoped(arguments: ["kill", "SIGKILL", target], scope: item.scope)
        }
    }

    /// 启用任务 (写入持久化 override)
    public func enable(label: String, scope: LaunchScope) async throws {
        guard !scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let target = "\(scope.launchdDomain)/\(label)"
        try await runScoped(arguments: ["enable", target], scope: scope)
    }

    /// 禁用任务 (写入持久化 override)
    public func disable(label: String, scope: LaunchScope) async throws {
        guard !scope.isReadOnly else { throw LaunchServiceError.systemProtected }
        let target = "\(scope.launchdDomain)/\(label)"
        try await runScoped(arguments: ["disable", target], scope: scope)
    }

    /// 统一的作用域命令执行器 (正确处理 systemAgent 与 systemDaemon 权限差异，避免参数加壳引起路径找不到)
    private func runScoped(arguments: [String], scope: LaunchScope) async throws {
        if scope.requiresPrivilegeForService {
            let escapedArgs = arguments.map { LaunchPrivilegeService.escapeShellArg($0) }.joined(separator: " ")
            try await LaunchPrivilegeService.shared.runPrivileged("/bin/launchctl \(escapedArgs)")
        } else {
            _ = try ShellRunner.run("/bin/launchctl", arguments: arguments)
        }
    }

    // MARK: - Testing Hooks & Parsing

    public func parseListOutputForTesting(_ output: String) -> [String: (pid: Int?, exitCode: Int?)] {
        parseListOutput(output)
    }

    public func parsePrintSystemOutputForTesting(_ output: String) -> [String: (pid: Int?, exitCode: Int?)] {
        parsePrintSystemOutput(output)
    }

    public func parseDisabledOutputForTesting(_ output: String) -> Set<String> {
        parseDisabledOutput(output)
    }

    private func parseListOutput(_ output: String) -> [String: (pid: Int?, exitCode: Int?)] {
        var map: [String: (pid: Int?, exitCode: Int?)] = [:]
        let lines = output.components(separatedBy: "\n").dropFirst()
        for line in lines {
            let cols = line.components(separatedBy: "\t")
            guard cols.count == 3 else { continue }
            let pidStr = cols[0].trimmingCharacters(in: .whitespaces)
            let exitStr = cols[1].trimmingCharacters(in: .whitespaces)
            let label = cols[2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            map[label] = (
                pid: pidStr == "-" ? nil : Int(pidStr),
                exitCode: Int(exitStr)
            )
        }
        return map
    }

    private func parsePrintSystemOutput(_ output: String) -> [String: (pid: Int?, exitCode: Int?)] {
        var map: [String: (pid: Int?, exitCode: Int?)] = [:]
        let lines = output.components(separatedBy: "\n")
        var inServicesBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "services = {") {
                inServicesBlock = true
                continue
            }
            if inServicesBlock {
                if trimmed == "}" {
                    break
                }
                // 每行格式示例: "     515      - \tcom.crystalidea.macsfancontrol.smcwrite"
                // 或 "       0      1 \tcom.apple.wifiFirmwareLoader"
                // 或 "       0   (pe) \tcom.apple.kernelmanager_helper"
                let parts = trimmed.components(separatedBy: "\t")
                let label: String
                let statusCol: String
                if parts.count >= 2 {
                    statusCol = parts[0].trimmingCharacters(in: .whitespaces)
                    label = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
                } else {
                    let tokens = trimmed.split(separator: " ").map(String.init)
                    guard tokens.count >= 2, let last = tokens.last else { continue }
                    label = last
                    statusCol = tokens.dropLast().joined(separator: " ")
                }
                guard !label.isEmpty else { continue }

                let tokens = statusCol.split(separator: " ").map(String.init)
                var pid: Int? = nil
                var exitCode: Int? = nil
                if let firstToken = tokens.first, let p = Int(firstToken), p > 0 {
                    pid = p
                }
                if tokens.count > 1, let code = Int(tokens[1]) {
                    exitCode = code
                }
                map[label] = (pid: pid, exitCode: exitCode)
            }
        }
        return map
    }

    private func parseDisabledOutput(_ output: String) -> Set<String> {
        var disabled = Set<String>()
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("=> true") || trimmed.contains("=> disabled") {
                if let key = trimmed.components(separatedBy: "=>").first?
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces), !key.isEmpty {
                    disabled.insert(key)
                }
            }
        }
        return disabled
    }
}
