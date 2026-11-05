import Foundation
import Network

// MARK: - HTTP 请求 / 响应模型

public struct GatewayHTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: String
    public var version: String
    /// 头部名统一小写
    public var headers: [String: String]
    public var body: Data

    public var isKeepAlive: Bool {
        if let connection = headers["connection"]?.lowercased() {
            if connection.contains("close") { return false }
            if connection.contains("keep-alive") { return true }
        }
        return version == "HTTP/1.1"
    }

    public var remoteDescription: String { headers["host"] ?? "local" }
}

public enum GatewayHTTPStatusText {
    public static func text(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 451: return "Unavailable For Legal Reasons"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Unknown"
        }
    }
}

// MARK: - HTTP/1.1 增量解析

public enum GatewayHTTPParseResult: Sendable {
    case needMore
    case request(GatewayHTTPRequest)
    case failure(status: Int, message: String)
}

public struct GatewayHTTPRequestParser {
    public var maxHeaderBytes = 32 * 1024
    public var maxBodyBytes = 20 * 1024 * 1024

    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    public mutating func nextRequest() -> GatewayHTTPParseResult {
        guard !buffer.isEmpty else { return .needMore }

        guard let headerEnd = Self.findHeaderTerminator(in: buffer) else {
            if buffer.count > maxHeaderBytes {
                return .failure(status: 431, message: "请求头超过 32KB 限制")
            }
            return .needMore
        }

        let headerLength = headerEnd.offset
        guard headerLength <= maxHeaderBytes else {
            return .failure(status: 431, message: "请求头超过 32KB 限制")
        }

        let headerData = buffer.subdata(in: 0..<headerLength)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(status: 400, message: "请求头不是合法 UTF-8")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure(status: 400, message: "缺少请求行")
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            return .failure(status: 400, message: "请求行格式错误")
        }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let version = String(parts[2])
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            return .failure(status: 400, message: "不支持的 HTTP 版本")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(status: 400, message: "请求头格式错误")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return .failure(status: 400, message: "请求头名称为空")
            }
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }
        guard headers.count <= 100 else {
            return .failure(status: 431, message: "请求头数量过多")
        }

        let components = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(components.first ?? "")
        let query = components.count > 1 ? String(components[1]) : ""

        let contentLength = headers["content-length"].flatMap { Int($0) }
        let transferEncoding = headers["transfer-encoding"]?.lowercased()

        if let contentLength, contentLength < 0 {
            return .failure(status: 400, message: "Content-Length 非法")
        }
        if contentLength != nil, transferEncoding != nil {
            return .failure(status: 400, message: "Content-Length 与 Transfer-Encoding 不能同时存在")
        }

        let body: Data
        let consumed: Int

        if let transferEncoding, transferEncoding.contains("chunked") {
            guard let decoded = Self.decodeChunked(buffer, bodyStart: headerEnd.bodyStart) else {
                if buffer.count > maxBodyBytes + maxHeaderBytes {
                    return .failure(status: 413, message: "请求体超过 20MB 限制")
                }
                return .needMore
            }
            body = decoded.body
            consumed = headerEnd.bodyStart + decoded.consumed
        } else if let contentLength {
            guard contentLength <= maxBodyBytes else {
                return .failure(status: 413, message: "请求体超过 20MB 限制")
            }
            guard buffer.count >= headerEnd.bodyStart + contentLength else {
                return .needMore
            }
            body = buffer.subdata(in: headerEnd.bodyStart..<(headerEnd.bodyStart + contentLength))
            consumed = headerEnd.bodyStart + contentLength
        } else {
            body = Data()
            consumed = headerEnd.bodyStart
        }

        buffer.removeSubrange(0..<consumed)
        return .request(GatewayHTTPRequest(
            method: method,
            path: path,
            query: query,
            version: version,
            headers: headers,
            body: body
        ))
    }

    // MARK: 内部

    private struct HeaderTerminator {
        let offset: Int
        let bodyStart: Int
    }

    private static func findHeaderTerminator(in data: Data) -> HeaderTerminator? {
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            return HeaderTerminator(offset: range.lowerBound, bodyStart: range.upperBound)
        }
        if let range = data.range(of: Data("\n\n".utf8)) {
            return HeaderTerminator(offset: range.lowerBound, bodyStart: range.upperBound)
        }
        return nil
    }

    private static func decodeChunked(_ data: Data, bodyStart: Int) -> (body: Data, consumed: Int)? {
        var cursor = bodyStart
        var body = Data()

        while true {
            guard let lineEnd = findCRLF(data, from: cursor) else { return nil }
            let sizeLine = String(decoding: data[cursor..<lineEnd], as: UTF8.self)
            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? sizeLine
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else {
                return nil
            }
            let afterLine = lineEnd + 2
            if size == 0 {
                // 0\r\n 之后是可选 trailer，以空行结束
                if afterLine + 1 < data.count, data[afterLine] == 0x0D, data[afterLine + 1] == 0x0A {
                    return (body, afterLine + 2 - bodyStart)
                }
                if let trailerEnd = data.range(of: Data("\r\n\r\n".utf8), in: afterLine..<data.count) {
                    return (body, trailerEnd.upperBound - bodyStart)
                }
                return nil
            }
            guard size <= 20 * 1024 * 1024 else { return nil }
            guard data.count >= afterLine + size + 2 else { return nil }
            body.append(data.subdata(in: afterLine..<(afterLine + size)))
            let terminator = afterLine + size
            guard data[terminator] == 0x0D, data[terminator + 1] == 0x0A else { return nil }
            cursor = terminator + 2
        }
    }

    private static func findCRLF(_ data: Data, from start: Int) -> Int? {
        guard start < data.count else { return nil }
        var index = start
        while index + 1 < data.count {
            if data[index] == 0x0D, data[index + 1] == 0x0A { return index }
            index += 1
        }
        return nil
    }
}

// MARK: - 单个连接

public final class GatewayHTTPConnection: @unchecked Sendable {
    public let id = UUID()
    public var onClosed: (@Sendable (GatewayHTTPConnection) -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var parser = GatewayHTTPRequestParser()
    private var isProcessing = false
    private var isClosed = false
    private var currentKeepAlive = true
    private var requestCount = 0
    private var idleTimer: DispatchSourceTimer?
    private let onRequest: @Sendable (GatewayHTTPRequest, GatewayHTTPConnection) async -> Void

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        onRequest: @escaping @Sendable (GatewayHTTPRequest, GatewayHTTPConnection) async -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.onRequest = onRequest
    }

    public var isClosedState: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.markClosed()
            default:
                break
            }
        }
        connection.start(queue: queue)
        readNext()
    }

    public func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()
        idleTimer?.cancel()
        idleTimer = nil
        connection.cancel()
        onClosed?(self)
    }

    // MARK: 非流式响应

    public func respond(status: Int, headers: [GatewayHeader], body: Data) async {
        var finalHeaders = headers.filter { !Self.isHopByHop($0.name) }
        if !finalHeaders.contains(where: { $0.name.lowercased() == "content-type" }) {
            finalHeaders.append(GatewayHeader(name: "Content-Type", value: "application/json; charset=utf-8"))
        }
        finalHeaders.append(GatewayHeader(name: "Content-Length", value: String(body.count)))
        finalHeaders.append(GatewayHeader(
            name: "Connection",
            value: currentKeepAlive ? "keep-alive" : "close"
        ))

        var head = "HTTP/1.1 \(status) \(GatewayHTTPStatusText.text(for: status))\r\n"
        for header in finalHeaders {
            head += "\(header.name): \(header.value)\r\n"
        }
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(body)
        let success = await send(payload)

        if !success || !currentKeepAlive {
            close()
            return
        }
        finishResponseForKeepAlive()
    }

    // MARK: 流式响应

    public func startStream(status: Int, headers: [GatewayHeader]) async -> Bool {
        var finalHeaders = headers.filter { !Self.isHopByHop($0.name) }
        finalHeaders.append(GatewayHeader(name: "Transfer-Encoding", value: "chunked"))
        finalHeaders.append(GatewayHeader(name: "Cache-Control", value: "no-cache"))
        finalHeaders.append(GatewayHeader(name: "Connection", value: "close"))

        var head = "HTTP/1.1 \(status) \(GatewayHTTPStatusText.text(for: status))\r\n"
        for header in finalHeaders {
            head += "\(header.name): \(header.value)\r\n"
        }
        head += "\r\n"
        return await send(Data(head.utf8))
    }

    @discardableResult
    public func writeStreamChunk(_ data: Data) async -> Bool {
        guard !data.isEmpty else { return true }
        var payload = Data("\(String(data.count, radix: 16))\r\n".utf8)
        payload.append(data)
        payload.append(Data("\r\n".utf8))
        return await send(payload)
    }

    public func endStream() async {
        _ = await send(Data("0\r\n\r\n".utf8))
        close()
    }

    // MARK: 读取循环

    private func readNext() {
        guard !isClosedState, !isProcessing else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.parser.append(data)
                self.processBuffer()
                return
            }
            if let error {
                self.markClosed(error: error)
                return
            }
            if isComplete {
                self.markClosed()
                return
            }
            self.readNext()
        }
    }

    private func processBuffer() {
        guard !isClosedState, !isProcessing else { return }
        let result = parser.nextRequest()
        switch result {
        case .needMore:
            cancelIdleTimer()
            readNext()
        case .failure(let status, let message):
            currentKeepAlive = false
            let body = GatewayErrorPayload.json(code: "invalid_request", type: "invalid_request_error", message: message)
            Task { [weak self] in
                await self?.respond(status: status, headers: [], body: body)
            }
        case .request(let request):
            requestCount += 1
            if requestCount > 1000 {
                currentKeepAlive = false
            }
            currentKeepAlive = request.isKeepAlive && requestCount <= 1000
            isProcessing = true
            cancelIdleTimer()
            Task { [weak self] in
                guard let self else { return }
                await self.onRequest(request, self)
            }
        }
    }

    private func finishResponseForKeepAlive() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.isProcessing = false
            let keepAlive = self.currentKeepAlive
            let overLimit = self.requestCount >= 1000
            self.lock.unlock()
            if !keepAlive || overLimit {
                self.close()
                return
            }
            self.scheduleIdleTimer()
            self.processBuffer()
        }
    }

    private func scheduleIdleTimer() {
        cancelIdleTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: .never)
        timer.setEventHandler { [weak self] in
            self?.close()
        }
        timer.resume()
        idleTimer = timer
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    private func markClosed(error: Error? = nil) {
        lock.lock()
        let alreadyClosed = isClosed
        isClosed = true
        lock.unlock()
        guard !alreadyClosed else { return }
        cancelIdleTimer()
        connection.cancel()
        onClosed?(self)
    }

    private func send(_ data: Data) async -> Bool {
        guard !isClosedState else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.markClosed(error: error)
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            })
        }
    }

    private static func isHopByHop(_ name: String) -> Bool {
        switch name.lowercased() {
        case "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
             "te", "trailer", "transfer-encoding", "upgrade", "content-length", "host":
            return true
        default:
            return false
        }
    }
}

// MARK: - 监听器

public enum GatewayHTTPServerError: LocalizedError {
    case invalidPort
    case listenerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPort: return "端口无效"
        case .listenerFailed(let message): return "监听失败：\(message)"
        }
    }
}

public final class GatewayHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.calmbar.aigateway.server")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var connections: [UUID: GatewayHTTPConnection] = [:]
    private var onRequestHandler: (@Sendable (GatewayHTTPRequest, GatewayHTTPConnection) async -> Void)?

    public var onListenerFailure: (@Sendable (String) -> Void)?
    public var onReady: (@Sendable (UInt16) -> Void)?

    public init() {}

    public func setRequestHandler(_ handler: @escaping @Sendable (GatewayHTTPRequest, GatewayHTTPConnection) async -> Void) {
        onRequestHandler = handler
    }

    public func start(port: Int) throws {
        guard (1...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw GatewayHTTPServerError.invalidPort
        }
        stop()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw GatewayHTTPServerError.listenerFailed(error.localizedDescription)
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady?(nwPort.rawValue)
            case .failed(let error):
                self.onListenerFailure?(error.localizedDescription)
                self.stop()
            case .cancelled:
                break
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self, let handler = self.onRequestHandler else {
                connection.cancel()
                return
            }
            let wrapped = GatewayHTTPConnection(connection: connection, queue: self.queue, onRequest: handler)
            wrapped.onClosed = { [weak self] closed in
                guard let self else { return }
                self.stateLock.lock()
                self.connections.removeValue(forKey: closed.id)
                self.stateLock.unlock()
            }
            self.stateLock.lock()
            self.connections[wrapped.id] = wrapped
            self.stateLock.unlock()
            wrapped.start()
        }

        stateLock.lock()
        self.listener = listener
        stateLock.unlock()
        listener.start(queue: queue)
    }

    public func stop() {
        stateLock.lock()
        let listener = self.listener
        let connections = Array(self.connections.values)
        self.listener = nil
        self.connections.removeAll()
        stateLock.unlock()

        listener?.cancel()
        for connection in connections {
            connection.close()
        }
    }

    public var connectionCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return connections.count
    }
}
