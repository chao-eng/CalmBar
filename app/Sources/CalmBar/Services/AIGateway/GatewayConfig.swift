import Foundation
import Security

// MARK: - 渠道鉴权头类型

public enum GatewayAuthHeaderStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case bearer
    case apiKey = "api-key"
    case xApiKey = "x-api-key"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bearer: return "Authorization: Bearer"
        case .apiKey: return "api-key"
        case .xApiKey: return "x-api-key"
        }
    }
}

// MARK: - 出站代理

public enum GatewayProxyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case direct
    case http
    case socks5

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .direct: return "直连"
        case .http: return "HTTP 代理"
        case .socks5: return "SOCKS5"
        }
    }
}

public struct GatewayProxyConfig: Codable, Equatable, Sendable {
    public var mode: GatewayProxyMode
    public var host: String
    public var port: Int
    public var username: String
    public var passwordKeyID: String?

    public init(
        mode: GatewayProxyMode = .direct,
        host: String = "",
        port: Int = 0,
        username: String = "",
        passwordKeyID: String? = nil
    ) {
        self.mode = mode
        self.host = host
        self.port = port
        self.username = username
        self.passwordKeyID = passwordKeyID
    }

    public var isConfigured: Bool {
        mode != .direct && !host.isEmpty && port > 0 && port <= 65535
    }
}

// MARK: - 渠道与模型别名

/// 渠道支持的上游协议：自动按客户端入口透传，其余两种锁定为对应协议
public enum AIGatewayUpstreamProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case chat
    case responses

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "自动（按客户端入口）"
        case .chat: return "仅 Chat Completions"
        case .responses: return "仅 Responses"
        }
    }

    public var shortTitle: String {
        switch self {
        case .auto: return "自动"
        case .chat: return "Chat"
        case .responses: return "Responses"
        }
    }

    /// 锁定协议对应的上游路径；自动模式没有固定路径
    public var lockedEndpoint: String? {
        switch self {
        case .auto: return nil
        case .chat: return "/v1/chat/completions"
        case .responses: return "/v1/responses"
        }
    }
}

public struct AIGatewayChannel: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    /// 该渠道支持的上游模型；首项为主模型
    public var models: [String]
    public var authHeader: GatewayAuthHeaderStyle
    public var enabled: Bool
    public var proxy: GatewayProxyConfig
    /// 上游协议；默认自动（按客户端入口透传）
    public var protocolMode: AIGatewayUpstreamProtocol

    /// 主模型（models 首项），用于未显式绑定上游模型时兜底
    public var model: String { models.first ?? "" }

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        baseURL: String = "",
        model: String = "",
        authHeader: GatewayAuthHeaderStyle = .bearer,
        enabled: Bool = true,
        proxy: GatewayProxyConfig = GatewayProxyConfig(),
        protocolMode: AIGatewayUpstreamProtocol = .auto,
        models: [String] = []
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = Self.normalizedModels(models, fallback: model)
        self.authHeader = authHeader
        self.enabled = enabled
        self.proxy = proxy
        self.protocolMode = protocolMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, model, models, authHeader, enabled, proxy, protocolMode
    }

    /// 老版本配置里没有 protocolMode / models，缺失时分别按自动、单模型处理，避免整份渠道配置解码失败
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        models = Self.normalizedModels(
            try container.decodeIfPresent([String].self, forKey: .models) ?? [],
            fallback: try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        )
        authHeader = try container.decode(GatewayAuthHeaderStyle.self, forKey: .authHeader)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        proxy = try container.decode(GatewayProxyConfig.self, forKey: .proxy)
        protocolMode = try container.decodeIfPresent(AIGatewayUpstreamProtocol.self, forKey: .protocolMode) ?? .auto
    }

    /// 同时写出单值 model，保证旧版本读取配置时仍能取到主模型
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(models, forKey: .models)
        try container.encode(model, forKey: .model)
        try container.encode(authHeader, forKey: .authHeader)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(proxy, forKey: .proxy)
        try container.encode(protocolMode, forKey: .protocolMode)
    }

    static func normalizedModels(_ models: [String], fallback: String = "") -> [String] {
        var result: [String] = []
        for value in models + (fallback.isEmpty ? [] : [fallback]) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return result
    }
}

/// 模型别名在某个渠道下使用的上游模型绑定
public struct AIGatewayModelBinding: Codable, Identifiable, Equatable, Sendable {
    public var channelID: String
    /// nil 表示自动：优先同名上游模型，否则用渠道主模型
    public var upstreamModel: String?

    public init(channelID: String, upstreamModel: String? = nil) {
        self.channelID = channelID
        self.upstreamModel = upstreamModel
    }

    public var id: String { channelID }
}

public struct AIGatewayModelRoute: Codable, Identifiable, Equatable, Sendable {
    /// 客户端请求使用的模型别名
    public var alias: String
    /// 按顺序尝试的渠道绑定
    public var bindings: [AIGatewayModelBinding]

    /// 按顺序尝试的渠道 ID（由 bindings 派生）
    public var channelIDs: [String] { bindings.map(\.channelID) }

    public init(alias: String = "", bindings: [AIGatewayModelBinding] = []) {
        self.alias = alias
        self.bindings = bindings
    }

    public init(alias: String = "", channelIDs: [String]) {
        self.init(alias: alias, bindings: channelIDs.map { AIGatewayModelBinding(channelID: $0) })
    }

    public var id: String { alias }

    private enum CodingKeys: String, CodingKey {
        case alias, bindings, channelIDs
    }

    /// 老版本配置只有 channelIDs，缺失 bindings 时按自动绑定处理
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alias = try container.decode(String.self, forKey: .alias)
        if let bindings = try container.decodeIfPresent([AIGatewayModelBinding].self, forKey: .bindings) {
            self.bindings = bindings
        } else {
            let ids = try container.decodeIfPresent([String].self, forKey: .channelIDs) ?? []
            self.bindings = ids.map { AIGatewayModelBinding(channelID: $0) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alias, forKey: .alias)
        try container.encode(bindings, forKey: .bindings)
        try container.encode(channelIDs, forKey: .channelIDs)
    }
}

// MARK: - Keychain

/// 所有网关密钥合并存放在同一条钥匙串记录中。
/// ad-hoc 签名下每次重新打包都会改变 cdhash，钥匙串 ACL 必然失效；
/// 合并成单条后，更新后最多只弹一次授权，而不是按密钥数量弹多次。
public enum GatewayKeychain {
    /// 测试进程改用纯内存存储，避免读写真实配置或触发授权弹窗
    private static let isTesting: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    private static let service = "com.calmbar.aigateway"

    /// 单条记录内部以 account -> secret 的 JSON 存储
    private static let vaultAccount = "vault"

    public static let serverKeyID = "server.accessKey"

    public static func apiKey(for channelID: String) -> String {
        value(for: channelID)
    }

    public static func setAPIKey(_ value: String, for channelID: String) {
        set(value, for: channelID)
    }

    public static func removeAPIKey(for channelID: String) {
        set("", for: channelID)
    }

    public static func serverKey() -> String {
        value(for: serverKeyID)
    }

    public static func setServerKey(_ value: String) {
        set(value, for: serverKeyID)
    }

    public static func proxyPassword(for keyID: String) -> String {
        value(for: keyID)
    }

    public static func setProxyPassword(_ value: String, for keyID: String) {
        set(value, for: keyID)
    }

    // MARK: 单条记录读写

    /// 整个 vault 只从钥匙串读取一次，之后全部命中内存
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedVault: [String: String]?
    nonisolated(unsafe) private static var testingVault: [String: String] = [:]

    private static func value(for account: String) -> String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if isTesting { return testingVault[account] ?? "" }
        return loadVaultLocked()[account] ?? ""
    }

    private static func set(_ value: String, for account: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if isTesting {
            if value.isEmpty {
                testingVault.removeValue(forKey: account)
            } else {
                testingVault[account] = value
            }
            return
        }
        var vault = loadVaultLocked()
        if value.isEmpty {
            vault.removeValue(forKey: account)
        } else {
            vault[account] = value
        }
        if persist(vault) {
            cachedVault = vault
        }
    }

    /// 调用方需持有 cacheLock
    private static func loadVaultLocked() -> [String: String] {
        if let cachedVault { return cachedVault }
        let vault: [String: String]
        if let data = readVaultData(),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            vault = decoded
        } else {
            vault = [:]
        }
        cachedVault = vault
        return vault
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultAccount
        ]
    }

    /// 注：这里使用登录钥匙串（而非 kSecUseDataProtectionKeychain）。
    /// 本项目为 ad-hoc 签名、无 keychain-access-groups 权限，数据保护钥匙串写入会返回 -34018，
    /// 导致密钥实际未保存、UI 一直显示「无密钥」。
    private static func readVaultData() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func persist(_ vault: [String: String]) -> Bool {
        if vault.isEmpty {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let data = try? JSONEncoder().encode(vault) else { return false }
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

// MARK: - 运行时快照（已完成 Keychain 解析，供后台请求线程使用）

public struct GatewayChannelRuntime: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let baseURL: String
    /// 支持的上游模型；首项为主模型
    public let models: [String]
    /// 主模型（models 首项）
    public let model: String
    public let authHeader: GatewayAuthHeaderStyle
    public let apiKey: String
    public let proxy: GatewayProxyConfig
    public let proxyPassword: String
    public let protocolMode: AIGatewayUpstreamProtocol

    public init(
        id: String,
        name: String,
        baseURL: String,
        model: String,
        authHeader: GatewayAuthHeaderStyle = .bearer,
        apiKey: String = "",
        proxy: GatewayProxyConfig = GatewayProxyConfig(),
        proxyPassword: String = "",
        protocolMode: AIGatewayUpstreamProtocol = .auto,
        models: [String] = []
    ) {
        let normalized = AIGatewayChannel.normalizedModels(models, fallback: model)
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = normalized
        self.model = normalized.first ?? model
        self.authHeader = authHeader
        self.apiKey = apiKey
        self.proxy = proxy
        self.proxyPassword = proxyPassword
        self.protocolMode = protocolMode
    }
}

public struct GatewaySnapshot: Sendable, Equatable {
    public let enabled: Bool
    public let port: Int
    public let serverKey: String
    /// 渠道 ID -> 运行时配置（仅启用渠道）
    public let channels: [String: GatewayChannelRuntime]
    /// 模型别名 -> 渠道 ID 顺序
    public let modelRoutes: [String: [String]]
    /// 模型别名 -> 渠道 ID -> 显式指定的上游模型
    public let modelBindings: [String: [String: String]]
    /// 配置中声明且至少存在一个启用渠道的模型别名
    public let availableModels: [String]

    public init(
        enabled: Bool = true,
        port: Int = 8317,
        serverKey: String = "",
        channels: [String: GatewayChannelRuntime] = [:],
        modelRoutes: [String: [String]] = [:],
        modelBindings: [String: [String: String]] = [:],
        availableModels: [String] = []
    ) {
        self.enabled = enabled
        self.port = port
        self.serverKey = serverKey
        self.channels = channels
        self.modelRoutes = modelRoutes
        self.modelBindings = modelBindings
        self.availableModels = availableModels
    }

    public var hasUsableRoute: Bool { !availableModels.isEmpty }

    public func channel(named name: String) -> GatewayChannelRuntime? {
        channels.values.first { $0.name == name }
    }

    /// 解析某别名在某渠道下实际使用的上游模型：
    /// 显式绑定优先 → 渠道存在同名模型则用同名 → 否则用渠道主模型
    public func upstreamModel(alias: String, channelID: String) -> String? {
        guard let channel = channels[channelID] else { return nil }
        if let explicit = modelBindings[alias]?[channelID],
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        if channel.models.contains(alias) { return alias }
        return channel.models.first
    }
}

// MARK: - 配置校验

public enum GatewayConfigField: String, Sendable {
    case port
    case serverKey
    case channelName
    case channelBaseURL
    case channelModel
    case channelKey
    case channelProxy
    case modelAlias
    case modelChannel
}

public struct GatewayConfigIssue: Identifiable, Equatable, Sendable {
    public let field: GatewayConfigField
    public let channelID: String?
    public let modelAlias: String?
    public let message: String

    public var id: String {
        [field.rawValue, channelID ?? "", modelAlias ?? "", message].joined(separator: "|")
    }

    public init(field: GatewayConfigField, channelID: String? = nil, modelAlias: String? = nil, message: String) {
        self.field = field
        self.channelID = channelID
        self.modelAlias = modelAlias
        self.message = message
    }
}

public enum GatewayConfigValidator {
    /// 端口范围：1–65535（默认 8317）
    public static func validatePort(_ port: Int) -> GatewayConfigIssue? {
        guard (1...65535).contains(port) else {
            return GatewayConfigIssue(field: .port, message: "端口需在 1–65535 之间")
        }
        return nil
    }

    /// 访问密钥可选：留空表示不校验客户端凭据
    public static func validateServerKey(_ key: String) -> GatewayConfigIssue? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 128 else {
            return GatewayConfigIssue(field: .serverKey, message: "网关访问密钥最多 128 个字符")
        }
        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }) else {
            return GatewayConfigIssue(field: .serverKey, message: "网关访问密钥只能包含可见 ASCII 字符")
        }
        return nil
    }

    public static func validateChannel(_ channel: AIGatewayChannel) -> [GatewayConfigIssue] {
        var issues: [GatewayConfigIssue] = []
        if channel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: .channelName, channelID: channel.id, message: "渠道名称不能为空"))
        }
        if let url = URL(string: channel.baseURL),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host?.isEmpty == false,
           url.query == nil,
           url.fragment == nil {
            // 合法
        } else {
            issues.append(.init(field: .channelBaseURL, channelID: channel.id, message: "渠道 Base URL 必须是 http/https 地址，且不能包含查询参数或片段"))
        }
        if channel.models.isEmpty {
            issues.append(.init(field: .channelModel, channelID: channel.id, message: "至少配置一个上游模型"))
        }
        if channel.proxy.mode != .direct {
            if !channel.proxy.isConfigured {
                issues.append(.init(field: .channelProxy, channelID: channel.id, message: "代理地址或端口无效"))
            }
        }
        return issues
    }

    public static func validate(
        port: Int,
        serverKey: String,
        channels: [AIGatewayChannel],
        models: [AIGatewayModelRoute]
    ) -> [GatewayConfigIssue] {
        var issues: [GatewayConfigIssue] = []
        if let issue = validatePort(port) { issues.append(issue) }
        if let issue = validateServerKey(serverKey) { issues.append(issue) }
        if channels.isEmpty {
            issues.append(.init(field: .channelName, message: "至少配置一个渠道"))
        }

        let validChannels = channels.filter { channel in
            // 与快照构建口径保持一致：停用渠道不会进入运行时，不能算作可用
            channel.enabled && validateChannel(channel).isEmpty
        }
        for channel in channels {
            issues.append(contentsOf: validateChannel(channel))
        }

        let names = channels.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if Set(names.filter { !$0.isEmpty }).count != names.filter({ !$0.isEmpty }).count {
            issues.append(.init(field: .channelName, message: "渠道名称不能重复"))
        }

        let aliases = models.map { $0.alias.trimmingCharacters(in: .whitespacesAndNewlines) }
        if models.isEmpty {
            issues.append(.init(field: .modelAlias, message: "至少配置一个模型别名"))
        }
        if Set(aliases.filter { !$0.isEmpty }).count != aliases.filter({ !$0.isEmpty }).count {
            issues.append(.init(field: .modelAlias, message: "模型别名不能重复"))
        }

        let channelIDs = Set(channels.map(\.id))
        for model in models {
            let alias = model.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            if alias.isEmpty {
                issues.append(.init(field: .modelAlias, modelAlias: model.alias, message: "模型别名不能为空"))
            }
            let validMapping = model.channelIDs.filter { channelIDs.contains($0) }
            if validMapping.isEmpty {
                issues.append(.init(field: .modelChannel, modelAlias: model.alias, message: "模型别名需至少绑定一个渠道"))
            }
            if !validMapping.contains(where: { id in validChannels.contains { $0.id == id } }) {
                issues.append(.init(field: .modelChannel, modelAlias: model.alias, message: "模型别名绑定的渠道均不可用"))
            }
        }
        return issues
    }
}

// MARK: - 配置快照构建

public enum GatewaySnapshotBuilder {
    public static func makeSnapshot(
        enabled: Bool,
        port: Int,
        serverKey: String,
        channels: [AIGatewayChannel],
        models: [AIGatewayModelRoute]
    ) -> GatewaySnapshot {
        var runtimeChannels: [String: GatewayChannelRuntime] = [:]
        for channel in channels where channel.enabled {
            runtimeChannels[channel.id] = GatewayChannelRuntime(
                id: channel.id,
                name: channel.name,
                baseURL: channel.baseURL,
                model: channel.model,
                authHeader: channel.authHeader,
                apiKey: GatewayKeychain.apiKey(for: channel.id),
                proxy: channel.proxy,
                proxyPassword: channel.proxy.passwordKeyID.map { GatewayKeychain.proxyPassword(for: $0) } ?? "",
                protocolMode: channel.protocolMode,
                models: channel.models
            )
        }

        var routes: [String: [String]] = [:]
        var bindings: [String: [String: String]] = [:]
        var available: [String] = []
        for model in models {
            let alias = model.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty else { continue }
            let usable = model.bindings.filter { runtimeChannels[$0.channelID] != nil }
            routes[alias] = usable.map(\.channelID)
            let explicit = usable.reduce(into: [String: String]()) { result, binding in
                let value = binding.upstreamModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !value.isEmpty { result[binding.channelID] = value }
            }
            if !explicit.isEmpty { bindings[alias] = explicit }
            if !usable.isEmpty {
                available.append(alias)
            }
        }

        return GatewaySnapshot(
            enabled: enabled,
            port: port,
            serverKey: serverKey,
            channels: runtimeChannels,
            modelRoutes: routes,
            modelBindings: bindings,
            availableModels: available
        )
    }
}
