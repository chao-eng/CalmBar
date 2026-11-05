import Foundation

// MARK: - 失败判定

public enum GatewayFailureKind: String, Sendable {
    case connectFailed
    case firstContentTimeout
    case idleTimeout
    case upstreamHTTP
    case upstreamJSONError
    case upstreamRedirect
    case responseTooLarge
    case clientCancelled

    public var title: String {
        switch self {
        case .connectFailed: return "连接失败"
        case .firstContentTimeout: return "首内容超时"
        case .idleTimeout: return "空闲超时"
        case .upstreamHTTP: return "上游 HTTP 错误"
        case .upstreamJSONError: return "上游错误响应"
        case .upstreamRedirect: return "上游重定向"
        case .responseTooLarge: return "响应体超限"
        case .clientCancelled: return "客户端断开"
        }
    }
}

public enum GatewayFailureAction: String, Sendable {
    /// 有剩余渠道时切换，否则向客户端透传最后一次错误
    case nextChannel
    /// 直接返回给客户端，不重试
    case relay
    /// 中止请求（客户端已断开等）
    case abort
}

public struct GatewayFailure: Sendable, Equatable {
    public var kind: GatewayFailureKind
    public var action: GatewayFailureAction
    public var httpStatus: Int?
    public var message: String
    public var markQuotaCooldown: Bool = false
    public var upstreamBody: Data?

    public init(
        kind: GatewayFailureKind,
        action: GatewayFailureAction,
        httpStatus: Int? = nil,
        message: String,
        markQuotaCooldown: Bool = false,
        upstreamBody: Data? = nil
    ) {
        self.kind = kind
        self.action = action
        self.httpStatus = httpStatus
        self.message = message
        self.markQuotaCooldown = markQuotaCooldown
        self.upstreamBody = upstreamBody
    }
}

public enum GatewayErrorClassifier {
    private static let quotaKeywords = [
        "quota", "insufficient_quota", "billing", "credit", "balance",
        "余额", "配额", "欠费", "exhausted", "exceeded your current quota"
    ]

    public static func classify(statusCode: Int, body: Data, upstreamURL: URL? = nil) -> GatewayFailure {
        let text = String(decoding: body, as: UTF8.self)
        let lower = text.lowercased()
        let snippet = text.count > 300 ? String(text.prefix(300)) : text

        switch statusCode {
        case 200..<300:
            if let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
               let error = object["error"] {
                let message = (error as? [String: Any])?["message"] as? String ?? "上游返回错误响应"
                return GatewayFailure(
                    kind: .upstreamJSONError,
                    action: .nextChannel,
                    httpStatus: statusCode,
                    message: message,
                    markQuotaCooldown: containsQuotaKeyword(lower),
                    upstreamBody: body
                )
            }
            // 2xx 但无有效生成由调用方判定，这里代表可透传
            return GatewayFailure(
                kind: .upstreamHTTP,
                action: .relay,
                httpStatus: statusCode,
                message: "",
                upstreamBody: body
            )
        case 300..<400:
            return GatewayFailure(
                kind: .upstreamRedirect,
                action: .relay,
                httpStatus: statusCode,
                message: "上游返回重定向（\(statusCode)）",
                upstreamBody: body
            )
        case 408:
            return GatewayFailure(kind: .upstreamHTTP, action: .nextChannel, httpStatus: statusCode, message: "上游请求超时", upstreamBody: body)
        case 429:
            let quota = containsQuotaKeyword(lower)
            return GatewayFailure(
                kind: .upstreamHTTP,
                action: .nextChannel,
                httpStatus: statusCode,
                message: quota ? "渠道配额耗尽" : "上游限流（429）",
                markQuotaCooldown: quota,
                upstreamBody: body
            )
        case 500..<600:
            return GatewayFailure(
                kind: .upstreamHTTP,
                action: .nextChannel,
                httpStatus: statusCode,
                message: snippet.isEmpty ? "上游服务异常（\(statusCode)）" : "上游服务异常（\(statusCode)）：\(snippet)",
                upstreamBody: body
            )
        case 400, 401, 403, 404, 413, 415, 422, 451:
            var message = snippet.isEmpty ? "上游拒绝请求（\(statusCode)）" : "上游拒绝请求（\(statusCode)）：\(snippet)"
            // 404 常见于 Base URL 填错（如漏掉 /compatible-mode），带上实际请求地址便于自查
            if let upstreamURL {
                message += "（请求地址：\(upstreamURL.absoluteString)）"
            }
            return GatewayFailure(
                kind: .upstreamHTTP,
                action: .relay,
                httpStatus: statusCode,
                message: message,
                upstreamBody: body
            )
        default:
            return GatewayFailure(
                kind: .upstreamHTTP,
                action: .relay,
                httpStatus: statusCode,
                message: "上游返回 \(statusCode)",
                upstreamBody: body
            )
        }
    }

    public static func classify(error: Error, hasCommitted: Bool) -> GatewayFailure {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return GatewayFailure(kind: .clientCancelled, action: .abort, message: "请求已取消")
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return GatewayFailure(
                kind: hasCommitted ? .idleTimeout : .connectFailed,
                action: .nextChannel,
                message: hasCommitted ? "上游生成超时" : "连接上游超时"
            )
        }
        return GatewayFailure(
            kind: .connectFailed,
            action: .nextChannel,
            message: "上游连接失败：\(nsError.localizedDescription)"
        )
    }

    public static func containsQuotaKeyword(_ lowercasedText: String) -> Bool {
        quotaKeywords.contains { lowercasedText.contains($0) }
    }
}

// MARK: - 配额冷却

public final class GatewayCooldownStore: @unchecked Sendable {
    public static let shared = GatewayCooldownStore()

    private let lock = NSLock()
    private var until: [String: Date] = [:]
    private let defaultDuration: TimeInterval = 300

    private init() {}

    private func key(channelID: String, model: String) -> String {
        "\(channelID)|\(model)"
    }

    public func markQuotaExhausted(channelID: String, model: String, now: Date = Date()) {
        lock.lock()
        until[key(channelID: channelID, model: model)] = now.addingTimeInterval(defaultDuration)
        lock.unlock()
    }

    public func isCoolingDown(channelID: String, model: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let expiry = until[key(channelID: channelID, model: model)] else { return false }
        if expiry <= now {
            until.removeValue(forKey: key(channelID: channelID, model: model))
            return false
        }
        return true
    }

    public func clearAll() {
        lock.lock()
        until.removeAll()
        lock.unlock()
    }

    /// 冷却剩余秒数；未冷却返回 nil
    public func remainingSeconds(channelID: String, model: String, now: Date = Date()) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let lookup = key(channelID: channelID, model: model)
        guard let expiry = until[lookup] else { return nil }
        let remaining = expiry.timeIntervalSince(now)
        if remaining <= 0 {
            until.removeValue(forKey: lookup)
            return nil
        }
        return Int(remaining.rounded(.up))
    }
}

// MARK: - response_id → 渠道粘性映射（LRU 1000）

public final class GatewayResponseChannelMap: @unchecked Sendable {
    public static let shared = GatewayResponseChannelMap()

    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private var order: [String] = []
    private let capacity = 1000

    private init() {}

    public func record(responseID: String, channelID: String) {
        guard !responseID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if storage[responseID] == nil {
            order.append(responseID)
        }
        storage[responseID] = channelID
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public func channelID(for responseID: String?) -> String? {
        guard let responseID, !responseID.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return storage[responseID]
    }

    public func clearAll() {
        lock.lock()
        storage.removeAll()
        order.removeAll()
        lock.unlock()
    }
}

// MARK: - 统一错误体

public enum GatewayErrorPayload {
    public static func json(code: String, type: String, message: String) -> Data {
        let object: [String: Any] = [
            "error": [
                "message": message,
                "type": type,
                "code": code
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    public static func streamEvent(protocolName: GatewayStreamProtocol, code: String, message: String) -> Data {
        let errorObject: [String: Any] = [
            "error": [
                "message": message,
                "type": "upstream_error",
                "code": code
            ]
        ]
        let payload = (try? JSONSerialization.data(withJSONObject: errorObject))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"error\":{\"message\":\"upstream error\"}}"
        switch protocolName {
        case .chat:
            return Data("data: \(payload)\n\ndata: [DONE]\n\n".utf8)
        case .responses:
            return Data("event: error\ndata: \(payload)\n\n".utf8)
        }
    }
}
