import Foundation

// MARK: - 服务状态与错误

/// 文本条目的统一命名：桌面端添加与网页端上传共用同一规则，取首行前 20 个字符。
enum LANShareTextTitle {
    static let maxTitleCharacters = 20

    static func make(from text: String) -> String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let title = String(firstLine.prefix(maxTitleCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "文本片段" : title
    }
}

public enum LANShareStatus: String, Sendable {
    case stopped
    case starting
    case running
    case restricted
    case failed
}

public enum LANShareError: Error, Equatable, Sendable {
    case invalidPort
    case portInUse(Int)
    case directoryNotWritable(String)
    case noLocalNetwork
    case permissionDenied
    case pathRejected
    case itemNotFound
    case itemInvalid
    case diskFull
    case fileTooLarge
    case unsupportedMedia
    case unauthorized
    case rateLimited
    case serverFailed(String)
    case internalFailure(String)

    public var httpStatus: Int {
        switch self {
        case .invalidPort, .invalidRequest:
            return 400
        case .unauthorized:
            return 401
        case .permissionDenied, .pathRejected:
            return 403
        case .itemNotFound, .itemInvalid:
            return 404
        case .unsupportedMedia:
            return 415
        case .fileTooLarge:
            return 413
        case .rateLimited:
            return 429
        case .diskFull:
            return 507
        case .portInUse, .directoryNotWritable, .noLocalNetwork, .serverFailed, .internalFailure:
            return 500
        }
    }

    public var userMessage: String {
        switch self {
        case .invalidPort:
            return "端口不合法，请输入 1024 到 65535 之间的端口"
        case .portInUse(let port):
            return "端口 \(port) 已被占用，请换一个端口"
        case .directoryNotWritable:
            return "接收文件夹不可写，请重新选择"
        case .noLocalNetwork:
            return "未连接到局域网，请先连接 Wi-Fi 或有线网络"
        case .permissionDenied:
            return "被系统阻止，请在系统设置中允许 CalmBar 使用本地网络"
        case .pathRejected:
            return "没有访问权限"
        case .itemNotFound, .itemInvalid:
            return "内容已被移除"
        case .diskFull:
            return "磁盘空间不足，请清理后重试"
        case .fileTooLarge:
            return "文件超过 20GB 上限"
        case .unsupportedMedia:
            return "请求格式不受支持"
        case .unauthorized:
            return "链接已失效，请向对方重新获取"
        case .rateLimited:
            return "尝试过于频繁，请稍后再试"
        case .serverFailed:
            return "服务出错了，请重试"
        case .internalFailure:
            return "服务出错了，请重试"
        case .invalidRequest:
            return "请求有误，请刷新页面重试"
        }
    }

    public var nextStep: String? {
        switch self {
        case .invalidPort, .portInUse:
            return "在设置中修改端口后重新开启"
        case .directoryNotWritable:
            return "重新选择一个可写的接收文件夹"
        case .noLocalNetwork:
            return "连接网络后点击重试"
        case .permissionDenied:
            return "前往系统设置打开本地网络权限"
        default:
            return nil
        }
    }

    /// 补充一个不在主枚举中的请求错误，避免将 400 一律映射成服务端错误。
    case invalidRequest
}

// MARK: - 设置

public struct LANShareSettings: Codable, Equatable, Sendable {
    public var receiveDirectory: String
    public var port: Int
    public var passcodeEnabled: Bool
    public var allowUpload: Bool
    public var serverName: String
    public var selectedInterface: String?

    public static var defaultReceiveDirectory: String {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CalmBar 互传", isDirectory: true)
        return downloads?.path ?? (NSHomeDirectory() + "/Downloads/CalmBar 互传")
    }

    public static var defaultServerName: String {
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return name.isEmpty ? "我的 Mac" : name
    }

    public static var `default`: LANShareSettings {
        LANShareSettings(
            receiveDirectory: defaultReceiveDirectory,
            port: LANShareLimits.defaultPort,
            passcodeEnabled: false,
            allowUpload: true,
            serverName: defaultServerName,
            selectedInterface: nil
        )
    }

    public init(
        receiveDirectory: String = LANShareSettings.defaultReceiveDirectory,
        port: Int = LANShareLimits.defaultPort,
        passcodeEnabled: Bool = false,
        allowUpload: Bool = true,
        serverName: String = LANShareSettings.defaultServerName,
        selectedInterface: String? = nil
    ) {
        self.receiveDirectory = receiveDirectory
        self.port = port
        self.passcodeEnabled = passcodeEnabled
        self.allowUpload = allowUpload
        self.serverName = serverName
        self.selectedInterface = selectedInterface
    }
}

// MARK: - 分享条目

public enum LANShareItemKind: String, Codable, Sendable {
    case file
    case folder
    case text
}

public enum LANShareItemSource: String, Codable, Sendable {
    case local
    case remote
}

public struct LANShareItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: LANShareItemKind
    public var name: String
    public var path: String?
    public var text: String?
    public var intro: String?
    public var size: Int64?
    public var addedAt: Date
    public var source: LANShareItemSource
    public var uploaderIP: String?
    public var isValid: Bool
    public var invalidReason: String?

    public init(
        id: String = UUID().uuidString,
        kind: LANShareItemKind,
        name: String,
        path: String? = nil,
        text: String? = nil,
        intro: String? = nil,
        size: Int64? = nil,
        addedAt: Date = Date(),
        source: LANShareItemSource = .local,
        uploaderIP: String? = nil,
        isValid: Bool = true,
        invalidReason: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.text = text
        self.intro = intro
        self.size = size
        self.addedAt = addedAt
        self.source = source
        self.uploaderIP = uploaderIP
        self.isValid = isValid
        self.invalidReason = invalidReason
    }

    /// 展示用体积：文件夹大小未知时返回空。
    public var sizeText: String? {
        guard let size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - 传输任务

public enum LANShareTransferDirection: String, Sendable {
    case download
    case upload
}

public enum LANShareTransferState: String, Sendable {
    case waiting
    case transferring
    case completed
    case failed
    case cancelled
}

public struct LANShareTransferTask: Identifiable, Equatable, Sendable {
    public var id: String
    public var itemID: String?
    public var fileName: String
    public var peerIP: String
    public var direction: LANShareTransferDirection
    public var totalBytes: Int64
    public var transferredBytes: Int64
    public var bytesPerSecond: Double
    public var startedAt: Date
    public var state: LANShareTransferState
    public var errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        itemID: String? = nil,
        fileName: String,
        peerIP: String,
        direction: LANShareTransferDirection,
        totalBytes: Int64 = 0,
        transferredBytes: Int64 = 0,
        bytesPerSecond: Double = 0,
        startedAt: Date = Date(),
        state: LANShareTransferState = .waiting,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.fileName = fileName
        self.peerIP = peerIP
        self.direction = direction
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.bytesPerSecond = bytesPerSecond
        self.startedAt = startedAt
        self.state = state
        self.errorMessage = errorMessage
    }
}

// MARK: - 权限与状态快照

public struct LANSharePermissions: Codable, Equatable, Sendable {
    public var download: Bool
    public var upload: Bool
    public var text: Bool

    public init(download: Bool = true, upload: Bool = true, text: Bool = true) {
        self.download = download
        self.upload = upload
        self.text = text
    }

    public static func from(settings: LANShareSettings) -> LANSharePermissions {
        LANSharePermissions(download: true, upload: settings.allowUpload, text: settings.allowUpload)
    }
}

public struct LANShareSnapshot: Sendable {
    public var status: LANShareStatus
    public var port: Int
    public var shareURL: String?
    public var networkAddress: String?
    public var networkPrefix: String?
    public var sessionCount: Int
    public var connectionCount: Int
    public var transferCount: Int
    public var lastError: LANShareError?

    public init(
        status: LANShareStatus = .stopped,
        port: Int = LANShareLimits.defaultPort,
        shareURL: String? = nil,
        networkAddress: String? = nil,
        networkPrefix: String? = nil,
        sessionCount: Int = 0,
        connectionCount: Int = 0,
        transferCount: Int = 0,
        lastError: LANShareError? = nil
    ) {
        self.status = status
        self.port = port
        self.shareURL = shareURL
        self.networkAddress = networkAddress
        self.networkPrefix = networkPrefix
        self.sessionCount = sessionCount
        self.connectionCount = connectionCount
        self.transferCount = transferCount
        self.lastError = lastError
    }
}

// MARK: - 限制常量

public enum LANShareLimits {
    public static let defaultPort = 47820
    public static let autoFallbackPorts = 47820...47829
    public static let minPort = 1024
    public static let maxPort = 65535

    public static let maxHeaderBytes = 16 * 1024
    public static let maxHeaderCount = 100
    public static let maxJSONBytes = 1024 * 1024
    public static let maxFileBytes: Int64 = 20 * 1024 * 1024 * 1024
    public static let maxRequestBodyBytes: Int64 = maxFileBytes + 8 * 1024 * 1024
    public static let maxMultipartParts = 8
    public static let maxPartHeaderBytes = 8 * 1024
    public static let maxBoundaryLength = 70
    public static let maxTextCharacters = 100_000

    public static let receiveChunk = 64 * 1024
    public static let connectionHighWatermark = 1024 * 1024
    public static let connectionLowWatermark = 256 * 1024
    public static let globalBodyBufferLimit = 32 * 1024 * 1024
    public static let downloadChunk = 1024 * 1024

    public static let sessionTTL: TimeInterval = 30 * 60
    public static let maxSessions = 5
    public static let maxConnectionsPerIP = 8
    public static let maxConnectionsGlobal = 64
    public static let maxDownloadsPerIP = 4
    public static let headerTimeout: TimeInterval = 10
    public static let bodyIdleTimeout: TimeInterval = 30
    public static let uploadTotalTimeout: TimeInterval = 24 * 60 * 60
}

// MARK: - HTTP 基础对象

public struct LANShareHTTPHeader: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct LANShareHTTPRequestHead: Equatable, Sendable {
    public let method: String
    public let rawTarget: String
    public let rawPath: String
    public let rawQuery: String?
    public let decodedPath: String
    public let version: String
    public let headers: [LANShareHTTPHeader]

    public init(
        method: String,
        rawTarget: String,
        rawPath: String,
        rawQuery: String?,
        decodedPath: String,
        version: String,
        headers: [LANShareHTTPHeader]
    ) {
        self.method = method
        self.rawTarget = rawTarget
        self.rawPath = rawPath
        self.rawQuery = rawQuery
        self.decodedPath = decodedPath
        self.version = version
        self.headers = headers
    }

    public func value(forHeader name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func values(forHeader name: String) -> [String] {
        headers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }

    public var hostHeader: String? { value(forHeader: "Host") }

    public var contentLength: Int64? {
        guard let raw = value(forHeader: "Content-Length") else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespaces))
    }

    public var contentType: String? { value(forHeader: "Content-Type") }

    public var expectContinue: Bool {
        value(forHeader: "Expect")?.caseInsensitiveCompare("100-continue") == .orderedSame
    }

    /// 查询参数单次解析，不做额外解码（与 Path 分离）。
    public var queryItems: [String: String] {
        guard let rawQuery, !rawQuery.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
            if result[key] == nil { result[key] = value }
        }
        return result
    }
}

// MARK: - 编码工具

enum LANShareJSON {
    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
    }

    static func string(_ object: Any) -> String {
        String(decoding: data(object), as: UTF8.self)
    }
}

func formattedPeerIP(_ ip: String) -> String {
    // 只保留末尾一段，避免在 UI/日志中暴露完整来源地址
    if ip.contains(":") {
        return ip
    }
    let parts = ip.split(separator: ".")
    if parts.count == 4 { return "*." + parts.suffix(2).joined(separator: ".") }
    return ip
}
