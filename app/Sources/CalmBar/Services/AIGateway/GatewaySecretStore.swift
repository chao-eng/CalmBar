import Foundation

/// 网关密钥的存取门面。
///
/// 实际数据统一保存在 `AppSecretStore` 的 JSON 文件中（0600），
/// 这里保留原有账号命名，便于从旧 `aigateway.db` 的 `secrets` 表平滑迁移。
public enum GatewaySecretStore {
    public static let serverKeyID = "server.accessKey"

    public static func apiKey(for channelID: String) -> String {
        AppSecretStore.shared.value(for: channelID)
    }

    @discardableResult
    public static func setAPIKey(_ value: String, for channelID: String) -> Bool {
        AppSecretStore.shared.set(value, for: channelID)
    }

    @discardableResult
    public static func removeAPIKey(for channelID: String) -> Bool {
        AppSecretStore.shared.set("", for: channelID)
    }

    public static func serverKey() -> String {
        AppSecretStore.shared.value(for: serverKeyID)
    }

    @discardableResult
    public static func setServerKey(_ value: String) -> Bool {
        AppSecretStore.shared.set(value, for: serverKeyID)
    }

    public static func proxyPassword(for keyID: String) -> String {
        AppSecretStore.shared.value(for: keyID)
    }

    @discardableResult
    public static func setProxyPassword(_ value: String, for keyID: String) -> Bool {
        AppSecretStore.shared.set(value, for: keyID)
    }
}
