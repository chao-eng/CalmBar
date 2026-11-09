import Darwin
import Foundation
import Network
import UniformTypeIdentifiers

// MARK: - 局域网 HTTP 服务

public final class LANShareHTTPServer: @unchecked Sendable {
    public struct Callbacks: Sendable {
        public var onReady: @Sendable (Int) -> Void
        public var onFailure: @Sendable (LANShareError) -> Void
        public var onConnectionCountChanged: @Sendable (Int) -> Void
        public var onItemAdded: @Sendable (LANShareItem) -> Void
        public var onLog: @Sendable (String) -> Void

        public init(
            onReady: @escaping @Sendable (Int) -> Void,
            onFailure: @escaping @Sendable (LANShareError) -> Void,
            onConnectionCountChanged: @escaping @Sendable (Int) -> Void,
            onItemAdded: @escaping @Sendable (LANShareItem) -> Void,
            onLog: @escaping @Sendable (String) -> Void
        ) {
            self.onReady = onReady
            self.onFailure = onFailure
            self.onConnectionCountChanged = onConnectionCountChanged
            self.onItemAdded = onItemAdded
            self.onLog = onLog
        }
    }

    // MARK: 内部类型

    private enum Route: Equatable {
        case index
        case asset(String)
        case bootstrap
        case createSession
        case deleteSession
        case state
        case items
        case download
        case upload
        case text
        case notFound
        case methodNotAllowed
    }

    private enum JSONPurpose {
        case session
        case text
    }

    private enum BodyMode {
        case json(JSONPurpose)
        case multipart(LANShareMultipartParser)
    }

    private final class Context: @unchecked Sendable {
        let id = UUID().uuidString
        let connection: NWConnection
        let peerIP: String
        let parser = LANShareHTTPParser()
        var head: LANShareHTTPRequestHead?
        var route: Route = .notFound
        var bodyMode: BodyMode?
        var jsonBuffer = Data()
        var responseSent = false
        var closed = false
        var counted = false
        var rejectStatus: Int?
        var timer: DispatchWorkItem?
        var timerGeneration = 0
        var lastActivityAt = Date()
        var uploadTaskID: String?
        var uploadBytes: Int64 = 0
        var uploadCommitted = false
        var downloadTaskID: String?
        var downloadSlot = false
        var fileFD: Int32 = -1
        var tempURL: URL?
        var sessionToken: String?

        init(connection: NWConnection, peerIP: String) {
            self.connection = connection
            self.peerIP = peerIP
        }
    }

    private struct ByteRange {
        let start: Int64
        let length: Int64
    }

    // MARK: 属性

    private let queue = DispatchQueue(label: "com.calmbar.lanshare.server")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let store: LANShareStore
    private let sessions: LANShareSessionManager
    private let transfers: LANShareTransferManager
    private let zipper: LANShareZipper
    private let settings: LANShareSettings
    private let network: LANShareNetworkAddress
    private let webRoot: URL
    private let receiveDirectory: URL
    private let temporaryDirectory: URL
    private let callbacks: Callbacks

    private var listener: NWListener?
    private var contexts: [String: Context] = [:]
    private var connectionsPerIP: [String: Int] = [:]
    private var downloadsPerIP: [String: Int] = [:]
    private var activeConnections = 0
    private var actualPort: Int = 0
    private var candidates: [Int] = []
    private var candidateIndex = 0
    private var stopped = false
    private var allowUpload: Bool
    private var allowedHosts: Set<String> = []
    /// 监听长期停留在 `.waiting` 时的兜底超时。
    private var waitingTimer: DispatchWorkItem?

    public init(
        store: LANShareStore,
        sessions: LANShareSessionManager,
        transfers: LANShareTransferManager,
        zipper: LANShareZipper,
        settings: LANShareSettings,
        network: LANShareNetworkAddress,
        webRoot: URL,
        callbacks: Callbacks
    ) {
        self.store = store
        self.sessions = sessions
        self.transfers = transfers
        self.zipper = zipper
        self.settings = settings
        self.network = network
        self.webRoot = webRoot
        self.receiveDirectory = URL(fileURLWithPath: settings.receiveDirectory, isDirectory: true)
        self.temporaryDirectory = self.receiveDirectory.appendingPathComponent(".calmbar-tmp", isDirectory: true)
        self.callbacks = callbacks
        self.allowUpload = settings.allowUpload
        queue.setSpecific(key: queueKey, value: 1)

        var hosts: Set<String> = ["localhost", "127.0.0.1", "::1", network.address.lowercased()]
        for item in LANShareNetworkInterfaces.availableAddresses() {
            hosts.insert(item.address.lowercased())
        }
        self.allowedHosts = hosts
    }

    // MARK: 生命周期

    public func start() {
        guard settings.port >= LANShareLimits.minPort, settings.port <= LANShareLimits.maxPort else {
            callbacks.onFailure(.invalidPort)
            return
        }
        candidates = settings.port == LANShareLimits.defaultPort
            ? Array(LANShareLimits.autoFallbackPorts)
            : [settings.port]
        candidateIndex = 0
        stopped = false
        onQueue { self.attemptNextPort() }
    }

    public func stop() {
        onQueue {
            guard !self.stopped else { return }
            self.stopped = true
            self.cancelWaitingTimer()
            self.listener?.stateUpdateHandler = nil
            self.listener?.cancel()
            self.listener = nil
            let all = Array(self.contexts.values)
            for context in all {
                self.closeContext(context)
            }
            self.contexts.removeAll()
            self.zipper.cancelAll()
            self.transfers.cancelAll()
            self.cleanupTemporaryDirectory()
            self.callbacks.onLog("服务已停止")
        }
    }

    public func updateAllowUpload(_ value: Bool) {
        onQueue { self.allowUpload = value }
    }

    /// 网络切换后刷新允许的 Host 列表，避免重启服务中断传输。
    public func refreshAllowedHosts() {
        onQueue {
            var hosts: Set<String> = ["localhost", "127.0.0.1", "::1", self.network.address.lowercased()]
            for item in LANShareNetworkInterfaces.availableAddresses() {
                hosts.insert(item.address.lowercased())
            }
            self.allowedHosts = hosts
        }
    }

    private func onQueue(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            block()
        } else {
            queue.sync(execute: block)
        }
    }

    private func attemptNextPort() {
        guard !stopped else { return }
        waitingTimer?.cancel()
        waitingTimer = nil
        guard candidateIndex < candidates.count else {
            callbacks.onFailure(.portInUse(candidates.last ?? settings.port))
            return
        }
        let portNumber = candidates[candidateIndex]
        candidateIndex += 1

        guard let port = NWEndpoint.Port(rawValue: UInt16(portNumber)) else {
            attemptNextPort()
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = false
        parameters.includePeerToPeer = false

        do {
            let newListener = try NWListener(using: parameters, on: port)
            listener = newListener
            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.cancelWaitingTimer()
                    self.actualPort = Int(newListener?.port?.rawValue ?? UInt16(portNumber))
                    self.callbacks.onLog("监听就绪 port=\(self.actualPort) addr=\(self.network.prefixText)")
                    self.callbacks.onReady(self.actualPort)
                case .failed(let error):
                    self.cancelWaitingTimer()
                    self.callbacks.onLog("监听失败 port=\(portNumber) error=\(error)")
                    newListener?.stateUpdateHandler = nil
                    newListener?.cancel()
                    if self.listener === newListener { self.listener = nil }
                    if self.candidateIndex < self.candidates.count {
                        self.attemptNextPort()
                    } else {
                        self.callbacks.onFailure(self.mapListenerError(error, port: portNumber))
                    }
                case .waiting(let error):
                    self.callbacks.onLog("监听等待 port=\(portNumber) error=\(error)")
                    self.scheduleWaitingTimeout(listener: newListener, port: portNumber, error: error)
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            newListener.start(queue: queue)
        } catch {
            callbacks.onLog("创建监听失败 port=\(portNumber) error=\(error)")
            if candidateIndex < candidates.count {
                attemptNextPort()
            } else {
                callbacks.onFailure(.portInUse(portNumber))
            }
        }
    }

    /// `.waiting` 常见于端口被占用或网络未就绪；超时后按失败处理并尝试下一个候选端口。
    private func scheduleWaitingTimeout(listener: NWListener?, port: Int, error: NWError) {
        cancelWaitingTimer()
        let work = DispatchWorkItem { [weak self, weak listener] in
            guard let self, let listener, self.listener === listener else { return }
            self.callbacks.onLog("监听等待超时 port=\(port)")
            listener.stateUpdateHandler = nil
            listener.cancel()
            if self.listener === listener { self.listener = nil }
            if self.candidateIndex < self.candidates.count {
                self.attemptNextPort()
            } else {
                self.callbacks.onFailure(self.mapListenerError(error, port: port))
            }
        }
        waitingTimer = work
        queue.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func cancelWaitingTimer() {
        waitingTimer?.cancel()
        waitingTimer = nil
    }

    private func mapListenerError(_ error: NWError, port: Int) -> LANShareError {
        if case .posix(let code) = error {
            if code == .EACCES { return .permissionDenied }
            if code == .EADDRINUSE { return .portInUse(port) }
        }
        return .portInUse(port)
    }

    // MARK: 接入

    private func accept(_ connection: NWConnection) {
        guard !stopped else {
            connection.cancel()
            return
        }
        let peerIP = normalizePeer(peerAddress(connection.endpoint))
        activeConnections += 1
        connectionsPerIP[peerIP, default: 0] += 1
        callbacks.onConnectionCountChanged(activeConnections)

        let context = Context(connection: connection, peerIP: peerIP)
        context.counted = true
        contexts[context.id] = context

        if activeConnections > LANShareLimits.maxConnectionsGlobal {
            context.rejectStatus = 429
        } else if connectionsPerIP[peerIP, default: 0] > LANShareLimits.maxConnectionsPerIP {
            context.rejectStatus = 429
        } else if !isAllowedPeer(peerIP) {
            context.rejectStatus = 403
        }

        connection.stateUpdateHandler = { [weak self, weak context] state in
            guard let self, let context else { return }
            switch state {
            case .ready:
                if let status = context.rejectStatus {
                    self.respondStatus(context, status: status, message: status == 403 ? "不允许从该地址访问" : "连接过多，请稍后再试")
                } else {
                    self.scheduleTimeout(context, delay: LANShareLimits.headerTimeout, isHeader: true)
                    self.receiveNext(context)
                }
            case .failed:
                self.closeContext(context)
            case .cancelled:
                self.closeContext(context)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func peerAddress(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            return "\(host)"
        default:
            return "unknown"
        }
    }

    private func normalizePeer(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let percent = value.firstIndex(of: "%") {
            value = String(value[..<percent])
        }
        return LANShareIP.unmapIPv4(value)
    }

    private func isAllowedPeer(_ peer: String) -> Bool {
        if peer == "127.0.0.1" || peer == "::1" { return true }
        return network.contains(peer)
    }

    // MARK: 接收循环

    private func receiveNext(_ context: Context) {
        guard !context.closed, !context.responseSent else { return }
        context.connection.receive(minimumIncompleteLength: 1, maximumLength: LANShareLimits.receiveChunk) { [weak self, weak context] data, _, isComplete, error in
            guard let self, let context, !context.closed else { return }
            if let data, !data.isEmpty {
                self.process(context, data: data)
            }
            if error != nil {
                self.closeContext(context)
                return
            }
            if isComplete {
                self.handleEndOfStream(context)
                return
            }
            if !context.closed && !context.responseSent {
                self.receiveNext(context)
            }
        }
    }

    private func process(_ context: Context, data: Data) {
        context.lastActivityAt = Date()
        context.parser.consume(data) { [weak self, weak context] event in
            guard let self, let context else { return }
            self.handle(event, context: context)
        }
    }

    private func handle(_ event: LANShareHTTPParseEvent, context: Context) {
        guard !context.closed, !context.responseSent else { return }
        switch event {
        case .head(let head):
            handleHead(context, head: head)
        case .body(let data):
            handleBody(context, data: data)
        case .complete:
            handleComplete(context)
        case .failure(let failure):
            respondStatus(context, status: failure.status, message: message(forStatus: failure.status))
        }
    }

    private func handleEndOfStream(_ context: Context) {
        if context.parser.isComplete {
            closeContext(context)
            return
        }
        if context.parser.receivedByteCount == 0 {
            closeContext(context)
            return
        }
        if !context.responseSent {
            callbacks.onLog("INCOMPLETE conn=\(context.id.prefix(8)) bytes=\(context.parser.receivedByteCount)")
        }
        closeContext(context)
    }

    // MARK: 请求分发

    private func handleHead(_ context: Context, head: LANShareHTTPRequestHead) {
        context.head = head
        context.lastActivityAt = Date()

        guard validateHostAndOrigin(head) else {
            respondStatus(context, status: 403, message: "请求来源不受信任")
            return
        }

        let effectiveMethod = head.method == "HEAD" ? "GET" : head.method
        let route = resolveRoute(method: effectiveMethod, path: head.decodedPath)
        context.route = route

        if route == .notFound || route == .methodNotAllowed {
            respondStatus(context, status: route == .notFound ? 404 : 405, message: message(forStatus: route == .notFound ? 404 : 405))
            return
        }

        if head.method == "POST" || head.method == "DELETE" {
            guard head.value(forHeader: "X-CalmBar-Client") == "web" else {
                respondStatus(context, status: 403, message: "缺少客户端标识")
                return
            }
        }

        switch route {
        case .index:
            respondStatic(context, file: "index.html", contentType: "text/html; charset=utf-8", csp: true)
        case .asset(let name):
            respondStatic(context, file: name, contentType: contentType(forAsset: name), csp: false)
        case .bootstrap:
            respondJSON(context, status: 200, object: [
                "serverName": settings.serverName,
                "passcodeRequired": sessions.isPasscodeEnabled,
                "authMode": sessions.isPasscodeEnabled ? "passcode" : "link"
            ])
        case .createSession:
            guard requireJSON(context, head: head) else { return }
            guard (head.contentLength ?? 0) <= LANShareLimits.maxJSONBytes else {
                respondStatus(context, status: 413, message: message(forStatus: 413))
                return
            }
            context.bodyMode = .json(.session)
            prepareBody(context, head: head)
        case .deleteSession:
            sessions.invalidate(cookieHeader: head.value(forHeader: "Cookie"))
            respond(context, status: 204, body: Data(), contentType: "text/plain; charset=utf-8", setCookies: [sessions.clearCookieHeader()])
        case .state:
            guard let session = requireSession(context, head: head) else { return }
            let permissions = LANSharePermissions.from(settings: settings)
            respondJSON(context, status: 200, object: [
                "serverName": settings.serverName,
                "passcodeRequired": sessions.isPasscodeEnabled,
                "permissions": permissionsJSON(permissions),
                "itemCount": store.currentItems.count,
                "revision": store.revision
            ], setCookies: [sessions.setCookieHeader(token: session.token)])
        case .items:
            guard let session = requireSession(context, head: head) else { return }
            respondItems(context, head: head, session: session)
        case .download:
            guard let session = requireSession(context, head: head) else { return }
            respondDownload(context, head: head, session: session)
        case .upload:
            guard let session = requireSession(context, head: head) else { return }
            guard allowUpload else {
                respondStatus(context, status: 403, message: "分享者已关闭上传")
                return
            }
            context.sessionToken = session.token
            guard let boundary = multipartBoundary(from: head.contentType) else {
                respondStatus(context, status: 415, message: message(forStatus: 415))
                return
            }
            do {
                let parser = try LANShareMultipartParser(boundary: boundary, tempDirectory: temporaryDirectory)
                context.bodyMode = .multipart(parser)
                context.uploadBytes = 0
                context.uploadTaskID = transfers.begin(
                    itemID: nil,
                    fileName: "上传中…",
                    peerIP: context.peerIP,
                    direction: .upload,
                    totalBytes: head.contentLength ?? 0,
                    cancel: { [weak self, weak context] in
                        guard let self, let context else { return }
                        self.queue.async { self.closeContext(context) }
                    }
                )
                prepareBody(context, head: head)
            } catch let error as LANShareError {
                respondStatus(context, status: error.httpStatus, message: error.userMessage)
            } catch {
                respondStatus(context, status: 500, message: "服务出错了，请重试")
            }
        case .text:
            guard let session = requireSession(context, head: head) else { return }
            guard allowUpload else {
                respondStatus(context, status: 403, message: "分享者已关闭上传")
                return
            }
            guard requireJSON(context, head: head) else { return }
            guard (head.contentLength ?? 0) <= LANShareLimits.maxJSONBytes else {
                respondStatus(context, status: 413, message: message(forStatus: 413))
                return
            }
            context.sessionToken = session.token
            context.bodyMode = .json(.text)
            prepareBody(context, head: head)
        case .notFound, .methodNotAllowed:
            break
        }
    }

    private func prepareBody(_ context: Context, head: LANShareHTTPRequestHead) {
        scheduleTimeout(context, delay: LANShareLimits.bodyIdleTimeout, isHeader: false)
        if head.expectContinue {
            let interim = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
            context.connection.send(content: interim, completion: .contentProcessed { _ in })
        }
    }

    private func handleBody(_ context: Context, data: Data) {
        context.lastActivityAt = Date()
        switch context.bodyMode {
        case .json:
            context.jsonBuffer.append(data)
            if context.jsonBuffer.count > LANShareLimits.maxJSONBytes {
                respondStatus(context, status: 413, message: message(forStatus: 413))
            }
        case .multipart(let parser):
            do {
                try parser.consume(data)
                context.uploadBytes += Int64(data.count)
                if let taskID = context.uploadTaskID {
                    if let fileName = parser.currentFileName {
                        transfers.updateFileName(id: taskID, fileName: fileName)
                    }
                    transfers.update(id: taskID, transferredBytes: context.uploadBytes)
                }
            } catch let error as LANShareError {
                respondStatus(context, status: error.httpStatus, message: error.userMessage)
            } catch {
                respondStatus(context, status: 400, message: "请求格式有误")
            }
        case nil:
            break
        }
    }

    private func handleComplete(_ context: Context) {
        context.timer?.cancel()
        guard !context.responseSent else { return }
        switch context.bodyMode {
        case .json(.session):
            finalizeSessionLogin(context)
        case .json(.text):
            finalizeText(context)
        case .multipart(let parser):
            finalizeUpload(context, parser: parser)
        case nil:
            if context.head?.method == "POST" {
                respondStatus(context, status: 400, message: "请求体缺失")
            }
        }
    }

    // MARK: 路由解析

    private func resolveRoute(method: String, path: String) -> Route {
        if path == "/" {
            return method == "GET" ? .index : .methodNotAllowed
        }
        if method == "GET" {
            switch path {
            case "/app.css": return .asset("app.css")
            case "/app.js": return .asset("app.js")
            case "/api/bootstrap": return .bootstrap
            case "/api/state": return .state
            case "/api/items": return .items
            case "/api/download": return .download
            default: return knownPaths.contains(path) ? .methodNotAllowed : .notFound
            }
        }
        if method == "POST" {
            switch path {
            case "/api/session": return .createSession
            case "/api/upload": return .upload
            case "/api/text": return .text
            default: return knownPaths.contains(path) ? .methodNotAllowed : .notFound
            }
        }
        if method == "DELETE", path == "/api/session" {
            return .deleteSession
        }
        return knownPaths.contains(path) ? .methodNotAllowed : .notFound
    }

    private var knownPaths: Set<String> {
        ["/", "/app.css", "/app.js", "/api/bootstrap", "/api/state", "/api/items", "/api/download", "/api/session", "/api/upload", "/api/text"]
    }

    // MARK: 认证与安全

    private func validateHostAndOrigin(_ head: LANShareHTTPRequestHead) -> Bool {
        guard let hostValue = head.hostHeader, let parsed = parseHost(hostValue) else { return false }
        guard allowedHosts.contains(parsed.host.lowercased()) else { return false }
        guard parsed.port == actualPort else { return false }

        if let origin = head.value(forHeader: "Origin") {
            guard let components = URLComponents(string: origin),
                  components.scheme == "http",
                  let originHost = components.host,
                  allowedHosts.contains(originHost.lowercased()),
                  components.port == actualPort else {
                return false
            }
        }
        if head.value(forHeader: "Sec-Fetch-Site") == "cross-site" {
            return false
        }
        return true
    }

    private func parseHost(_ value: String) -> (host: String, port: Int)? {
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            let host = String(value[value.index(after: value.startIndex)..<close])
            let remainder = value[value.index(after: close)...]
            guard remainder.hasPrefix(":"), let port = Int(remainder.dropFirst()) else { return nil }
            return (host, port)
        }
        let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, let port = Int(pieces[1]) else { return nil }
        return (String(pieces[0]), port)
    }

    private func requireSession(_ context: Context, head: LANShareHTTPRequestHead) -> LANShareSession? {
        guard let session = sessions.authenticate(
            cookieHeader: head.value(forHeader: "Cookie"),
            peerIP: context.peerIP
        ) else {
            respondStatus(context, status: 401, message: "链接已失效，请向对方重新获取")
            return nil
        }
        context.sessionToken = session.token
        return session
    }

    private func requireJSON(_ context: Context, head: LANShareHTTPRequestHead) -> Bool {
        guard let contentType = head.contentType, isJSONContentType(contentType) else {
            respondStatus(context, status: 415, message: message(forStatus: 415))
            return false
        }
        return true
    }

    private func isJSONContentType(_ raw: String) -> Bool {
        let parts = raw.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.first?.lowercased() == "application/json" else { return false }
        for parameter in parts.dropFirst() where parameter.lowercased().hasPrefix("charset=") {
            let value = parameter.dropFirst("charset=".count).trimmingCharacters(in: .whitespaces)
            if value.caseInsensitiveCompare("utf-8") != .orderedSame { return false }
        }
        return true
    }

    private func multipartBoundary(from contentType: String?) -> String? {
        guard let contentType else { return nil }
        let parts = contentType.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.first?.lowercased() == "multipart/form-data" else { return nil }
        for parameter in parts.dropFirst() where parameter.lowercased().hasPrefix("boundary=") {
            var value = String(parameter.dropFirst("boundary=".count))
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            guard !value.isEmpty, value.utf8.count <= LANShareLimits.maxBoundaryLength else { return nil }
            return value
        }
        return nil
    }

    // MARK: 会话

    private func finalizeSessionLogin(_ context: Context) {
        guard let object = parseJSONObject(context.jsonBuffer) else {
            respondStatus(context, status: 400, message: "请求格式有误")
            return
        }
        let linkToken = object["linkToken"] as? String
        let passcode = object["passcode"] as? String
        do {
            let token = try sessions.login(
                linkToken: linkToken,
                passcode: passcode,
                peerIP: context.peerIP,
                userAgent: context.head?.value(forHeader: "User-Agent") ?? ""
            )
            let permissions = LANSharePermissions.from(settings: settings)
            respondJSON(context, status: 200, object: [
                "permissions": permissionsJSON(permissions),
                "serverName": settings.serverName
            ], setCookies: [sessions.setCookieHeader(token: token)])
            callbacks.onLog("SESSION ok conn=\(context.id.prefix(8))")
        } catch let error as LANShareError {
            var headers: [String: String] = [:]
            if error == .rateLimited { headers["Retry-After"] = "60" }
            let message = error == .unauthorized ? "认证失败，请检查口令或链接" : error.userMessage
            respondStatus(context, status: error.httpStatus, message: message, extraHeaders: headers)
            callbacks.onLog("SESSION rejected conn=\(context.id.prefix(8))")
        } catch {
            respondStatus(context, status: 500, message: "服务出错了，请重试")
        }
    }

    // MARK: 分享列表

    private func respondItems(_ context: Context, head: LANShareHTTPRequestHead, session: LANShareSession) {
        let query = head.queryItems
        guard let itemID = query["item"], !itemID.isEmpty else {
            let items = store.currentItems.map { itemJSON($0) }
            respondJSON(context, status: 200, object: [
                "items": items,
                "revision": store.revision
            ], setCookies: [sessions.setCookieHeader(token: session.token)])
            return
        }

        guard let item = store.item(id: itemID), item.isValid else {
            respondStatus(context, status: 404, message: "内容已被移除")
            return
        }

        if item.kind == .text {
            var payload = itemJSON(item)
            payload["text"] = item.text ?? ""
            respondJSON(context, status: 200, object: [
                "item": payload,
                "revision": store.revision
            ], setCookies: [sessions.setCookieHeader(token: session.token)])
            return
        }

        guard item.kind == .folder, let folderPath = item.path else {
            respondJSON(context, status: 200, object: [
                "item": itemJSON(item),
                "revision": store.revision
            ], setCookies: [sessions.setCookieHeader(token: session.token)])
            return
        }

        let relativePath = query["path"] ?? ""
        do {
            let entries = try LANSharePathValidator.listDirectory(root: folderPath, relativePath: relativePath)
            let mapped = entries.map { entry -> [String: Any] in
                [
                    "name": entry.name,
                    "isDirectory": entry.isDirectory,
                    "size": entry.size
                ]
            }
            respondJSON(context, status: 200, object: [
                "item": itemJSON(item),
                "path": relativePath,
                "entries": mapped,
                "revision": store.revision
            ], setCookies: [sessions.setCookieHeader(token: session.token)])
        } catch let error as LANShareError {
            respondStatus(context, status: error.httpStatus, message: error.userMessage)
        } catch {
            respondStatus(context, status: 404, message: "内容已被移除")
        }
    }

    // MARK: 下载

    private func respondDownload(_ context: Context, head: LANShareHTTPRequestHead, session: LANShareSession) {
        let query = head.queryItems
        guard let itemID = query["item"], !itemID.isEmpty else {
            respondStatus(context, status: 400, message: "缺少内容标识")
            return
        }
        guard let item = store.item(id: itemID), item.isValid else {
            respondStatus(context, status: 404, message: "内容已被移除")
            return
        }
        let relativePath = query["path"] ?? ""
        let refreshCookie = sessions.setCookieHeader(token: session.token)

        if item.kind == .text {
            let text = item.text ?? ""
            let name = LANSharePathValidator.sanitizeFilename(item.name) + ".txt"
            respond(context,
                    status: 200,
                    body: Data(text.utf8),
                    contentType: "text/plain; charset=utf-8",
                    extraHeaders: ["Content-Disposition": contentDisposition(name: name)],
                    setCookies: [refreshCookie])
            return
        }

        guard let itemPath = item.path else {
            respondStatus(context, status: 404, message: "内容已被移除")
            return
        }

        do {
            let opened = try LANSharePathValidator.open(
                root: item.kind == .folder ? itemPath : URL(fileURLWithPath: itemPath).deletingLastPathComponent().path,
                relativePath: item.kind == .folder ? relativePath : URL(fileURLWithPath: itemPath).lastPathComponent,
                allowDirectory: item.kind == .folder
            )

            if opened.isDirectory {
                opened.close()
                guard beginDownloadSlot(context) else {
                    respondStatus(context, status: 429, message: "同时下载任务过多，请稍后再试")
                    return
                }
                let zipPath = relativePath.isEmpty
                    ? itemPath
                    : URL(fileURLWithPath: itemPath).appendingPathComponent(relativePath).path
                let displayName = URL(fileURLWithPath: zipPath).lastPathComponent
                prepareZip(context, folderPath: zipPath, displayName: displayName, setCookie: refreshCookie)
                return
            }

            guard beginDownloadSlot(context) else {
                opened.close()
                respondStatus(context, status: 429, message: "同时下载任务过多，请稍后再试")
                return
            }
            let fileName: String
            if item.kind == .folder, !relativePath.isEmpty {
                fileName = URL(fileURLWithPath: relativePath).lastPathComponent
            } else {
                fileName = URL(fileURLWithPath: itemPath).lastPathComponent
            }
            streamOpenedFile(context, opened: opened, fileName: fileName, setCookie: refreshCookie)
        } catch let error as LANShareError {
            respondStatus(context, status: error.httpStatus, message: error.userMessage)
        } catch {
            respondStatus(context, status: 404, message: "内容已被移除")
        }
    }

    private func beginDownloadSlot(_ context: Context) -> Bool {
        let current = downloadsPerIP[context.peerIP, default: 0]
        guard current < LANShareLimits.maxDownloadsPerIP else { return false }
        downloadsPerIP[context.peerIP] = current + 1
        context.downloadSlot = true
        return true
    }

    private func streamOpenedFile(_ context: Context, opened: LANShareOpenedFile, fileName: String, setCookie: String?) {
        let isHead = context.head?.method == "HEAD"
        let totalSize = opened.size
        let etag = "\"\(opened.inode)-\(totalSize)\""

        var range: ByteRange?
        var isPartial = false
        if let rawRange = context.head?.value(forHeader: "Range"), totalSize > 0 {
            if let ifRange = context.head?.value(forHeader: "If-Range"), ifRange != etag {
                range = nil
            } else {
                switch parseRange(rawRange, size: totalSize) {
                case .none:
                    range = nil
                case .range(let start, let length):
                    range = ByteRange(start: start, length: length)
                    isPartial = true
                case .invalid:
                    opened.close()
                    respond(context, status: 416, body: Data(), contentType: "text/plain; charset=utf-8",
                            extraHeaders: ["Content-Range": "bytes */\(totalSize)"],
                            setCookies: setCookie.map { [$0] } ?? [])
                    return
                }
            }
        }

        let start = range?.start ?? 0
        let length = range?.length ?? totalSize
        let mime = contentType(forFile: fileName)

        var headers: [String: String] = [
            "Accept-Ranges": "bytes",
            "ETag": etag,
            "Content-Disposition": contentDisposition(name: fileName)
        ]
        if isPartial {
            headers["Content-Range"] = "bytes \(start)-\(start + length - 1)/\(totalSize)"
        }

        let status = isPartial ? 206 : 200
        let headerData = buildResponseHead(
            status: status,
            contentType: mime,
            contentLength: length,
            extraHeaders: headers,
            setCookies: setCookie.map { [$0] } ?? [],
            includeCSP: false
        )

        context.responseSent = true
        context.timer?.cancel()

        if isHead || length == 0 {
            context.connection.send(content: headerData, completion: .contentProcessed { [weak self, weak context] _ in
                guard let self, let context else { return }
                context.fileFD = opened.fd
                self.closeContext(context)
            })
            return
        }

        context.fileFD = opened.fd
        let taskID = transfers.begin(
            itemID: context.head.flatMap { _ in nil },
            fileName: fileName,
            peerIP: context.peerIP,
            direction: .download,
            totalBytes: length,
            cancel: { [weak self, weak context] in
                guard let self, let context else { return }
                self.queue.async { self.closeContext(context) }
            }
        )
        context.downloadTaskID = taskID

        context.connection.send(content: headerData, completion: .contentProcessed { [weak self, weak context] error in
            guard let self, let context else { return }
            if error != nil {
                self.finishDownload(context, state: .failed)
                self.closeContext(context)
                return
            }
            self.sendFileChunk(context, offset: start, remaining: length, sent: 0, total: length)
        })
    }

    private func sendFileChunk(_ context: Context, offset: Int64, remaining: Int64, sent: Int64, total: Int64) {
        guard !context.closed, context.fileFD >= 0 else {
            finishDownload(context, state: .cancelled)
            closeContext(context)
            return
        }
        let chunkSize = Int(min(Int64(LANShareLimits.downloadChunk), remaining))
        guard chunkSize > 0 else {
            finishDownload(context, state: .completed)
            closeContext(context)
            return
        }
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        let readCount = pread(context.fileFD, &buffer, chunkSize, offset)
        if readCount <= 0 {
            finishDownload(context, state: .failed)
            closeContext(context)
            return
        }
        let data = Data(buffer[0..<readCount])
        context.connection.send(content: data, completion: .contentProcessed { [weak self, weak context] error in
            guard let self, let context else { return }
            if error != nil {
                self.finishDownload(context, state: .failed)
                self.closeContext(context)
                return
            }
            let newSent = sent + Int64(readCount)
            if let taskID = context.downloadTaskID {
                self.transfers.update(id: taskID, transferredBytes: newSent, totalBytes: total)
            }
            if newSent >= total {
                self.finishDownload(context, state: .completed)
                self.closeContext(context)
            } else {
                self.sendFileChunk(context, offset: offset + Int64(readCount), remaining: total - newSent, sent: newSent, total: total)
            }
        })
    }

    private func finishDownload(_ context: Context, state: LANShareTransferState) {
        if let taskID = context.downloadTaskID {
            transfers.finish(id: taskID, state: state, errorMessage: state == .failed ? "传输中断" : nil)
            context.downloadTaskID = nil
        }
    }

    private func prepareZip(_ context: Context, folderPath: String, displayName: String, setCookie: String?) {
        zipper.zip(folderPath: folderPath, displayName: displayName, tempDirectory: temporaryDirectory) { [weak self, weak context] result in
            guard let self, let context else { return }
            self.queue.async {
                guard !context.closed, !context.responseSent else { return }
                switch result {
                case .success(let zip):
                    do {
                        let fd = Darwin.open(zip.url.path, O_RDONLY | O_CLOEXEC)
                        guard fd >= 0, let attributes = try? FileManager.default.attributesOfItem(atPath: zip.url.path),
                              let size = (attributes[.size] as? NSNumber)?.int64Value else {
                            if fd >= 0 { _ = Darwin.close(fd) }
                            self.respondStatus(context, status: 500, message: "打包文件夹失败")
                            return
                        }
                        self.streamZip(context, fd: fd, size: size, fileName: zip.fileName, setCookie: setCookie)
                    }
                case .failure(let error):
                    self.respondStatus(context, status: error.httpStatus, message: error.userMessage)
                }
            }
        }
    }

    private func streamZip(_ context: Context, fd: Int32, size: Int64, fileName: String, setCookie: String?) {
        let isHead = context.head?.method == "HEAD"
        let headerData = buildResponseHead(
            status: 200,
            contentType: "application/zip",
            contentLength: size,
            extraHeaders: [
                "Content-Disposition": contentDisposition(name: fileName),
                "Accept-Ranges": "none"
            ],
            setCookies: setCookie.map { [$0] } ?? [],
            includeCSP: false
        )
        context.responseSent = true
        context.timer?.cancel()
        context.fileFD = fd

        if isHead || size == 0 {
            context.connection.send(content: headerData, completion: .contentProcessed { [weak self, weak context] _ in
                guard let self, let context else { return }
                self.closeContext(context)
            })
            return
        }

        let taskID = transfers.begin(
            itemID: nil,
            fileName: fileName,
            peerIP: context.peerIP,
            direction: .download,
            totalBytes: size,
            cancel: { [weak self, weak context] in
                guard let self, let context else { return }
                self.queue.async { self.closeContext(context) }
            }
        )
        context.downloadTaskID = taskID

        context.connection.send(content: headerData, completion: .contentProcessed { [weak self, weak context] error in
            guard let self, let context else { return }
            if error != nil {
                self.finishDownload(context, state: .failed)
                self.closeContext(context)
                return
            }
            self.sendFileChunk(context, offset: 0, remaining: size, sent: 0, total: size)
        })
    }

    private enum RangeResult {
        case none
        case range(Int64, Int64)
        case invalid
    }

    private func parseRange(_ raw: String, size: Int64) -> RangeResult {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value.lowercased().hasPrefix("bytes=") else { return .invalid }
        let spec = value.dropFirst("bytes=".count)
        guard !spec.contains(",") else { return .invalid }
        let pieces = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return .invalid }
        let startText = pieces[0].trimmingCharacters(in: .whitespaces)
        let endText = pieces[1].trimmingCharacters(in: .whitespaces)

        if startText.isEmpty {
            guard let suffix = Int64(endText), suffix > 0 else { return .invalid }
            let start = max(0, size - suffix)
            return .range(start, size - start)
        }
        guard let start = Int64(startText), start >= 0, start < size else { return .invalid }
        if endText.isEmpty {
            return .range(start, size - start)
        }
        guard let end = Int64(endText), end >= start else { return .invalid }
        let clampedEnd = min(end, size - 1)
        return .range(start, clampedEnd - start + 1)
    }

    // MARK: 上传

    private func finalizeUpload(_ context: Context, parser: LANShareMultipartParser) {
        do {
            let result = try parser.finish()
            let destination = try moveUploadedFile(
                tempURL: result.tempURL,
                preferredName: result.filename,
                receiveDirectory: receiveDirectory
            )
            context.tempURL = nil
            context.uploadCommitted = true

            let item = LANShareItem(
                kind: .file,
                name: destination.lastPathComponent,
                path: destination.path,
                size: result.byteCount,
                source: .remote,
                uploaderIP: context.peerIP
            )
            store.add([item])
            callbacks.onItemAdded(item)
            if let taskID = context.uploadTaskID {
                transfers.finish(id: taskID, state: .completed)
                context.uploadTaskID = nil
            }
            callbacks.onLog("UPLOAD done conn=\(context.id.prefix(8)) file=\(item.name) bytes=\(result.byteCount)")
            respondJSON(
                context,
                status: 201,
                object: ["item": itemJSON(item)],
                setCookies: context.sessionToken.map { [sessions.setCookieHeader(token: $0)] } ?? []
            )
        } catch let error as LANShareError {
            cleanupCurrentUpload(context)
            respondStatus(context, status: error.httpStatus, message: error.userMessage)
        } catch {
            cleanupCurrentUpload(context)
            respondStatus(context, status: 500, message: "保存文件失败")
        }
    }

    private func moveUploadedFile(tempURL: URL, preferredName: String, receiveDirectory: URL) throws -> URL {
        let sanitized = LANSharePathValidator.sanitizeFilename(preferredName)
        let baseURL = URL(fileURLWithPath: sanitized)
        let ext = baseURL.pathExtension
        let stem = ext.isEmpty ? sanitized : String(sanitized.dropLast(ext.count + 1))

        for index in 0..<1000 {
            let name: String
            if index == 0 {
                name = sanitized
            } else if ext.isEmpty {
                name = "\(stem) (\(index + 1))"
            } else {
                name = "\(stem) (\(index + 1)).\(ext)"
            }
            let destination = receiveDirectory.appendingPathComponent(name)
            let result = tempURL.withUnsafeFileSystemRepresentation { fromPointer -> Int32 in
                guard let fromPointer else { return -1 }
                return destination.withUnsafeFileSystemRepresentation { toPointer -> Int32 in
                    guard let toPointer else { return -1 }
                    return renamex_np(fromPointer, toPointer, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return destination }
            if errno == EEXIST { continue }
            if errno == ENOSPC { throw LANShareError.diskFull }
            throw LANShareError.internalFailure("保存文件失败")
        }
        throw LANShareError.internalFailure("同名文件过多")
    }

    private func cleanupCurrentUpload(_ context: Context) {
        if let taskID = context.uploadTaskID {
            transfers.finish(id: taskID, state: .failed, errorMessage: "上传失败")
            context.uploadTaskID = nil
        }
        if let tempURL = context.tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            context.tempURL = nil
        }
    }

    // MARK: 文本

    private func finalizeText(_ context: Context) {
        guard let object = parseJSONObject(context.jsonBuffer),
              let text = object["text"] as? String,
              !text.isEmpty,
              text.count <= LANShareLimits.maxTextCharacters else {
            respondStatus(context, status: 400, message: "文本内容不合法")
            return
        }
        let intro = (object["intro"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LANShareItem(
            kind: .text,
            name: LANShareTextTitle.make(from: text),
            text: text,
            intro: intro?.isEmpty == true ? nil : intro,
            source: .remote,
            uploaderIP: context.peerIP
        )
        store.add([item])
        callbacks.onItemAdded(item)
        callbacks.onLog("TEXT done conn=\(context.id.prefix(8)) chars=\(text.count)")
        respondJSON(
            context,
            status: 201,
            object: ["item": itemJSON(item)],
            setCookies: context.sessionToken.map { [sessions.setCookieHeader(token: $0)] } ?? []
        )
    }

    // MARK: 响应

    private func respondStatic(_ context: Context, file: String, contentType: String, csp: Bool) {
        let url = webRoot.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else {
            respondStatus(context, status: 500, message: "页面资源缺失")
            return
        }
        respond(context, status: 200, body: data, contentType: contentType, includeCSP: csp)
    }

    private func respondJSON(
        _ context: Context,
        status: Int,
        object: [String: Any],
        extraHeaders: [String: String] = [:],
        setCookies: [String] = []
    ) {
        respond(
            context,
            status: status,
            body: LANShareJSON.data(object),
            contentType: "application/json; charset=utf-8",
            extraHeaders: extraHeaders,
            setCookies: setCookies
        )
    }

    private func respondStatus(
        _ context: Context,
        status: Int,
        message: String,
        extraHeaders: [String: String] = [:]
    ) {
        let errorCode: String
        switch status {
        case 400: errorCode = "bad_request"
        case 401: errorCode = "unauthorized"
        case 403: errorCode = "forbidden"
        case 404: errorCode = "not_found"
        case 405: errorCode = "method_not_allowed"
        case 408: errorCode = "timeout"
        case 413: errorCode = "too_large"
        case 415: errorCode = "unsupported_media"
        case 416: errorCode = "range_not_satisfiable"
        case 429: errorCode = "rate_limited"
        default: errorCode = "server_error"
        }
        var headers = extraHeaders
        if status == 429 { headers["Retry-After"] = headers["Retry-After"] ?? "60" }
        respondJSON(context, status: status, object: ["error": errorCode, "message": message], extraHeaders: headers)
    }

    private func respond(
        _ context: Context,
        status: Int,
        body: Data,
        contentType: String,
        extraHeaders: [String: String] = [:],
        setCookies: [String] = [],
        includeCSP: Bool = false
    ) {
        guard !context.responseSent else { return }
        context.responseSent = true
        context.timer?.cancel()

        let headerData = buildResponseHead(
            status: status,
            contentType: contentType,
            contentLength: Int64(body.count),
            extraHeaders: extraHeaders,
            setCookies: setCookies,
            includeCSP: includeCSP
        )
        var payload = headerData
        let isHead = context.head?.method == "HEAD"
        if !isHead {
            payload.append(body)
        }
        context.connection.send(content: payload, completion: .contentProcessed { [weak self, weak context] _ in
            guard let self, let context else { return }
            self.closeContext(context)
        })
    }

    private func buildResponseHead(
        status: Int,
        contentType: String,
        contentLength: Int64,
        extraHeaders: [String: String],
        setCookies: [String],
        includeCSP: Bool
    ) -> Data {
        var lines = ["HTTP/1.1 \(status) \(reasonPhrase(status))"]
        var headers = extraHeaders
        headers["Content-Type"] = contentType
        headers["Content-Length"] = String(contentLength)
        headers["Connection"] = "close"
        headers["Cache-Control"] = "no-store"
        headers["X-Content-Type-Options"] = "nosniff"
        headers["X-Frame-Options"] = "DENY"
        headers["Referrer-Policy"] = "no-referrer"
        headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        if includeCSP {
            headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
        }
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            let safeValue = value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            lines.append("\(name): \(safeValue)")
        }
        for cookie in setCookies {
            lines.append("Set-Cookie: \(cookie)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 507: return "Insufficient Storage"
        default: return "Error"
        }
    }

    private func message(forStatus status: Int) -> String {
        switch status {
        case 400: return "请求有误，请刷新页面重试"
        case 401: return "链接已失效，请向对方重新获取"
        case 403: return "没有访问权限"
        case 404: return "内容已被移除"
        case 405: return "请求方式不受支持"
        case 408: return "请求超时，请重试"
        case 413: return "内容超过 20GB 上限"
        case 415: return "请求格式不受支持"
        case 416: return "下载范围无效"
        case 429: return "尝试过于频繁，请稍后再试"
        case 431: return "请求头过大"
        default: return "服务出错了，请重试"
        }
    }

    // MARK: 工具

    private func itemJSON(_ item: LANShareItem) -> [String: Any] {
        var payload: [String: Any] = [
            "id": item.id,
            "kind": item.kind.rawValue,
            "name": item.name,
            "source": item.source.rawValue,
            "addedAt": ISO8601DateFormatter().string(from: item.addedAt),
            "isValid": item.isValid
        ]
        if let size = item.size { payload["size"] = size }
        if let sizeText = item.sizeText { payload["sizeText"] = sizeText }
        if let intro = item.intro { payload["intro"] = intro }
        if let reason = item.invalidReason { payload["invalidReason"] = reason }
        return payload
    }

    private func permissionsJSON(_ permissions: LANSharePermissions) -> [String: Any] {
        [
            "download": permissions.download,
            "upload": permissions.upload,
            "text": permissions.text
        ]
    }

    private func parseJSONObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func contentType(forAsset name: String) -> String {
        switch name {
        case "app.css": return "text/css; charset=utf-8"
        case "app.js": return "application/javascript; charset=utf-8"
        case "index.html": return "text/html; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    private func contentType(forFile name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }

    private func contentDisposition(name: String) -> String {
        let fallback = name
            .unicodeScalars
            .map { scalar -> Character in
                scalar.isASCII && scalar.value >= 0x20 && scalar.value != 0x22 && scalar.value != 0x3B
                    ? Character(scalar)
                    : "_"
            }
        let fallbackString = String(fallback)
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .rfc5987Allowed) ?? fallbackString
        return "attachment; filename=\"\(fallbackString)\"; filename*=UTF-8''\(encoded)"
    }

    // MARK: 超时

    private func scheduleTimeout(_ context: Context, delay: TimeInterval, isHeader: Bool) {
        context.timerGeneration += 1
        let generation = context.timerGeneration
        context.timer?.cancel()
        let item = DispatchWorkItem { [weak self, weak context] in
            guard let self, let context, !context.closed, !context.responseSent,
                  context.timerGeneration == generation else { return }
            let elapsed = Date().timeIntervalSince(context.lastActivityAt)
            let limit = isHeader ? LANShareLimits.headerTimeout : LANShareLimits.bodyIdleTimeout
            if elapsed < limit {
                self.scheduleTimeout(context, delay: max(1, limit - elapsed), isHeader: isHeader)
                return
            }
            self.respondStatus(context, status: 408, message: "请求超时，请重试")
        }
        context.timer = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: 关闭与清理

    private func closeContext(_ context: Context) {
        guard !context.closed else { return }
        context.closed = true
        context.timer?.cancel()
        context.timer = nil
        context.connection.stateUpdateHandler = nil
        context.connection.cancel()

        if context.fileFD >= 0 {
            _ = Darwin.close(context.fileFD)
            context.fileFD = -1
        }
        if let mode = context.bodyMode, case .multipart(let parser) = mode {
            parser.cancel()
        }
        cleanupCurrentUpload(context)
        finishDownload(context, state: .cancelled)

        if context.downloadSlot {
            let current = downloadsPerIP[context.peerIP, default: 0]
            downloadsPerIP[context.peerIP] = max(0, current - 1)
            if downloadsPerIP[context.peerIP] == 0 { downloadsPerIP.removeValue(forKey: context.peerIP) }
            context.downloadSlot = false
        }

        contexts.removeValue(forKey: context.id)
        if context.counted {
            context.counted = false
            activeConnections = max(0, activeConnections - 1)
            let current = connectionsPerIP[context.peerIP, default: 0]
            if current <= 1 {
                connectionsPerIP.removeValue(forKey: context.peerIP)
            } else {
                connectionsPerIP[context.peerIP] = current - 1
            }
            callbacks.onConnectionCountChanged(activeConnections)
        }
    }

    private func cleanupTemporaryDirectory() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}

private extension CharacterSet {
    static let rfc5987Allowed: CharacterSet = {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_`|~")
        allowed.insert(charactersIn: "'")
        return allowed
    }()
}
