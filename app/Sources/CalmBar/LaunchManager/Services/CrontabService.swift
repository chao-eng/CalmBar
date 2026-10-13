import Foundation

public final class CrontabService: Sendable {
    public static let shared = CrontabService()
    public static let systemCrontabPath = "/etc/crontab"

    public init() {}

    public func readUserCrontab() throws -> String {
        do {
            return try ShellRunner.run("/usr/bin/crontab", arguments: ["-l"])
        } catch let error as ShellRunnerError {
            switch error {
            case .nonZeroExit(let code, let output):
                if code == 1 && output.localizedCaseInsensitiveContains("no crontab") {
                    return ""
                }
                throw error
            default:
                throw error
            }
        }
    }

    public func readSystemCrontab() -> String {
        guard FileManager.default.fileExists(atPath: Self.systemCrontabPath),
              let content = try? String(contentsOfFile: Self.systemCrontabPath, encoding: .utf8) else {
            return ""
        }
        return content
    }

    public func writeUserCrontab(_ content: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = ["-"]

        let stdinPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        let data = Data(content.utf8)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        try stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ShellRunnerError.nonZeroExit(code: process.terminationStatus, output: err)
        }
    }

    public func writeSystemCrontab(_ content: String) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("calmbar_crontab_\(UUID().uuidString)")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        let escapedTemp = LaunchPrivilegeService.escapeShellArg(tempURL.path)
        let script = "/bin/cp -f \(escapedTemp) /etc/crontab && /bin/chmod 644 /etc/crontab ; /bin/rm -f \(escapedTemp)"
        try await LaunchPrivilegeService.shared.runPrivileged(script)
    }

    /// 将用户可能输入的多行 Shell 脚本自动安全扁平化为符合 POSIX 规范的单行 Crontab 命令
    public static func normalizeCommandForCrontab(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        var processed: [String] = []
        let noSemicolonEnds: Set<String> = ["then", "do", "else", "elif", "{", "(", "&&", "||", "|", ";"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasSuffix("\\") {
                let stripped = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty {
                    processed.append(stripped)
                }
                continue
            }
            processed.append(trimmed)
        }

        guard !processed.isEmpty else { return "" }
        if processed.count == 1 {
            return processed[0]
        }

        var normalizedTokens: [String] = []
        for (index, token) in processed.enumerated() {
            if index < processed.count - 1 {
                let endsWithNoSemi = noSemicolonEnds.contains { token.hasSuffix($0) }
                if endsWithNoSemi {
                    normalizedTokens.append(token)
                } else {
                    normalizedTokens.append(token + ";")
                }
            } else {
                normalizedTokens.append(token)
            }
        }

        var merged = normalizedTokens.joined(separator: " ")
        while merged.contains("; ;") {
            merged = merged.replacingOccurrences(of: "; ;", with: ";")
        }
        return merged.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Parsing

    public func parseLines(_ text: String, scope: CrontabScope) -> [CrontabLine] {
        let normalized = text.hasSuffix("\n") ? String(text.dropLast()) : text
        guard !normalized.isEmpty else { return [] }

        return normalized
            .components(separatedBy: "\n")
            .map { parseLine($0, scope: scope) }
    }

    public func fetchAllJobs() -> [CronJob] {
        var result: [CronJob] = []

        // 1. 用户定时任务
        if let userText = try? readUserCrontab() {
            let lines = parseLines(userText, scope: .user)
            result.append(contentsOf: extractJobs(from: lines, scope: .user))
        }

        // 2. 系统定时任务
        let systemText = readSystemCrontab()
        if !systemText.isEmpty {
            let lines = parseLines(systemText, scope: .system)
            result.append(contentsOf: extractJobs(from: lines, scope: .system))
        }

        return result
    }

    public func toggleJob(_ targetJob: CronJob) async throws {
        if targetJob.scope == .user {
            let currentText = (try? readUserCrontab()) ?? ""
            var lines = parseLines(currentText, scope: .user)

            for i in 0..<lines.count {
                if case .job(var job) = lines[i], job.id == targetJob.id || (job.command == targetJob.command && job.cronExpression == targetJob.cronExpression) {
                    job.isEnabled.toggle()
                    lines[i] = .job(job)
                    break
                }
            }

            let newContent = serialize(lines: lines, scope: .user)
            try writeUserCrontab(newContent)
        } else {
            let currentText = readSystemCrontab()
            var lines = parseLines(currentText, scope: .system)

            for i in 0..<lines.count {
                if case .job(var job) = lines[i], job.id == targetJob.id || (job.command == targetJob.command && job.cronExpression == targetJob.cronExpression) {
                    job.isEnabled.toggle()
                    lines[i] = .job(job)
                    break
                }
            }

            let newContent = serialize(lines: lines, scope: .system)
            try await writeSystemCrontab(newContent)
        }
    }

    public func deleteJob(_ targetJob: CronJob) async throws {
        if targetJob.scope == .user {
            let currentText = (try? readUserCrontab()) ?? ""
            var lines = parseLines(currentText, scope: .user)
            lines.removeAll { line in
                if case .job(let job) = line {
                    return job.id == targetJob.id || (job.command == targetJob.command && job.cronExpression == targetJob.cronExpression)
                }
                return false
            }

            let newContent = serialize(lines: lines, scope: .user)
            try writeUserCrontab(newContent)
        } else {
            let currentText = readSystemCrontab()
            var lines = parseLines(currentText, scope: .system)
            lines.removeAll { line in
                if case .job(let job) = line {
                    return job.id == targetJob.id || (job.command == targetJob.command && job.cronExpression == targetJob.cronExpression)
                }
                return false
            }

            let newContent = serialize(lines: lines, scope: .system)
            try await writeSystemCrontab(newContent)
        }
    }

    public func addJob(_ newJob: CronJob) async throws {
        var job = newJob
        job.command = Self.normalizeCommandForCrontab(newJob.command)

        if job.scope == .user {
            let currentText = (try? readUserCrontab()) ?? ""
            var lines = parseLines(currentText, scope: .user)
            lines.append(.job(job))

            let newContent = serialize(lines: lines, scope: .user)
            try writeUserCrontab(newContent)
        } else {
            let currentText = readSystemCrontab()
            var lines = parseLines(currentText, scope: .system)
            lines.append(.job(job))

            let newContent = serialize(lines: lines, scope: .system)
            try await writeSystemCrontab(newContent)
        }
    }

    public func serialize(lines: [CrontabLine], scope: CrontabScope) -> String {
        let body = lines.map { serializeLine($0, scope: scope) }.joined(separator: "\n")
        return body.isEmpty ? "" : body + "\n"
    }

    // MARK: - Helpers

    private func extractJobs(from lines: [CrontabLine], scope: CrontabScope) -> [CronJob] {
        lines.compactMap { line in
            guard case .job(var job) = line else { return nil }
            job.scope = scope
            return job
        }
    }

    private func parseLine(_ line: String, scope: CrontabScope) -> CrontabLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .blank(id: UUID())
        }

        // 被注释停用的 cron 任务 (例如 "# 0 2 * * * /usr/bin/backup")
        if trimmed.hasPrefix("#") {
            let remainder = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let fields = parseCronFields(remainder, scope: scope) {
                return makeJobLine(fields: fields, scope: scope, isEnabled: false)
            }
            return .comment(id: UUID(), text: line)
        }

        if let fields = parseCronFields(trimmed, scope: scope) {
            return makeJobLine(fields: fields, scope: scope, isEnabled: true)
        }

        return .raw(id: UUID(), line: line)
    }

    private func parseCronFields(_ line: String, scope: CrontabScope) -> [String]? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let minTokens = scope == .user ? 6 : 7
        guard tokens.count >= minTokens else { return nil }

        let timeFields = Array(tokens.prefix(5))
        for f in timeFields {
            if !isValidCronField(f) { return nil }
        }

        if scope == .user {
            let command = tokens.dropFirst(5).joined(separator: " ")
            return timeFields + [command]
        } else {
            let runAsUser = tokens[5]
            let command = tokens.dropFirst(6).joined(separator: " ")
            return timeFields + [runAsUser, command]
        }
    }

    private func isValidCronField(_ token: String) -> Bool {
        // 允许数字、*、/、,、-、? 等标准 cron 符号
        let allowed = CharacterSet(charactersIn: "0123456789*,-/?")
        return !token.isEmpty && token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func makeJobLine(fields: [String], scope: CrontabScope, isEnabled: Bool) -> CrontabLine {
        if scope == .user {
            return .job(CronJob(
                minute: fields[0],
                hour: fields[1],
                dayOfMonth: fields[2],
                month: fields[3],
                weekday: fields[4],
                command: fields[5],
                isEnabled: isEnabled
            ))
        } else {
            return .job(CronJob(
                scope: .system,
                minute: fields[0],
                hour: fields[1],
                dayOfMonth: fields[2],
                month: fields[3],
                weekday: fields[4],
                runAsUser: fields[5],
                command: fields[6],
                isEnabled: isEnabled
            ))
        }
    }

    private func serializeLine(_ line: CrontabLine, scope: CrontabScope) -> String {
        switch line {
        case .blank:
            return ""
        case .comment(_, let text):
            return text
        case .environment(_, let key, let value):
            return "\(key)=\(value)"
        case .job(let job):
            let prefix = job.isEnabled ? "" : "# "
            if scope == .user {
                return "\(prefix)\(job.minute) \(job.hour) \(job.dayOfMonth) \(job.month) \(job.weekday) \(job.command)"
            } else {
                let user = job.runAsUser ?? "root"
                return "\(prefix)\(job.minute) \(job.hour) \(job.dayOfMonth) \(job.month) \(job.weekday) \(user) \(job.command)"
            }
        case .raw(_, let rawText):
            return rawText
        }
    }
}
