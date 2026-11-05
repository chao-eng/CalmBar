import Foundation

// MARK: - 渠道连接测试（FR-09 规则 9：GET <base_url>/models，不计入统计）

public enum GatewayConnectionTestError: LocalizedError {
    case invalidURL
    case timedOut
    case httpStatus(Int, String?)
    case responseTooLarge
    case invalidModelsPayload
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Base URL 无效，无法拼接 /models"
        case .invalidModelsPayload: return "/models 返回内容无法解析出模型列表"
        case .timedOut: return "连接测试超时（连接 10 秒 / 响应 15 秒）"
        case .httpStatus(let code, let body):
            guard let body, !body.isEmpty else { return "上游返回 HTTP \(code)" }
            return "上游返回 HTTP \(code)：\(body)"
        case .responseTooLarge: return "响应体超过 1 MB，已中止测试"
        case .transport(let message): return message
        }
    }
}

public enum GatewayConnectionTester {
    /// 只验证 /models 端点可达与延迟，不代表 Chat / Responses 端点可用
    public static func test(channel: AIGatewayChannel) async throws {
        _ = try await fetchModels(channel: channel, apiKey: GatewayKeychain.apiKey(for: channel.id))
    }

    /// 拉取上游模型列表；apiKey 传入 nil 时读取钥匙串（新增渠道尚未保存时可直接用草稿中的密钥）
    public static func fetchModels(channel: AIGatewayChannel, apiKey: String? = nil) async throws -> [String] {
        guard let url = GatewayUpstreamRequestBuilder.makeURL(baseURL: channel.baseURL, endpoint: "/models") else {
            throw GatewayConnectionTestError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let apiKey = apiKey ?? GatewayKeychain.apiKey(for: channel.id)
        if !apiKey.isEmpty {
            switch channel.authHeader {
            case .bearer:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .apiKey:
                request.setValue(apiKey, forHTTPHeaderField: "api-key")
            case .xApiKey:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let proxy = GatewayProxyDictionaryBuilder.make(channel.proxy) {
            configuration.connectionProxyDictionary = proxy
        }

        let session = URLSession(
            configuration: configuration,
            delegate: NoRedirectSessionDelegate.shared,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else {
                    throw GatewayConnectionTestError.httpStatus(http.statusCode, Self.bodySnippet(from: data))
                }
            }
            guard data.count <= 1_048_576 else {
                throw GatewayConnectionTestError.responseTooLarge
            }
            return Self.parseModels(from: data)
        } catch let error as GatewayConnectionTestError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut {
                throw GatewayConnectionTestError.timedOut
            }
            throw GatewayConnectionTestError.transport(error.localizedDescription)
        }
    }

    /// 兼容 OpenAI `{data:[{id}]}`、`{models:[{id}]}` 以及纯字符串数组三种返回格式
    static func parseModels(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var ids: [String] = []
        if let array = object as? [String] {
            ids = array
        } else if let dictionary = object as? [String: Any] {
            let list = (dictionary["data"] as? [[String: Any]]) ?? (dictionary["models"] as? [[String: Any]])
            ids = (list ?? []).compactMap { $0["id"] as? String ?? $0["name"] as? String }
        }
        var seen = Set<String>()
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
    }

    /// 提取响应体摘要，便于定位 401/403 等鉴权失败原因
    private static func bodySnippet(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let head = data.prefix(4096)
        guard let text = String(data: head, encoding: .utf8) else {
            return "（非 UTF-8 响应，共 \(data.count) 字节）"
        }
        let collapsed = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count > 300 {
            return String(collapsed.prefix(300)) + "…"
        }
        return collapsed
    }
}

/// 连接测试同样不跟随 3xx 重定向（防止凭据被转发到其他主机）
private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectSessionDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
