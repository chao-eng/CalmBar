import Foundation
import Testing
@testable import CalmBar

// MARK: - 服务端集成测试（本地回环）

@Suite("LANShare HTTP Integration", .serialized)
struct LANShareHTTPIntegrationTests {
    private final class PortWaiter: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var storedPort = 0
        private var finished = false

        func resolve(port: Int) {
            lock.lock()
            if !finished {
                storedPort = port
                finished = true
            }
            lock.unlock()
            semaphore.signal()
        }

        var port: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedPort
        }

        func wait(timeout: TimeInterval) -> Bool {
            semaphore.wait(timeout: .now() + timeout) == .success
        }
    }

    private struct Harness {
        let server: LANShareHTTPServer
        let sessions: LANShareSessionManager
        let store: LANShareStore
        let port: Int
        let root: URL
        let receiveDirectory: URL
        let session: URLSession
    }

    private func makeHarness() async throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareIntegration-\(UUID().uuidString)", isDirectory: true)
        let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
        let receiveDirectory = root.appendingPathComponent("receive", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiveDirectory, withIntermediateDirectories: true)

        let store = LANShareStore(stateDirectory: stateDirectory)
        var settings = LANShareSettings.default
        settings.port = Int.random(in: 49200...59000)
        settings.receiveDirectory = receiveDirectory.path
        settings.passcodeEnabled = false
        settings.allowUpload = true
        store.updateSettings(settings)

        let passcodeStore = LANSharePasscodeStore(stateDirectory: stateDirectory)
        let sessions = LANShareSessionManager(passcodeStore: passcodeStore, passcodeEnabled: false)
        let transfers = LANShareTransferManager()
        let zipper = LANShareZipper()
        let network = LANShareNetworkAddress(
            interfaceName: "lo0",
            address: "127.0.0.1",
            prefixLength: 8,
            family: .ipv4,
            isLinkLocal: false
        )
        let webRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/LANShareWeb", isDirectory: true)

        let waiter = PortWaiter()
        let callbacks = LANShareHTTPServer.Callbacks(
            onReady: { port in waiter.resolve(port: port) },
            onFailure: { _ in waiter.resolve(port: 0) },
            onConnectionCountChanged: { _ in },
            onItemAdded: { _ in },
            onLog: { _ in }
        )
        let server = LANShareHTTPServer(
            store: store,
            sessions: sessions,
            transfers: transfers,
            zipper: zipper,
            settings: settings,
            network: network,
            webRoot: webRoot,
            callbacks: callbacks
        )
        server.start()

        let ready = await Task.detached { waiter.wait(timeout: 5) }.value
        #expect(ready)
        #expect(waiter.port > 0)

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)

        return Harness(
            server: server,
            sessions: sessions,
            store: store,
            port: waiter.port,
            root: root,
            receiveDirectory: receiveDirectory,
            session: session
        )
    }

    private func request(
        _ harness: Harness,
        _ path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(harness.port)\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await harness.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    @Test("bootstrap 与静态页面可直接访问")
    func servesBootstrapAndIndex() async throws {
        let harness = try await makeHarness()
        defer {
            harness.server.stop()
            try? FileManager.default.removeItem(at: harness.root)
        }

        let (bootstrapData, bootstrapResponse) = try await request(harness, "/api/bootstrap")
        #expect(bootstrapResponse.statusCode == 200)
        let bootstrapJSON = json(bootstrapData)
        #expect(bootstrapJSON["authMode"] as? String == "link")
        #expect(bootstrapJSON["passcodeRequired"] as? Bool == false)
        #expect((bootstrapJSON["serverName"] as? String)?.isEmpty == false)

        let (indexData, indexResponse) = try await request(harness, "/")
        #expect(indexResponse.statusCode == 200)
        let html = String(data: indexData, encoding: .utf8) ?? ""
        #expect(html.contains("CalmBar 局域网互传"))

        let (jsData, jsResponse) = try await request(harness, "/app.js")
        #expect(jsResponse.statusCode == 200)
        #expect(String(data: jsData, encoding: .utf8)?.contains("X-CalmBar-Client") == true)
    }

    @Test("缺少 CSRF 头的写请求被拒绝")
    func rejectsMissingCSRFHeader() async throws {
        let harness = try await makeHarness()
        defer {
            harness.server.stop()
            try? FileManager.default.removeItem(at: harness.root)
        }

        let (_, response) = try await request(
            harness,
            "/api/session",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: Data("{\"linkToken\":\"x\"}".utf8)
        )
        #expect(response.statusCode == 403)
    }

    @Test("错误令牌返回 401，正确令牌建立会话并可访问状态接口")
    func authenticatesSession() async throws {
        let harness = try await makeHarness()
        defer {
            harness.server.stop()
            try? FileManager.default.removeItem(at: harness.root)
        }

        let (_, wrong) = try await request(
            harness,
            "/api/session",
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "X-CalmBar-Client": "web"
            ],
            body: Data("{\"linkToken\":\"wrong\"}".utf8)
        )
        #expect(wrong.statusCode == 401)

        // 通过 bootstrap 拿到模式后，直接从会话管理器读取现令牌
        let token = try #require(harness.sessions.currentLinkToken.isEmpty ? nil : harness.sessions.currentLinkToken)
        let body = try JSONSerialization.data(withJSONObject: ["linkToken": token])
        let (loginData, loginResponse) = try await request(
            harness,
            "/api/session",
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "X-CalmBar-Client": "web"
            ],
            body: body
        )
        #expect(loginResponse.statusCode == 200)
        #expect(json(loginData)["permissions"] != nil)

        let setCookie = try #require(loginResponse.value(forHTTPHeaderField: "Set-Cookie"))
        #expect(setCookie.contains("calmbar_session="))
        let cookie = setCookie.split(separator: ";").first.map(String.init) ?? setCookie

        let (stateData, stateResponse) = try await request(
            harness,
            "/api/state",
            headers: ["Cookie": cookie]
        )
        #expect(stateResponse.statusCode == 200)
        #expect(json(stateData)["permissions"] != nil)

        let (_, unauthState) = try await request(harness, "/api/state")
        #expect(unauthState.statusCode == 401)
    }

    @Test("带会话的上传请求会把文件写入接收目录")
    func acceptsUpload() async throws {
        let harness = try await makeHarness()
        defer {
            harness.server.stop()
            try? FileManager.default.removeItem(at: harness.root)
        }

        let cookie = try await login(harness)
        let boundary = "----CalmBarIntegration"
        var payload = Data()
        payload.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"note.txt\"\r\nContent-Type: text/plain\r\n\r\n".utf8))
        payload.append(Data("integration".utf8))
        payload.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (_, response) = try await request(
            harness,
            "/api/upload",
            method: "POST",
            headers: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)",
                "Cookie": cookie,
                "X-CalmBar-Client": "web"
            ],
            body: payload
        )
        #expect(response.statusCode == 201)

        let file = harness.receiveDirectory.appendingPathComponent("note.txt")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect((try? String(contentsOf: file, encoding: .utf8)) == "integration")
    }

    @Test("下载本地文件条目返回文件内容")
    func downloadsLocalFileItem() async throws {
        let harness = try await makeHarness()
        defer {
            harness.server.stop()
            try? FileManager.default.removeItem(at: harness.root)
        }
        let cookie = try await login(harness)

        // 使用与真实场景一致的复杂文件名（中文、方括号、&、括号）。
        let name = "【接口文档】千机系统新商户线索导入&更新(1).pdf"
        let fileURL = harness.root.appendingPathComponent(name)
        let payload = Data("pdf-bytes".utf8)
        try payload.write(to: fileURL)

        let item = LANShareItem(kind: .file, name: name, path: fileURL.path, size: Int64(payload.count))
        _ = harness.store.add([item])
        #expect(harness.store.item(id: item.id) != nil)

        let (data, response) = try await request(
            harness,
            "/api/download?item=\(item.id)",
            headers: ["Cookie": cookie]
        )
        #expect(response.statusCode == 200)
        #expect(data == payload)
    }

    @Test("多客户端会话互不影响：B 上传后 A 仍可读取列表")
    func keepsOtherSessionsAlive() async throws {
        let harness = try await makeHarness()
        defer {
            harness.server.stop()
            try? FileManager.default.removeItem(at: harness.root)
        }

        let cookieA = try await login(harness)
        let cookieB = try await login(harness)
        #expect(harness.sessions.activeSessionCount == 2)

        let boundary = "----CalmBarMulti"
        var payload = Data()
        payload.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"b.txt\"\r\nContent-Type: text/plain\r\n\r\n".utf8))
        payload.append(Data("from-b".utf8))
        payload.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (_, uploadResponse) = try await request(
            harness,
            "/api/upload",
            method: "POST",
            headers: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)",
                "Cookie": cookieB,
                "X-CalmBar-Client": "web"
            ],
            body: payload
        )
        #expect(uploadResponse.statusCode == 201)

        let (itemsData, itemsResponse) = try await request(
            harness,
            "/api/items",
            headers: ["Cookie": cookieA]
        )
        #expect(itemsResponse.statusCode == 200)
        let items = json(itemsData)["items"] as? [[String: Any]] ?? []
        #expect(items.count == 1)
        #expect(harness.sessions.activeSessionCount == 2)
    }

    // MARK: 辅助

    private func login(_ harness: Harness) async throws -> String {
        let token = try #require(harness.sessions.currentLinkToken.isEmpty ? nil : harness.sessions.currentLinkToken)
        let body = try JSONSerialization.data(withJSONObject: ["linkToken": token])
        let (_, response) = try await request(
            harness,
            "/api/session",
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "X-CalmBar-Client": "web"
            ],
            body: body
        )
        #expect(response.statusCode == 200)
        let setCookie = try #require(response.value(forHTTPHeaderField: "Set-Cookie"))
        return setCookie.split(separator: ";").first.map(String.init) ?? setCookie
    }
}
