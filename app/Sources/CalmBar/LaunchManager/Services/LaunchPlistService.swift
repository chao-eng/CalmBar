import Foundation
import AppKit

@MainActor
public final class LaunchPlistService {
    public static let shared = LaunchPlistService()

    public init() {}

    /// 读取 Plist 字典 (支持二进制与 XML 格式)
    public func readDictionary(from url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LaunchServiceError.fileNotFound(url.path)
        }
        let data = try Data(contentsOf: url)
        guard let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw LaunchServiceError.invalidPlist("根节点不是字典")
        }
        return obj
    }

    /// 原子写入 Plist 字典 (实现 BR-LM-05: 先写临时文件，校验后再原子替换)
    public func writeDictionary(_ dict: [String: Any], to targetURL: URL) throws {
        let parentDir = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        
        let tempURL = parentDir.appendingPathComponent(".\(targetURL.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)

        // 验证临时文件格式正确
        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        // 原子替换或移动
        if FileManager.default.fileExists(atPath: targetURL.path) {
            _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
        }
    }

    /// 扫描指定作用域下的所有 Plist
    public func scanScope(_ scope: LaunchScope) async -> [LaunchItem] {
        guard let dirURL = scope.directoryURL, FileManager.default.fileExists(atPath: dirURL.path) else {
            return []
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [LaunchItem] = []
        for file in files where file.pathExtension == "plist" {
            if let item = parseItem(from: file, scope: scope) {
                items.append(item)
            }
        }
        return items
    }

    /// 解析单条 Plist 文件为 LaunchItem
    public func parseItem(from url: URL, scope: LaunchScope) -> LaunchItem? {
        guard let dict = try? readDictionary(from: url) else { return nil }
        guard let label = dict["Label"] as? String, !label.isEmpty else {
            // 如果缺少 Label，回退使用文件名
            let fallbackLabel = url.deletingPathExtension().lastPathComponent
            return buildItem(from: dict, label: fallbackLabel, url: url, scope: scope)
        }
        return buildItem(from: dict, label: label, url: url, scope: scope)
    }

    private func buildItem(from dict: [String: Any], label: String, url: URL, scope: LaunchScope) -> LaunchItem {
        let program = dict["Program"] as? String
        let programArguments = (dict["ProgramArguments"] as? [String]) ?? []
        let workingDirectory = dict["WorkingDirectory"] as? String
        let environmentVariables = (dict["EnvironmentVariables"] as? [String: String]) ?? [:]

        let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false
        let keepAlive = KeepAliveStrategy.parse(from: dict["KeepAlive"])
        let startInterval = dict["StartInterval"] as? Int
        let watchPaths = (dict["WatchPaths"] as? [String]) ?? []

        let standardOutPath = dict["StandardOutPath"] as? String
        let standardErrorPath = dict["StandardErrorPath"] as? String

        // 应用身份反查与图标提取
        let (appName, appIconURL) = resolveAppIdentity(
            program: program,
            arguments: programArguments,
            label: label
        )

        return LaunchItem(
            label: label,
            plistURL: url,
            scope: scope,
            appName: appName,
            appIconURL: appIconURL,
            program: program,
            programArguments: programArguments,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            startInterval: startInterval,
            watchPaths: watchPaths,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath
        )
    }

    /// 根据可执行路径反查归属的应用程序名称与图标
    public func resolveAppIdentity(
        program: String?,
        arguments: [String],
        label: String
    ) -> (name: String?, iconURL: URL?) {
        let execPath = program ?? arguments.first
        guard let path = execPath, !path.isEmpty else {
            return (nil, nil)
        }

        // 1. 若路径中包含 .app，向上查找 .app 根路径
        if let appRange = path.range(of: ".app") {
            let appBundlePath = String(path[..<appRange.upperBound])
            let appURL = URL(fileURLWithPath: appBundlePath)
            if FileManager.default.fileExists(atPath: appBundlePath) {
                let bundle = Bundle(url: appURL)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                return (name, appURL)
            }
        }

        // 2. 尝试从常见的 LaunchDaemons label (如 com.docker.*, com.baidu.*, com.google.*) 解析品牌名称
        return (nil, nil)
    }

    /// 按 POSIX 引号规则拆分命令行参数（支持单引号、双引号与反斜杠转义），
    /// 避免含空格的路径（如 `/Applications/My App.app/...`）被错误拆分。
    nonisolated public static func tokenizeArguments(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var hasToken = false
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for character in input {
            if isEscaping {
                current.append(character)
                hasToken = true
                isEscaping = false
                continue
            }
            if character == "\\" && !inSingleQuote {
                isEscaping = true
                hasToken = true
                continue
            }
            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                hasToken = true
                continue
            }
            if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                hasToken = true
                continue
            }
            if character == " " && !inSingleQuote && !inDoubleQuote {
                if hasToken {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }
            current.append(character)
            hasToken = true
        }

        if hasToken { result.append(current) }
        return result
    }

    /// 一键为本地监听服务生成自启 Agent Plist
    public func generateAgentDict(from service: ListeningServiceItem) -> (plistURL: URL, dict: [String: Any]) {
        let cleanName = service.processName.replacingOccurrences(of: " ", with: "-").lowercased()
        let label = "dev.local.calmbar.\(cleanName)-\(service.port)"
        let filename = "\(label).plist"
        let destURL = LaunchScope.userAgent.directoryURL!.appendingPathComponent(filename)

        var args: [String] = []
        if let cmd = service.commandLine, !cmd.isEmpty {
            args = Self.tokenizeArguments(cmd)
        }
        if args.isEmpty {
            args = [service.processName]
        }

        var dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": args,
            "RunAtLoad": true,
            "KeepAlive": true
        ]

        if let cwd = service.workingDirectory, !cwd.isEmpty {
            dict["WorkingDirectory"] = cwd
        }

        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CalmBar")
        dict["StandardOutPath"] = logsDir.appendingPathComponent("\(cleanName)-\(service.port).stdout.log").path
        dict["StandardErrorPath"] = logsDir.appendingPathComponent("\(cleanName)-\(service.port).stderr.log").path

        return (destURL, dict)
    }
}
