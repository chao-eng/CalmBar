import CFNetwork
import Foundation

// MARK: - 头部与事件

public struct GatewayHeader: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public enum GatewayUpstreamEvent: Sendable {
    case response(status: Int, headers: [GatewayHeader])
    case data(Data)
    case completed(body: Data?, error: Error?)
    case timedOut(GatewayFailureKind)
    case cancelled
}

// MARK: 出站代理字典

public enum GatewayProxyDictionaryBuilder {
    public static func make(_ proxy: GatewayProxyConfig) -> [AnyHashable: Any]? {
        guard proxy.mode != .direct, proxy.isConfigured else { return nil }
        var dictionary: [AnyHashable: Any] = [:]
        switch proxy.mode {
        case .direct:
            return nil
        case .http:
            dictionary[kCFNetworkProxiesHTTPEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPProxy as String] = proxy.host
            dictionary[kCFNetworkProxiesHTTPPort as String] = proxy.port
            dictionary[kCFNetworkProxiesHTTPSEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPSProxy as String] = proxy.host
            dictionary[kCFNetworkProxiesHTTPSPort as String] = proxy.port
        case .socks5:
            dictionary[kCFNetworkProxiesSOCKSEnable as String] = true
            dictionary[kCFNetworkProxiesSOCKSProxy as String] = proxy.host
            dictionary[kCFNetworkProxiesSOCKSPort as String] = proxy.port
        }
        return dictionary
    }
}

// MARK: 上游请求构造

public enum GatewayUpstreamRequestBuilder {
    public static func makeURL(baseURL: String, endpoint: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        var path = endpoint
        // Base URL 自带版本段（/v1、/compatible-mode/v1、/api/v3）时丢弃路径里的 /v1，
        // 否则会拼出 /api/v3/v1/chat/completions 这类不存在的地址
        if path.hasPrefix("/v1/"), baseHasVersionSegment(base) {
            path.removeFirst(3)
        }
        let joined = base + path
        guard let url = URL(string: joined), url.host != nil else { return nil }
        return url
    }

    /// Base URL 的路径末段是否形如 v1 / v3 / v1beta
    private static func baseHasVersionSegment(_ base: String) -> Bool {
        guard let url = URL(string: base) else { return false }
        return url.path.range(of: #"/v\d+[A-Za-z0-9]*$"#, options: .regularExpression) != nil
    }

    public static func makeRequest(
        channel: GatewayChannelRuntime,
        endpoint: String,
        body: Data,
        isStream: Bool
    ) -> URLRequest? {
        guard let url = makeURL(baseURL: channel.baseURL, endpoint: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue(isStream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("CalmBar/AIGateway", forHTTPHeaderField: "User-Agent")
        if !channel.apiKey.isEmpty {
            switch channel.authHeader {
            case .bearer:
                request.setValue("Bearer \(channel.apiKey)", forHTTPHeaderField: "Authorization")
            case .apiKey:
                request.setValue(channel.apiKey, forHTTPHeaderField: "api-key")
            case .xApiKey:
                request.setValue(channel.apiKey, forHTTPHeaderField: "x-api-key")
            }
        }
        return request
    }
}

// MARK: - URLSession 上游连接

/// 封装单个上游请求：统一输出响应头、原始数据块与超时事件
public final class GatewayUpstreamConnection: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public let events: AsyncStream<GatewayUpstreamEvent>

    private let continuation: AsyncStream<GatewayUpstreamEvent>.Continuation
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.calmbar.aigateway.upstream")
    private let collectsBody: Bool
    private let bodyLimit: Int
    private let proxy: GatewayProxyConfig
    private let proxyPassword: String
    private let connectTimeout: TimeInterval
    private let firstContentTimeout: TimeInterval
    private let idleTimeout: TimeInterval

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false
    private var responseReceived = false
    private var hasContent = false
    private var buffered = Data()
    private var errorSample = Data()
    private let errorSampleLimit = 64 * 1024
    private var connectTimer: DispatchSourceTimer?
    private var firstContentTimer: DispatchSourceTimer?
    private var idleTimer: DispatchSourceTimer?

    public init(
        collectsBody: Bool,
        bodyLimit: Int = 8 * 1024 * 1024,
        proxy: GatewayProxyConfig = GatewayProxyConfig(),
        proxyPassword: String = "",
        connectTimeout: TimeInterval = 10,
        firstContentTimeout: TimeInterval = 300,
        idleTimeout: TimeInterval = 120
    ) {
        self.collectsBody = collectsBody
        self.bodyLimit = bodyLimit
        self.proxy = proxy
        self.proxyPassword = proxyPassword
        self.connectTimeout = connectTimeout
        self.firstContentTimeout = firstContentTimeout
        self.idleTimeout = idleTimeout

        var streamContinuation: AsyncStream<GatewayUpstreamEvent>.Continuation!
        self.events = AsyncStream { streamContinuation = $0 }
        self.continuation = streamContinuation
        super.init()
    }

    public func start(request: URLRequest) {
        let configuration = makeConfiguration()
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()

        scheduleConnectTimer()
        firstContentTimer = makeTimer(deadline: firstContentTimeout) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let content = self.hasContent
            self.lock.unlock()
            guard !content else { return }
            self.emit(.timedOut(.firstContentTimeout))
            self.cancel()
        }
        task.resume()
    }

    public func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let task = self.task
        let session = self.session
        let continuation = self.continuation
        self.task = nil
        self.session = nil
        lock.unlock()

        cancelTimers()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation.finish()
    }

    // MARK: 内部

    private func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = false
        configuration.httpShouldUsePipelining = false
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        if let dictionary = GatewayProxyDictionaryBuilder.make(proxy) {
            configuration.connectionProxyDictionary = dictionary
        }
        return configuration
    }

    private func scheduleConnectTimer() {
        connectTimer = makeTimer(deadline: connectTimeout) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let received = self.responseReceived
            self.lock.unlock()
            guard !received else { return }
            self.emit(.timedOut(.connectFailed))
            self.cancel()
        }
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        idleTimer = makeTimer(deadline: idleTimeout) { [weak self] in
            guard let self else { return }
            self.emit(.timedOut(.idleTimeout))
            self.cancel()
        }
    }

    private func makeTimer(deadline: TimeInterval, handler: @escaping @Sendable () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + deadline, repeating: .never)
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

    private func cancelTimers() {
        connectTimer?.cancel()
        firstContentTimer?.cancel()
        idleTimer?.cancel()
        connectTimer = nil
        firstContentTimer = nil
        idleTimer = nil
    }

    private func emit(_ event: GatewayUpstreamEvent) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        let continuation = self.continuation
        lock.unlock()
        continuation.yield(event)
    }

    private func finish(body: Data?, error: Error?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()

        cancelTimers()
        continuation.yield(.completed(body: body, error: error))
        continuation.finish()
        session?.finishTasksAndInvalidate()
    }

    private func failBodyTooLarge() {
        emit(.timedOut(.responseTooLarge))
        cancel()
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        lock.lock()
        responseReceived = true
        if collectsBody {
            hasContent = true
        }
        connectTimer?.cancel()
        connectTimer = nil
        lock.unlock()

        let headers = http.allHeaderFields.compactMap { key, value -> GatewayHeader? in
            guard let name = key as? String else { return nil }
            return GatewayHeader(name: name, value: String(describing: value))
        }
        emit(.response(status: http.statusCode, headers: headers))
        resetIdleTimer()
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        hasContent = true
        if errorSample.count < errorSampleLimit {
            let remaining = errorSampleLimit - errorSample.count
            errorSample.append(data.prefix(remaining))
        }
        if collectsBody {
            if buffered.count + data.count > bodyLimit {
                lock.unlock()
                failBodyTooLarge()
                return
            }
            buffered.append(data)
            lock.unlock()
        } else {
            lock.unlock()
        }
        emit(.data(data))
        resetIdleTimer()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let body = collectsBody ? buffered : errorSample
        lock.unlock()
        finish(body: body, error: error)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 不跟随重定向，原样透传 3xx
        completionHandler(nil)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let method = challenge.protectionSpace.authenticationMethod as String?,
              method == NSURLAuthenticationMethodHTTPBasic
                || method == NSURLAuthenticationMethodHTTPDigest
                || method == NSURLAuthenticationMethodNTLM,
              proxy.mode != .direct,
              !proxy.username.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(
            user: proxy.username,
            password: proxyPassword,
            persistence: .forSession
        )
        completionHandler(.useCredential, credential)
    }
}
