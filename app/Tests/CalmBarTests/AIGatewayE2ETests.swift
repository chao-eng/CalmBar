import Network
import XCTest
@testable import CalmBar

// MARK: - 端到端联调：本地网关 → 模拟上游（SSE 透传 + 指标落库）

final class AIGatewayE2ETests: XCTestCase {
    func testStreamingPassthroughRecordsMetrics() async throws {
        GatewayCooldownStore.shared.clearAll()
        GatewayResponseChannelMap.shared.clearAll()

        let upstream = try MockUpstreamServer(chunks: [
            "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\n",
            "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n",
            "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}\n\n"
        ])
        let upstreamPort = try await upstream.start()
        defer { upstream.stop() }

        let database = GatewayDatabase(path: NSTemporaryDirectory() + "aigateway-e2e-\(UUID().uuidString).db")
        let channel = GatewayChannelRuntime(
            id: "mock",
            name: "模拟渠道",
            baseURL: "http://127.0.0.1:\(upstreamPort)/v1",
            model: "gpt-4o-mini"
        )
        let snapshot = GatewaySnapshot(
            channels: ["mock": channel],
            modelRoutes: ["chat": [channel.id]],
            availableModels: ["chat"]
        )

        let server = GatewayHTTPServer()
        let recorder = RecordBox()
        let recordExpectation = expectation(description: "记录落库")
        let processor = GatewayRequestProcessor(snapshot: snapshot)
        server.setRequestHandler { request, connection in
            if let record = await processor.run(request: request, connection: connection) {
                try? await database.insert(record)
                await recorder.store(record)
                recordExpectation.fulfill()
            }
        }

        let gatewayPort = Int.random(in: 20_000...45_000)
        let readyExpectation = expectation(description: "网关就绪")
        server.onReady = { _ in readyExpectation.fulfill() }
        server.onListenerFailure = { message in
            XCTFail("网关监听失败：\(message)")
            readyExpectation.fulfill()
        }
        try server.start(port: gatewayPort)
        defer { server.stop() }
        await fulfillment(of: [readyExpectation], timeout: 5)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(gatewayPort)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            #"{"model":"chat","stream":true,"messages":[{"role":"user","content":"hello"}]}"#.utf8
        )
        request.timeoutInterval = 10

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream"), true)

        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"content\":\"hello\""))
        XCTAssertTrue(text.contains("\"content\":\" world\""))

        await fulfillment(of: [recordExpectation], timeout: 5)

        let recordedValue = await recorder.value()
        let record = try XCTUnwrap(recordedValue)
        XCTAssertEqual(record.status, .success)
        XCTAssertEqual(record.requestedModel, "chat")
        XCTAssertEqual(record.upstreamModel, "gpt-4o-mini")
        XCTAssertEqual(record.channelName, "模拟渠道")
        XCTAssertEqual(record.inputTokens, 5)
        XCTAssertEqual(record.outputTokens, 2)
        XCTAssertNotNil(record.ttftMs)
        XCTAssertNotNil(record.outputTPS)
        XCTAssertTrue((record.outputTPS ?? 0) > 0)

        let result = try await database.series(granularity: .minute)
        XCTAssertEqual(result.series.count, 1)
        XCTAssertEqual(result.series.first?.channelName, "模拟渠道")
        XCTAssertEqual(result.points.count, 1)

        let stored = try await database.recent(limit: 10)
        XCTAssertEqual(stored.count, 1)
    }

    func testAuthRejectionWhenServerKeyConfigured() async throws {
        let database = GatewayDatabase(path: NSTemporaryDirectory() + "aigateway-e2e-\(UUID().uuidString).db")
        let channel = GatewayChannelRuntime(
            id: "mock",
            name: "模拟渠道",
            baseURL: "http://127.0.0.1:1/v1",
            model: "m"
        )
        let snapshot = GatewaySnapshot(
            port: 0,
            serverKey: "secret-key-123456",
            channels: ["mock": channel],
            modelRoutes: ["chat": [channel.id]],
            availableModels: ["chat"]
        )

        let server = GatewayHTTPServer()
        let recordExpectation = expectation(description: "拒绝记录")
        let processor = GatewayRequestProcessor(snapshot: snapshot)
        server.setRequestHandler { request, connection in
            if let record = await processor.run(request: request, connection: connection) {
                try? await database.insert(record)
                recordExpectation.fulfill()
            }
        }

        let gatewayPort = Int.random(in: 20_000...45_000)
        let readyExpectation = expectation(description: "网关就绪")
        server.onReady = { _ in readyExpectation.fulfill() }
        try server.start(port: gatewayPort)
        defer { server.stop() }
        await fulfillment(of: [readyExpectation], timeout: 5)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(gatewayPort)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"chat","messages":[]}"#.utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 401)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("invalid_api_key"))

        await fulfillment(of: [recordExpectation], timeout: 5)
        let stored = try await database.recent(limit: 10)
        XCTAssertEqual(stored.first?.status, .rejected)
        XCTAssertEqual(stored.first?.httpStatus, 401)
    }

    /// 客户端省略 /v1 前缀调用，且渠道 Base 自带版本段时，上游应收到 /api/v3/chat/completions
    func testPathWithoutV1HitsVersionedUpstreamBase() async throws {
        GatewayCooldownStore.shared.clearAll()
        GatewayResponseChannelMap.shared.clearAll()

        let upstream = try MockUpstreamServer(chunks: [
            "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\n"
        ])
        let upstreamPort = try await upstream.start()
        defer { upstream.stop() }

        let channel = GatewayChannelRuntime(
            id: "mock",
            name: "模拟渠道",
            baseURL: "http://127.0.0.1:\(upstreamPort)/api/v3",
            model: "doubao-seed-2-1-pro-260628"
        )
        let snapshot = GatewaySnapshot(
            channels: ["mock": channel],
            modelRoutes: ["chat": [channel.id]],
            availableModels: ["chat"]
        )

        let server = GatewayHTTPServer()
        let processor = GatewayRequestProcessor(snapshot: snapshot)
        let recordExpectation = expectation(description: "记录落库")
        server.setRequestHandler { request, connection in
            if await processor.run(request: request, connection: connection) != nil {
                recordExpectation.fulfill()
            }
        }

        let gatewayPort = Int.random(in: 20_000...45_000)
        let readyExpectation = expectation(description: "网关就绪")
        server.onReady = { _ in readyExpectation.fulfill() }
        try server.start(port: gatewayPort)
        defer { server.stop() }
        await fulfillment(of: [readyExpectation], timeout: 5)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(gatewayPort)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"chat","stream":true,"messages":[{"role":"user","content":"hello"}]}"#.utf8)
        request.timeoutInterval = 10

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, String(decoding: data, as: UTF8.self))
        XCTAssertEqual(upstream.receivedPath, "/api/v3/chat/completions")
        await fulfillment(of: [recordExpectation], timeout: 5)
    }

    /// 别名在渠道下显式绑定的上游模型应写入转发请求体
    func testAliasBindingRewritesUpstreamModel() async throws {
        GatewayCooldownStore.shared.clearAll()
        GatewayResponseChannelMap.shared.clearAll()

        let upstream = try MockUpstreamServer(chunks: [
            "data: {\"model\":\"m-large\",\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\n"
        ])
        let upstreamPort = try await upstream.start()
        defer { upstream.stop() }

        let channel = GatewayChannelRuntime(
            id: "mock",
            name: "多模型渠道",
            baseURL: "http://127.0.0.1:\(upstreamPort)/v1",
            model: "m-small",
            models: ["m-small", "m-large"]
        )
        let snapshot = GatewaySnapshot(
            channels: ["mock": channel],
            modelRoutes: ["chat": ["mock"]],
            modelBindings: ["chat": ["mock": "m-large"]],
            availableModels: ["chat"]
        )

        let server = GatewayHTTPServer()
        let recordExpectation = expectation(description: "记录落库")
        let processor = GatewayRequestProcessor(snapshot: snapshot)
        server.setRequestHandler { request, connection in
            if await processor.run(request: request, connection: connection) != nil {
                recordExpectation.fulfill()
            }
        }

        let gatewayPort = Int.random(in: 20_000...45_000)
        let readyExpectation = expectation(description: "网关就绪")
        server.onReady = { _ in readyExpectation.fulfill() }
        try server.start(port: gatewayPort)
        defer { server.stop() }
        await fulfillment(of: [readyExpectation], timeout: 5)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(gatewayPort)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"chat","stream":true,"messages":[{"role":"user","content":"hi"}]}"#.utf8)
        request.timeoutInterval = 10

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, String(decoding: data, as: UTF8.self))
        await fulfillment(of: [recordExpectation], timeout: 5)

        let body = try XCTUnwrap(upstream.receivedBody)
        XCTAssertTrue(body.contains("\"model\":\"m-large\""), body)
    }

    /// 渠道锁定 Responses 协议时，Chat 入口应直接返回 400 并提示正确入口
    func testLockedProtocolRejectsMismatchedEndpoint() async throws {
        let channel = GatewayChannelRuntime(
            id: "mock",
            name: "模拟渠道",
            baseURL: "http://127.0.0.1:1/v1",
            model: "m",
            protocolMode: .responses
        )
        let snapshot = GatewaySnapshot(
            channels: ["mock": channel],
            modelRoutes: ["chat": ["mock"]],
            availableModels: ["chat"]
        )

        let server = GatewayHTTPServer()
        let processor = GatewayRequestProcessor(snapshot: snapshot)
        let recorder = RecordBox()
        let recordExpectation = expectation(description: "拒绝记录")
        server.setRequestHandler { request, connection in
            if let record = await processor.run(request: request, connection: connection) {
                await recorder.store(record)
                recordExpectation.fulfill()
            }
        }

        let gatewayPort = Int.random(in: 20_000...45_000)
        let readyExpectation = expectation(description: "网关就绪")
        server.onReady = { _ in readyExpectation.fulfill() }
        try server.start(port: gatewayPort)
        defer { server.stop() }
        await fulfillment(of: [readyExpectation], timeout: 5)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(gatewayPort)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"chat","stream":false,"messages":[{"role":"user","content":"hi"}]}"#.utf8)
        request.timeoutInterval = 10

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 400)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("protocol_mismatch"))
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (payload?["error"] as? [String: Any])?["message"] as? String ?? ""
        XCTAssertTrue(message.contains("/v1/responses"), message)

        await fulfillment(of: [recordExpectation], timeout: 5)
        let record = await recorder.value()
        XCTAssertEqual(record?.status, .rejected)
        XCTAssertEqual(record?.httpStatus, 400)
    }
}

// MARK: - 测试辅助

private actor RecordBox {
    private var record: GatewayRequestRecord?

    func store(_ value: GatewayRequestRecord) {
        record = value
    }

    func value() -> GatewayRequestRecord? {
        record
    }
}

/// 保证续体只被恢复一次
private final class ResumeOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}

/// 极简 HTTP/1.1 上游：读掉请求头后按块回写 SSE，最终以 close 结束响应
private final class MockUpstreamServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.calmbar.tests.mock-upstream")
    private let chunks: [String]
    private let pathLock = NSLock()
    private var path: String?
    private var bodyText: String?

    /// 上游实际收到的请求路径（用于校验 Base URL 拼接结果）
    var receivedPath: String? {
        pathLock.lock()
        defer { pathLock.unlock() }
        return path
    }

    /// 上游实际收到的请求体（用于校验转发的上游模型）
    var receivedBody: String? {
        pathLock.lock()
        defer { pathLock.unlock() }
        return bodyText
    }

    init(chunks: [String]) throws {
        self.chunks = chunks
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        let stateBox = ResumeOnceBox()
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard stateBox.claim() else { return }
                    if let port = self?.listener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "MockUpstreamServer",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "未分配端口"]
                        ))
                    }
                case .failed(let error):
                    guard stateBox.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                connection.start(queue: self.queue)
                self.receiveHeaders(on: connection, buffer: Data())
            }
            listener.start(queue: queue)
        }
        return port
    }

    func stop() {
        listener.cancel()
    }

    private func receiveHeaders(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            let separator = Data("\r\n\r\n".utf8)
            guard let headerRange = accumulated.range(of: separator) else {
                if error == nil, !isComplete {
                    self.receiveHeaders(on: connection, buffer: accumulated)
                } else {
                    connection.cancel()
                }
                return
            }

            self.recordPath(from: accumulated)
            let headerText = String(decoding: accumulated[..<headerRange.lowerBound], as: UTF8.self)
            let expectedLength = self.contentLength(from: headerText)
            let bodyStart = headerRange.upperBound
            let available = accumulated.count - bodyStart

            if available >= expectedLength {
                self.recordBody(from: accumulated.subdata(in: bodyStart..<(bodyStart + expectedLength)))
                self.sendResponse(on: connection)
            } else if error == nil, !isComplete {
                self.receiveHeaders(on: connection, buffer: accumulated)
            } else {
                self.recordBody(from: accumulated.subdata(in: bodyStart..<accumulated.endIndex))
                self.sendResponse(on: connection)
            }
        }
    }

    private func contentLength(from headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    /// 从请求行里取出上游路径，供测试校验 Base URL 拼接
    private func recordPath(from data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first else { return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return }
        pathLock.lock()
        path = String(parts[1])
        pathLock.unlock()
    }

    private func recordBody(from data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        pathLock.lock()
        bodyText = text
        pathLock.unlock()
    }

    private func sendResponse(on connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.sendChunk(at: 0, on: connection) }
        })
    }

    private func sendChunk(at index: Int, on connection: NWConnection) {
        guard index < chunks.count else {
            connection.send(
                content: Data("data: [DONE]\n\n".utf8),
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() }
            )
            return
        }
        connection.send(content: Data(chunks[index].utf8), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.queue.asyncAfter(deadline: .now() + 0.03) {
                self.sendChunk(at: index + 1, on: connection)
            }
        })
    }
}
