import Foundation

public enum ShellRunnerError: LocalizedError, Equatable {
    case nonZeroExit(code: Int32, output: String)
    case timeout(seconds: Double)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let output):
            return "命令退出码非零 (\(code)): \(output)"
        case .timeout(let sec):
            return "命令执行超时 (\(sec) 秒)"
        case .processFailed(let reason):
            return "进程启动失败: \(reason)"
        }
    }
}

public final class ShellRunner: Sendable {
    public static let shared = ShellRunner()

    public init() {}

    /// 同步运行命令并返回输出
    public static func run(_ path: String, arguments: [String] = []) throws -> String {
        try runProcess(path: path, arguments: arguments, timeout: nil)
    }

    /// 异步运行命令，支持指定超时时间（秒）
    /// 超时后直接终止子进程，确保阻塞的 waitUntilExit 能够被真正打断
    public static func runAsync(_ path: String, arguments: [String] = [], timeout: Double = 5.0) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runProcess(path: path, arguments: arguments, timeout: timeout)
        }.value
    }

    /// 统一的进程执行器：边运行边读取管道（避免子进程大输出写满缓冲区后与 waitUntilExit 互相死锁），并支持超时终止
    private static func runProcess(path: String, arguments: [String], timeout: Double?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["LC_ALL=C.UTF-8", "LANG=C.UTF-8", path] + arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outAccumulator = PipeAccumulator()
        let errAccumulator = PipeAccumulator()
        // 使用 readabilityHandler 持续抽取输出，防止子进程写满管道缓冲区后阻塞
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            outAccumulator.append(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            errAccumulator.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw ShellRunnerError.processFailed(error.localizedDescription)
        }

        // 超时熔断：轮询子进程状态，到点直接发送 SIGTERM，避免命令无限期挂起
        var didTimeout = false
        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                didTimeout = true
                process.terminate()
            }
        }

        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        // 抽取 handler 移除后，补读管道中可能残留的尾部数据
        if let rest = try? outPipe.fileHandleForReading.readToEnd() { outAccumulator.append(rest) }
        if let rest = try? errPipe.fileHandleForReading.readToEnd() { errAccumulator.append(rest) }

        let outData = outAccumulator.value
        let errData = errAccumulator.value
        let out = String(data: outData, encoding: .utf8) ?? String(decoding: outData, as: UTF8.self)
        let err = String(data: errData, encoding: .utf8) ?? String(decoding: errData, as: UTF8.self)

        if didTimeout, let timeout {
            throw ShellRunnerError.timeout(seconds: timeout)
        }

        if process.terminationStatus != 0 {
            // lsof 找不到监听端口时返回 1，属于正常空结果
            if path.hasSuffix("/lsof") && process.terminationStatus == 1 && err.isEmpty {
                return out
            }
            throw ShellRunnerError.nonZeroExit(code: process.terminationStatus, output: err.isEmpty ? out : err)
        }
        return out
    }
}

/// 线程安全的管道数据累加器 (@unchecked Sendable: 内部由 NSLock 保护)
private final class PipeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        buffer.append(chunk)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
