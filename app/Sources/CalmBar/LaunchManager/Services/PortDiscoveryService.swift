import Foundation

@MainActor
public final class PortDiscoveryService {
    public static let shared = PortDiscoveryService()

    public init() {}

    /// 扫描所有正在监听的 TCP 端口服务（带 2.5s 超时熔断与 TOCTOU 容错）
    public func scanListeningPorts() async throws -> [ListeningServiceItem] {
        // 1. 调用 lsof -iTCP -sTCP:LISTEN -nP (设置 2.5s 超时)
        let lsofOutput: String
        do {
            lsofOutput = try await ShellRunner.runAsync("/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-nP"], timeout: 2.5)
        } catch {
            if let shellErr = error as? ShellRunnerError, case .timeout = shellErr {
                throw LaunchServiceError.timeout("端口扫描 lsof 超时")
            }
            return []
        }

        let parsedRows = parseLsofOutput(lsofOutput)
        if parsedRows.isEmpty {
            return []
        }

        // 2. 检测是否存在 Docker 容器，轻量探活
        let dockerMap = await probeDockerContainers()

        // 3. 组装 ListeningServiceItem
        var items: [ListeningServiceItem] = []
        var seenKeys = Set<String>()

        for row in parsedRows {
            let key = "\(row.port):\(row.pid)"
            guard seenKeys.insert(key).inserted else { continue }

            // TOCTOU 容错获取 command line 与 cwd（放到后台执行，避免同步 ShellRunner 阻塞主线程）
            let details = await Task.detached(priority: .utility) {
                Self.resolveProcessDetails(pid: row.pid)
            }.value
            let cmdLine = details.commandLine
            let cwd = details.workingDirectory
            let isDocker = row.processName.contains("docker-proxy")
            let containerName = isDocker ? dockerMap[row.port] : nil

            let item = ListeningServiceItem(
                port: row.port,
                protocolType: "TCP",
                pid: row.pid,
                processName: row.processName,
                commandLine: cmdLine,
                workingDirectory: cwd,
                user: row.user,
                isDocker: isDocker,
                containerName: containerName
            )
            items.append(item)
        }

        return items.sorted { $0.port < $1.port }
    }

    private struct RawLsofRow {
        let processName: String
        let pid: Int
        let user: String
        let port: Int
    }

    private func parseLsofOutput(_ output: String) -> [RawLsofRow] {
        var rows: [RawLsofRow] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("COMMAND") { continue }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 9 else { continue }

            let procName = String(parts[0])
            guard let pid = Int(parts[1]) else { continue }
            let user = String(parts[2])
            let nodeField = parts[8...].joined(separator: " ")
            guard nodeField.contains("(LISTEN)") else { continue }

            // 解析端口号，例如 *:3000 (LISTEN) 或 127.0.0.1:8080 (LISTEN)
            let nameWithoutListen = nodeField.replacingOccurrences(of: " (LISTEN)", with: "")
            if let colonIdx = nameWithoutListen.lastIndex(of: ":") {
                let portStr = String(nameWithoutListen[nameWithoutListen.index(after: colonIdx)...])
                if let port = Int(portStr) {
                    rows.append(RawLsofRow(processName: procName, pid: pid, user: user, port: port))
                }
            }
        }
        return rows
    }

    private struct ProcessDetails: Sendable {
        let commandLine: String?
        let workingDirectory: String?
    }

    nonisolated private static func resolveProcessDetails(pid: Int) -> ProcessDetails {
        var command: String? = nil
        var cwd: String? = nil

        // 查询 command line
        if let psOut = try? ShellRunner.run("/bin/ps", arguments: ["-p", "\(pid)", "-o", "command="]) {
            let trimmed = psOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { command = trimmed }
        }

        // 查询 cwd
        if let cwdOut = try? ShellRunner.run("/usr/sbin/lsof", arguments: ["-p", "\(pid)", "-a", "-d", "cwd", "-Fn"]) {
            for line in cwdOut.components(separatedBy: "\n") {
                if line.hasPrefix("n") {
                    cwd = String(line.dropFirst())
                    break
                }
            }
        }

        return ProcessDetails(commandLine: command, workingDirectory: cwd)
    }

    /// 定位 docker CLI 可执行文件（兼容 Apple Silicon Homebrew、Docker Desktop 等常见安装位置）
    private func dockerExecutablePath() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
            "\(NSHomeDirectory())/.docker/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Docker 容器轻量探活与端口映射反查 (1.5s 超时)
    private func probeDockerContainers() async -> [Int: String] {
        let dockerSocket = "/var/run/docker.sock"
        guard FileManager.default.fileExists(atPath: dockerSocket) else {
            return [:]
        }

        guard let dockerPath = dockerExecutablePath() else {
            return [:]
        }

        guard let output = try? await ShellRunner.runAsync(
            dockerPath,
            arguments: ["ps", "--format", "{{.Names}}\t{{.Ports}}"],
            timeout: 1.5
        ) else {
            return [:]
        }

        var map: [Int: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2 else { continue }
            let name = cols[0].trimmingCharacters(in: .whitespaces)
            let portsStr = cols[1]

            // 解析形如 0.0.0.0:5432->5432/tcp 中的 5432
            let portMatches = portsStr.components(separatedBy: ",")
            for match in portMatches {
                if let arrowIdx = match.range(of: "->") {
                    let hostPart = String(match[..<arrowIdx.lowerBound])
                    if let colonIdx = hostPart.lastIndex(of: ":"),
                       let port = Int(hostPart[hostPart.index(after: colonIdx)...]) {
                        map[port] = name
                    }
                }
            }
        }
        return map
    }
}
