import Foundation
import Testing
@testable import CalmBar

// MARK: - HTTP Parser

@Suite("LANShare HTTP Parser")
struct LANShareHTTPParserTests {
    private struct Outcome {
        var head: LANShareHTTPRequestHead?
        var body = Data()
        var failure: LANShareHTTPParseFailure?
        var completed = false
    }

    private func parse(_ raw: String, maxBodyBytes: Int64 = LANShareLimits.maxRequestBodyBytes) -> Outcome {
        var outcome = Outcome()
        let parser = LANShareHTTPParser(maxBodyBytes: maxBodyBytes)
        parser.consume(Data(raw.utf8)) { event in
            switch event {
            case .head(let head):
                outcome.head = head
            case .body(let chunk):
                outcome.body.append(chunk)
            case .complete:
                outcome.completed = true
            case .failure(let failure):
                outcome.failure = failure
            }
        }
        return outcome
    }

    @Test("合法 GET 请求被完整解析")
    func parsesValidGet() {
        let outcome = parse("GET /api/items?item=abc HTTP/1.1\r\nHost: 192.168.1.10:47820\r\n\r\n")
        #expect(outcome.failure == nil)
        #expect(outcome.completed)
        #expect(outcome.head?.method == "GET")
        #expect(outcome.head?.decodedPath == "/api/items")
        #expect(outcome.head?.rawQuery == "item=abc")
        #expect(outcome.head?.hostHeader == "192.168.1.10:47820")
    }

    @Test("POST 按 Content-Length 聚合请求体")
    func parsesPostBody() {
        let outcome = parse(
            "POST /api/text HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"text\":\"hi\"}"
        )
        #expect(outcome.failure == nil)
        #expect(outcome.completed)
        #expect(String(data: outcome.body, encoding: .utf8) == "{\"text\":\"hi\"}")
    }

    @Test("分片到达时请求体可以增量拼接")
    func parsesChunkedArrival() {
        let parser = LANShareHTTPParser()
        var body = Data()
        var completed = false
        parser.consume(Data("POST /api/text HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nab".utf8)) { event in
            if case .body(let chunk) = event { body.append(chunk) }
        }
        parser.consume(Data("cde".utf8)) { event in
            if case .body(let chunk) = event { body.append(chunk) }
            if case .complete = event { completed = true }
        }
        #expect(completed)
        #expect(String(data: body, encoding: .utf8) == "abcde")
    }

    @Test("缺少 Host 头返回 400")
    func rejectsMissingHost() {
        #expect(parse("GET / HTTP/1.1\r\n\r\n").failure?.status == 400)
    }

    @Test("重复 Host 头返回 400")
    func rejectsDuplicateHost() {
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n").failure?.status == 400)
    }

    @Test("缺少 Content-Length 的 POST 返回 411")
    func rejectsPostWithoutLength() {
        #expect(parse("POST /api/text HTTP/1.1\r\nHost: localhost\r\n\r\n").failure?.status == 411)
    }

    @Test("Content-Length 超过上限返回 413")
    func rejectsOversizedBody() {
        let raw = "POST /api/upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2048\r\n\r\n"
        #expect(parse(raw, maxBodyBytes: 1024).failure?.status == 413)
    }

    @Test("重复 Content-Length 返回 400")
    func rejectsDuplicateLength() {
        let raw = "POST /api/text HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\nx"
        #expect(parse(raw).failure?.status == 400)
    }

    @Test("Transfer-Encoding 返回 501")
    func rejectsTransferEncoding() {
        let raw = "POST /api/text HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n"
        #expect(parse(raw).failure?.status == 501)
    }

    @Test("Expect 非 100-continue 返回 417")
    func rejectsUnsupportedExpect() {
        let raw = "POST /api/text HTTP/1.1\r\nHost: localhost\r\nExpect: something\r\nContent-Length: 1\r\n\r\nx"
        #expect(parse(raw).failure?.status == 417)
    }

    @Test("非 1.1 版本返回 501")
    func rejectsOldVersion() {
        #expect(parse("GET / HTTP/1.0\r\nHost: localhost\r\n\r\n").failure?.status == 501)
    }

    @Test("不支持的方法返回 405")
    func rejectsUnsupportedMethod() {
        #expect(parse("PUT / HTTP/1.1\r\nHost: localhost\r\n\r\n").failure?.status == 405)
    }

    @Test("裸 LF 换行被拒绝")
    func rejectsBareLineBreak() {
        #expect(parse("GET / HTTP/1.1\nHost: localhost\r\n\r\n").failure?.status == 400)
    }

    @Test("百分号编码的路径穿越被拒绝")
    func rejectsEncodedTraversal() {
        let outcome = parse("GET /api/download/%2e%2e%2fsecret HTTP/1.1\r\nHost: localhost\r\n\r\n")
        #expect(outcome.failure != nil)
    }

    @Test("重复编码的路径穿越被拒绝")
    func rejectsDoubleEncodedTraversal() {
        let outcome = parse("GET /%252e%252e/%2e%2e HTTP/1.1\r\nHost: localhost\r\n\r\n")
        #expect(outcome.failure != nil)
    }

    @Test("请求头超限返回 431")
    func rejectsOversizedHeader() {
        let padding = String(repeating: "a", count: LANShareLimits.maxHeaderBytes + 16)
        let raw = "GET / HTTP/1.1\r\nHost: localhost\r\nX-Pad: \(padding)\r\n\r\n"
        #expect(parse(raw).failure?.status == 431)
    }

    @Test("零字节连接的 finish 视为干净结束")
    func finishEmptyIsClean() {
        let parser = LANShareHTTPParser()
        #expect(parser.finish())
    }

    @Test("半截请求的 finish 返回 false")
    func finishPartialIsDirty() {
        let parser = LANShareHTTPParser()
        parser.consume(Data("GET / HTTP/1.1\r\nHost: local".utf8)) { _ in }
        #expect(!parser.finish())
    }
}

// MARK: - Multipart

@Suite("LANShare Multipart Parser")
struct LANShareMultipartParserTests {
    private func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareMultipart-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("单文件上传被流式写入临时文件")
    func parsesSingleFile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let boundary = "----CalmBarTest"
        let body = """
        --\(boundary)\r
        Content-Disposition: form-data; name="file"; filename="hello.txt"\r
        Content-Type: text/plain\r
        \r
        hello world\r
        --\(boundary)--\r

        """

        let parser = try LANShareMultipartParser(boundary: boundary, tempDirectory: directory)
        try parser.consume(Data(body.utf8))
        let result = try parser.finish()

        #expect(result.filename == "hello.txt")
        #expect(result.byteCount == 11)
        #expect(result.contentType == "text/plain")
        let content = try String(contentsOf: result.tempURL, encoding: .utf8)
        #expect(content == "hello world")
    }

    @Test("上传文件名中的路径被清洗")
    func sanitizesFilename() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let boundary = "b"
        let body = "--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"../../etc/passwd\"\r\n\r\nx\r\n--b--\r\n"
        let parser = try LANShareMultipartParser(boundary: boundary, tempDirectory: directory)
        try parser.consume(Data(body.utf8))
        let result = try parser.finish()
        #expect(result.filename == "passwd")
    }

    @Test("未结束的 multipart 请求抛出错误并清理临时文件")
    func rejectsUnfinishedBody() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let body = "--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n\r\npartial"
        let parser = try LANShareMultipartParser(boundary: "b", tempDirectory: directory)
        try parser.consume(Data(body.utf8))
        #expect(throws: (any Error).self) {
            _ = try parser.finish()
        }
        parser.cancel()
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty)
    }
}

// MARK: - 路径安全

@Suite("LANShare Path Validator")
struct LANSharePathValidatorTests {
    @Test("文件名清洗去除路径与控制字符")
    func sanitizesFilename() {
        #expect(LANSharePathValidator.sanitizeFilename("../../etc/passwd") == "passwd")
        #expect(LANSharePathValidator.sanitizeFilename("folder/file.txt") == "file.txt")
        #expect(LANSharePathValidator.sanitizeFilename("a\\b.txt") == "b.txt")
        #expect(LANSharePathValidator.sanitizeFilename("...") == "未命名文件")
        #expect(LANSharePathValidator.sanitizeFilename("   ") == "未命名文件")
        #expect(LANSharePathValidator.sanitizeFilename("report\u{0}.pdf") == "report.pdf")
    }

    @Test("合法相对路径通过校验")
    func acceptsValidPath() throws {
        try LANSharePathValidator.validateRelativePath("")
        try LANSharePathValidator.validateRelativePath("docs/report.pdf")
    }

    @Test("路径穿越与绝对路径被拒绝")
    func rejectsInvalidPath() {
        #expect(throws: (any Error).self) { try LANSharePathValidator.validateRelativePath("..") }
        #expect(throws: (any Error).self) { try LANSharePathValidator.validateRelativePath("a/../b") }
        #expect(throws: (any Error).self) { try LANSharePathValidator.validateRelativePath("/etc/passwd") }
        #expect(throws: (any Error).self) { try LANSharePathValidator.validateRelativePath("a//b") }
        #expect(throws: (any Error).self) { try LANSharePathValidator.validateRelativePath("a/./b") }
        #expect(throws: (any Error).self) { try LANSharePathValidator.validateRelativePath("a\\b") }
    }

    @Test("单文件与文件夹均可按 fd 级校验打开")
    func opensFileAndDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)

        let fileHandle = try LANSharePathValidator.open(root: root.path, relativePath: "note.txt", allowDirectory: false)
        #expect(!fileHandle.isDirectory)
        #expect(fileHandle.size == 5)
        fileHandle.close()

        let directoryHandle = try LANSharePathValidator.open(root: root.path, relativePath: "", allowDirectory: true)
        #expect(directoryHandle.isDirectory)
        directoryHandle.close()
    }
}

// MARK: - 文本条目命名

@Suite("LANShare Text Title")
struct LANShareTextTitleTests {
    @Test("取首行前 20 个字符作为标题")
    func usesFirstLinePrefix() {
        #expect(LANShareTextTitle.make(from: "内容") == "内容")
        #expect(LANShareTextTitle.make(from: "第一行\n第二行") == "第一行")
        #expect(LANShareTextTitle.make(from: String(repeating: "a", count: 30)).count == 20)
    }

    @Test("空文本回退为文本片段")
    func fallsBackWhenEmpty() {
        #expect(LANShareTextTitle.make(from: "\n\n") == "文本片段")
        #expect(LANShareTextTitle.make(from: "   ") == "文本片段")
    }
}

// MARK: - 网络接口

@Suite("LANShare Network Interfaces")
struct LANShareNetworkInterfaceTests {
    @Test("虚拟网卡被识别并排除在自动选择之外")
    func identifiesVirtualInterfaces() {
        for name in ["utun4", "ipsec0", "ppp0", "awdl0", "llw0", "bridge0", "gif0", "anpi0"] {
            #expect(LANShareNetworkInterfaces.isVirtualInterface(name))
        }
        for name in ["en0", "en5", "en7"] {
            #expect(!LANShareNetworkInterfaces.isVirtualInterface(name))
        }
    }

    @Test("枚举结果不会把虚拟网卡当作默认网卡")
    func bestAddressSkipsVirtualInterfaces() {
        let best = LANShareNetworkInterfaces.bestAddress(preferredInterface: "utun4")
        if let best {
            #expect(!best.isVirtual)
        }
    }

    @Test("从 sockaddr 正确解析 IPv4 地址与掩码")
    func parsesIPv4Sockaddr() throws {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, "192.168.10.10", &sin.sin_addr)

        var mask = sockaddr_in()
        mask.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        mask.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, "255.255.255.0", &mask.sin_addr)

        let parsed = withUnsafePointer(to: sin) { sinPtr in
            withUnsafePointer(to: mask) { maskPtr in
                sinPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    maskPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { netmask in
                        LANShareNetworkInterfaces.parseAddress(name: "en0", address: addr, netmask: netmask)
                    }
                }
            }
        }
        let address = try #require(parsed)
        #expect(address.address == "192.168.10.10")
        #expect(address.prefixLength == 24)
        #expect(address.family == .ipv4)
        #expect(!address.isLinkLocal)
    }

    @Test("从 sockaddr 正确解析 IPv6 地址与掩码")
    func parsesIPv6Sockaddr() throws {
        var sin6 = sockaddr_in6()
        sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        sin6.sin6_family = sa_family_t(AF_INET6)
        inet_pton(AF_INET6, "fd00::1234", &sin6.sin6_addr)

        var mask = sockaddr_in6()
        mask.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        mask.sin6_family = sa_family_t(AF_INET6)
        inet_pton(AF_INET6, "ffff:ffff:ffff:ffff::", &mask.sin6_addr)

        let parsed = withUnsafePointer(to: sin6) { sin6Ptr in
            withUnsafePointer(to: mask) { maskPtr in
                sin6Ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    maskPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { netmask in
                        LANShareNetworkInterfaces.parseAddress(name: "en0", address: addr, netmask: netmask)
                    }
                }
            }
        }
        let address = try #require(parsed)
        #expect(address.address == "fd00::1234")
        #expect(address.prefixLength == 64)
        #expect(address.family == .ipv6)
        #expect(!address.isLinkLocal)
    }
}

// MARK: - 会话与认证

@Suite("LANShare Session Manager")
struct LANShareSessionManagerTests {
    private func makeManager(passcodeEnabled: Bool = false) -> (LANShareSessionManager, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareSession-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let passcodeStore = LANSharePasscodeStore(stateDirectory: directory)
        let manager = LANShareSessionManager(passcodeStore: passcodeStore, passcodeEnabled: passcodeEnabled)
        return (manager, directory)
    }

    @Test("正确链接令牌可换取会话 Cookie")
    func logsInWithLinkToken() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        let token = try manager.login(
            linkToken: manager.currentLinkToken,
            passcode: nil,
            peerIP: "192.168.1.20",
            userAgent: "Test"
        )
        #expect(!token.isEmpty)

        let session = manager.authenticate(cookieHeader: "calmbar_session=\(token)", peerIP: "192.168.1.20")
        #expect(session != nil)
        #expect(manager.activeSessionCount == 1)
    }

    @Test("错误链接令牌返回 401")
    func rejectsWrongLinkToken() {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: LANShareError.unauthorized) {
            _ = try manager.login(
                linkToken: "wrong",
                passcode: nil,
                peerIP: "192.168.1.21",
                userAgent: "Test"
            )
        }
    }

    @Test("连续失败 10 次后单 IP 被锁定 60 秒")
    func locksAfterRepeatedFailures() {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        for _ in 0..<10 {
            #expect(throws: LANShareError.unauthorized) {
                _ = try manager.login(linkToken: "wrong", passcode: nil, peerIP: "10.0.0.9", userAgent: "Test")
            }
        }
        #expect(throws: LANShareError.rateLimited) {
            _ = try manager.login(
                linkToken: manager.currentLinkToken,
                passcode: nil,
                peerIP: "10.0.0.9",
                userAgent: "Test"
            )
        }
    }

    @Test("停止服务后令牌轮换且会话全部失效")
    func revokeAllInvalidatesSessions() throws {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        let token = try manager.login(
            linkToken: manager.currentLinkToken,
            passcode: nil,
            peerIP: "192.168.1.22",
            userAgent: "Test"
        )
        let oldLinkToken = manager.currentLinkToken
        manager.revokeAll()

        #expect(manager.activeSessionCount == 0)
        #expect(manager.authenticate(cookieHeader: "calmbar_session=\(token)", peerIP: "192.168.1.22") == nil)
        #expect(manager.currentLinkToken != oldLinkToken)
    }

    @Test("Cookie 属性符合安全要求")
    func cookieHeaderIsHardened() {
        let (manager, directory) = makeManager()
        defer { try? FileManager.default.removeItem(at: directory) }

        let header = manager.setCookieHeader(token: "abc")
        #expect(header.contains("HttpOnly"))
        #expect(header.contains("SameSite=Strict"))
        #expect(header.contains("Path=/"))
    }
}
