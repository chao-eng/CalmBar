import Foundation
import Network

/// 更新代理的本地转发服务。
///
/// Sparkle 的下载逻辑运行在独立进程里，读不到 App 内配置的代理。因此启用
/// 更新代理时：
/// - `Updater` 通过 `feedURLString(for:)` 把 Sparkle 的更新源指向本服务；
/// - 本服务用带代理的 URLSession 拉取真实 appcast，并把 enclosure /
///   releaseNotes 的地址改写为 `http://127.0.0.1:<port>/fetch?...`；
/// - Sparkle 下载安装包时实际请求本机，再由本服务通过代理把真实内容转发回去。
///
/// 安全约束：只接受回环连接，所有请求都必须携带启动时生成的随机 token，
/// 避免被本机其它进程当成通用代理使用。
@MainActor
final class UpdateRelayServer {
    static let shared = UpdateRelayServer()

    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private(set) var isReady = false

    /// 供 Sparkle 使用的 appcast 地址；未就绪时返回 nil，让 Sparkle 退回 Info.plist 的直连地址。
    var appcastURL: String? {
        guard isReady, port > 0 else { return nil }
        return "http://127.0.0.1:\(port)/appcast.xml?token=\(token)"
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: .any) else { return }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = listener.port?.rawValue ?? 0
                    self.isReady = self.port > 0
                case .failed, .cancelled:
                    self.isReady = false
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            guard UpdateRelayServer.isLoopback(connection.endpoint) else {
                connection.cancel()
                return
            }
            connection.start(queue: .main)
            Task { @MainActor in
                await self.handle(connection)
            }
        }
        listener.start(queue: .main)
    }

    private nonisolated static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return "\(address)" == "127.0.0.1"
        case .ipv6(let address): return "\(address)" == "::1"
        default: return false
        }
    }

    // MARK: - 请求处理

    private func handle(_ connection: NWConnection) async {
        var buffer = Data()
        while buffer.count < 16 * 1024 {
            let chunk: Data? = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, _ in
                    if isComplete && (data?.isEmpty ?? true) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: data)
                    }
                }
            }
            guard let chunk else { break }
            buffer.append(chunk)
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }

        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer.prefix(upTo: headEnd.lowerBound), encoding: .utf8) else {
            send(connection: connection, status: "400 Bad Request", body: nil, contentType: nil)
            return
        }

        let firstLine = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(connection: connection, status: "400 Bad Request", body: nil, contentType: nil)
            return
        }
        let method = String(parts[0])
        let target = String(parts[1])
        guard method == "GET" || method == "HEAD" else {
            send(connection: connection, status: "405 Method Not Allowed", body: nil, contentType: nil)
            return
        }
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              components.queryItems?.first(where: { $0.name == "token" })?.value == token else {
            send(connection: connection, status: "403 Forbidden", body: nil, contentType: nil)
            return
        }

        switch components.path {
        case "/appcast.xml":
            await serveAppcast(connection: connection, headOnly: method == "HEAD")
        case "/fetch":
            let raw = components.queryItems?.first(where: { $0.name == "url" })?.value ?? ""
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                send(connection: connection, status: "400 Bad Request", body: nil, contentType: nil)
                return
            }
            RelayStreamer(connection: connection, url: url, method: method).start()
        default:
            send(connection: connection, status: "404 Not Found", body: nil, contentType: nil)
        }
    }

    private func serveAppcast(connection: NWConnection, headOnly: Bool) async {
        guard let feedText = UpdateProxyConfig.feedURLString,
              let feedURL = URL(string: feedText) else {
            send(connection: connection, status: "500 Internal Server Error", body: nil, contentType: nil)
            return
        }
        let session = URLSession(configuration: UpdateNetwork.makeConfiguration(timeout: 15, resourceTimeout: 20))
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let xml = String(data: data, encoding: .utf8) else {
                send(connection: connection, status: "502 Bad Gateway", body: nil, contentType: nil)
                return
            }
            let body = Data(rewriteAppcast(xml, base: feedURL).utf8)
            send(connection: connection,
                 status: "200 OK",
                 body: headOnly ? nil : body,
                 contentType: "application/rss+xml; charset=utf-8",
                 contentLength: headOnly ? body.count : nil)
        } catch {
            send(connection: connection, status: "502 Bad Gateway", body: nil, contentType: nil)
        }
    }

    // MARK: - appcast 地址改写

    private func rewriteAppcast(_ xml: String, base: URL) -> String {
        var result = xml
        let patterns = [
            "(<enclosure\\b[^>]*?\\burl=\")([^\"]+)(\")",
            "(<sparkle:releaseNotesLink\\b[^>]*>)([^<]+)(</sparkle:releaseNotesLink>)",
            "(<sparkle:fullReleaseNotesLink\\b[^>]*>)([^<]+)(</sparkle:fullReleaseNotesLink>)",
        ]
        for pattern in patterns {
            result = replaceMatches(pattern: pattern, group: 2, in: result) { raw in
                relayURL(for: raw, base: base).map(xmlEscaped)
            }
        }
        return result
    }

    /// 转发地址里带有 `?token=…&url=…`，XML 中裸 `&` 非法，必须转义成
    /// `&amp;`，否则 Sparkle 解析 appcast 会直接报 SUAppcastParseError。
    private func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func replaceMatches(pattern: String,
                                group: Int,
                                in text: String,
                                transform: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        var result = text as NSString
        // 从后往前替换，保证前面匹配项的 range 仍然有效。
        for match in matches.reversed() {
            guard match.numberOfRanges > group,
                  match.range(at: group).location != NSNotFound else { continue }
            let raw = result.substring(with: match.range(at: group))
            guard let replacement = transform(raw) else { continue }
            result = result.replacingCharacters(in: match.range(at: group), with: replacement) as NSString
        }
        return result as String
    }

    private func relayURL(for raw: String, base: URL) -> String? {
        guard let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              port > 0 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return "http://127.0.0.1:\(port)/fetch?token=\(token)&url=\(encoded)"
    }

    // MARK: - 响应

    private func send(connection: NWConnection,
                      status: String,
                      body: Data?,
                      contentType: String?,
                      contentLength: Int? = nil) {
        let payload = body ?? Data()
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Length: \(contentLength ?? payload.count)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-store\r\n"
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        if body != nil { out.append(payload) }
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// 把真实服务器的响应边收边写回本地连接。代理配置在请求发起时读取，
/// 因此用户修改代理设置后，下一次下载立即生效。
private final class RelayStreamer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let connection: NWConnection
    private let url: URL
    private let method: String
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var responded = false
    private var finished = false

    init(connection: NWConnection, url: URL, method: String) {
        self.connection = connection
        self.url = url
        self.method = method
        super.init()
        // 客户端断开（例如用户取消更新）时停止上游下载。
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.abort()
            default:
                break
            }
        }
    }

    func start() {
        let configuration = UpdateNetwork.makeConfiguration(timeout: 30, resourceTimeout: 600)
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    private func abort() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        connection.cancel()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.send(content: nil,
                        contentContext: .defaultMessage,
                        isComplete: true,
                        completion: .contentProcessed { [connection] _ in
                            connection.cancel()
                        })
        session?.finishTasksAndInvalidate()
        session = nil
    }

    private func respondError(_ status: String) {
        finished = true
        let head = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            completionHandler(.cancel)
            respondError("502 Bad Gateway")
            return
        }
        responded = true
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream")\r\n"
        // Sparkle 用响应里的 filename 命名下载的临时文件，再按扩展名选解压器；
        // 转发地址最后一段是 /fetch，不透传原文件名会被当成无扩展名文件导致解压失败。
        let filename = RelayStreamer.safeFilename(from: url)
        head += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
        // 上游若压缩过，长度是压缩后的，不能直接透传，改用连接关闭界定响应体。
        if http.value(forHTTPHeaderField: "Content-Encoding") == nil, http.expectedContentLength >= 0 {
            head += "Content-Length: \(http.expectedContentLength)\r\n"
        }
        head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        completionHandler(.allow)
    }

    /// 取被转发资源本身的文件名（如 CalmBar-2.4.1.dmg），保证 Sparkle 落盘后扩展名正确。
    private static func safeFilename(from url: URL) -> String {
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard !name.isEmpty, !name.contains("/") else { return "CalmBar-update.dmg" }
        return name.replacingOccurrences(of: "\"", with: "")
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        if error != nil {
            if responded {
                // 已发出响应头，只能断开连接让 Sparkle 感知下载不完整。
                abort()
            } else {
                respondError("502 Bad Gateway")
            }
            return
        }
        finish()
    }
}
