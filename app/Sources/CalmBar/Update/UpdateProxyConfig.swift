import Foundation

/// 更新代理配置：每次使用时从 UserDefaults 实时读取，供可达性探测与
/// 本地转发服务共用，避免两处配置不一致。
struct UpdateProxyConfig {
    static let enabledKey = "CalmBar.update.proxyEnabled"
    static let hostKey = "CalmBar.update.proxyHost"
    static let portKey = "CalmBar.update.proxyPort"

    static let defaultHost = "127.0.0.1"
    static let defaultPort = 10808

    var enabled: Bool
    var host: String
    var port: Int

    static func current() -> UpdateProxyConfig {
        let defaults = UserDefaults.standard
        return UpdateProxyConfig(
            enabled: defaults.bool(forKey: enabledKey),
            host: defaults.string(forKey: hostKey) ?? "",
            port: Int(defaults.string(forKey: portKey) ?? "") ?? 0
        )
    }

    /// 只有启用且配置完整时才生效。
    var isValid: Bool {
        enabled
            && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && (1...65535).contains(port)
    }

    /// URLSession 的 HTTP/HTTPS 代理字典；未启用时返回 nil（走系统直连 / 系统代理）。
    var proxyDictionary: [String: Any]? {
        guard isValid else { return nil }
        return [
            "HTTPEnable": 1,
            "HTTPProxy": host,
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port,
        ]
    }

    /// Info.plist 中配置的更新源地址。
    static var feedURLString: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }
}

/// 更新相关请求的统一出口，与业务网络请求隔离，避免代理配置互相影响。
enum UpdateNetwork {
    static func makeConfiguration(timeout: TimeInterval,
                                  resourceTimeout: TimeInterval) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = UpdateProxyConfig.current().proxyDictionary
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = resourceTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCache = nil
        return config
    }

    /// 检查更新前探测更新服务器是否可达；拿到任意 HTTP 响应即视为网络可达。
    static func probeReachability() async -> Result<Int, Error> {
        guard let feed = UpdateProxyConfig.feedURLString,
              let url = URL(string: feed) else {
            return .failure(NSError(domain: "CalmBar.Update",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "更新源地址无效"]))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let session = URLSession(configuration: makeConfiguration(timeout: 10, resourceTimeout: 15))
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request)
            return .success((response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return .failure(error)
        }
    }
}
