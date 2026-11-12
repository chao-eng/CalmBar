import Combine
import Foundation

/// 本地 AI API Gateway 的运行时服务：负责监听、请求分发与状态广播
@MainActor
public final class GatewayService: ObservableObject {
    public enum Status: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case failed(String)

        public var title: String {
            switch self {
            case .stopped: return "未启用"
            case .starting: return "正在启动"
            case .running(let port): return "运行中 · \(port)"
            case .failed: return "启动失败"
            }
        }

        public var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    public static let shared = GatewayService()

    @Published public private(set) var status: Status = .stopped
    @Published public private(set) var activeRequests = 0
    @Published public private(set) var totalRequests = 0
    @Published public private(set) var lastError: String?
    /// 每次落库后自增，供 UI 触发刷新
    @Published public private(set) var revision = 0

    private let server = GatewayHTTPServer()
    private var cancellables = Set<AnyCancellable>()
    private var runningPort: Int?
    private var isApplying = false
    /// 配置快照缓存：避免每个请求都重新读取钥匙串；配置变化时由 applyConfiguration 重建
    private var cachedSnapshot: GatewaySnapshot?

    private init() {
        server.setRequestHandler { [weak self] request, connection in
            guard let self else {
                connection.close()
                return
            }
            await self.handle(request: request, connection: connection)
        }
        server.onReady = { [weak self] port in
            Task { @MainActor in
                guard let self else { return }
                self.runningPort = Int(port)
                self.status = .running(port: Int(port))
            }
        }
        server.onListenerFailure = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.runningPort = nil
                self.status = .failed(message)
                self.lastError = message
            }
        }

        let settings = AppSettings.shared
        // @Published 订阅时会立即发送当前值，这里 dropFirst 避免与下面的首次 applyConfiguration 重复
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$aiGatewayEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$aiGatewayPort.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$aiGatewayChannels.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$aiGatewayModels.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(triggers)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.applyConfiguration()
            }
            .store(in: &cancellables)

        applyConfiguration()
    }

    // MARK: 生命周期

    public func applyConfiguration() {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        cachedSnapshot = nil
        let settings = AppSettings.shared
        guard settings.aiGatewayEnabled else {
            if runningPort != nil {
                server.stop()
                runningPort = nil
            }
            status = .stopped
            return
        }

        let issues = GatewayConfigValidator.validate(
            port: settings.aiGatewayPort,
            serverKey: GatewaySecretStore.serverKey(),
            channels: settings.aiGatewayChannels,
            models: settings.aiGatewayModels
        )
        if let issue = issues.first {
            stopServer()
            status = .failed(issue.message)
            lastError = issue.message
            return
        }

        let snapshot = Self.makeSnapshot()
        cachedSnapshot = snapshot
        guard snapshot.hasUsableRoute else {
            stopServer()
            status = .failed("至少需要一个可用模型别名与渠道")
            lastError = status.title
            return
        }

        if runningPort == snapshot.port, status.isRunning {
            return
        }

        stopServer()
        status = .starting
        do {
            try server.start(port: snapshot.port)
            runningPort = snapshot.port
        } catch {
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    /// 配置项（如 Keychain 中的密钥）变更后由设置页调用
    public func restart() {
        stopServer()
        applyConfiguration()
    }

    public func stop() {
        AppSettings.shared.aiGatewayEnabled = false
        stopServer()
        status = .stopped
    }

    /// 应用退出时仅停止监听，不修改用户的启用偏好
    public func shutdown() {
        stopServer()
        status = .stopped
    }

    private func stopServer() {
        server.stop()
        runningPort = nil
    }

    // MARK: 请求接入

    nonisolated func handle(request: GatewayHTTPRequest, connection: GatewayHTTPConnection) async {
        let snapshot = await MainActor.run { GatewayService.currentSnapshot() }
        guard snapshot.enabled else {
            let body = GatewayErrorPayload.json(code: "gateway_disabled", type: "gateway_error", message: "网关未启用")
            await connection.respond(status: 503, headers: [], body: body)
            return
        }

        let accepted = await MainActor.run { () -> Bool in
            guard activeRequests < 64 else { return false }
            activeRequests += 1
            return true
        }
        guard accepted else {
            let body = GatewayErrorPayload.json(code: "server_busy", type: "gateway_error", message: "并发请求超过 64，请稍后重试")
            await connection.respond(status: 503, headers: [], body: body)
            return
        }
        defer {
            Task { @MainActor in
                GatewayService.shared.activeRequests = max(0, GatewayService.shared.activeRequests - 1)
            }
        }

        let processor = GatewayRequestProcessor(snapshot: snapshot)
        let record = await processor.run(request: request, connection: connection)

        if let record {
            try? await GatewayDatabase.shared.insert(record)
            await MainActor.run {
                GatewayService.shared.totalRequests += 1
                GatewayService.shared.revision += 1
                if record.status != .success {
                    GatewayService.shared.lastError = record.errorMessage
                }
            }
        }
    }

    // MARK: 查询辅助

    /// 优先返回缓存快照；缓存失效时才重建（避免每个请求都访问钥匙串）
    @MainActor
    public static func currentSnapshot() -> GatewaySnapshot {
        let service = GatewayService.shared
        if let cached = service.cachedSnapshot { return cached }
        let snapshot = makeSnapshot()
        service.cachedSnapshot = snapshot
        return snapshot
    }

    @MainActor
    private static func makeSnapshot() -> GatewaySnapshot {
        let settings = AppSettings.shared
        return GatewaySnapshotBuilder.makeSnapshot(
            enabled: settings.aiGatewayEnabled,
            port: settings.aiGatewayPort,
            serverKey: GatewaySecretStore.serverKey(),
            channels: settings.aiGatewayChannels,
            models: settings.aiGatewayModels
        )
    }

    public static var endpoint: String {
        "http://127.0.0.1:\(AppSettings.shared.aiGatewayPort)/v1"
    }

    public var validationIssues: [GatewayConfigIssue] {
        let settings = AppSettings.shared
        return GatewayConfigValidator.validate(
            port: settings.aiGatewayPort,
            serverKey: GatewaySecretStore.serverKey(),
            channels: settings.aiGatewayChannels,
            models: settings.aiGatewayModels
        )
    }

    public func series(range: GatewayRange, metric: GatewayMetric = .speed) async -> GatewaySeriesResult {
        do {
            return try await GatewayDatabase.shared.series(range: range, metric: metric)
        } catch {
            return .empty
        }
    }

    public func summary(range: GatewayRange) async -> GatewayWindowSummary {
        (try? await GatewayDatabase.shared.summary(range: range)) ?? .empty
    }

    public func channelSummaries(
        range: GatewayRange,
        limit: Int = 3,
        metric: GatewayRankingMetric = .requests
    ) async -> [GatewayChannelSummary] {
        (try? await GatewayDatabase.shared.channelSummaries(range: range, limit: limit, metric: metric)) ?? []
    }

    public func recentRequests(limit: Int, offset: Int) async -> [GatewayRequestRecord] {
        (try? await GatewayDatabase.shared.recent(limit: limit, offset: offset)) ?? []
    }

    public func deleteAllHistory() async {
        try? await GatewayDatabase.shared.deleteAll()
        await MainActor.run {
            self.revision += 1
        }
    }

    public func clearLastError() {
        lastError = nil
    }
}
