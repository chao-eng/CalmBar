import Foundation

// MARK: - 解析事件与失败

public struct LANShareHTTPParseFailure: Error, Equatable, Sendable {
    public let status: Int
    public let reason: String

    public init(status: Int, reason: String) {
        self.status = status
        self.reason = reason
    }
}

public enum LANShareHTTPParseEvent: Sendable {
    case head(LANShareHTTPRequestHead)
    case body(Data)
    case complete
    case failure(LANShareHTTPParseFailure)
}

// MARK: - 最小 HTTP/1.1 增量解析器

/// 纯状态机，不依赖 NWConnection；只接受 origin-form 与 HTTP/1.1。
public final class LANShareHTTPParser {
    public enum State: String, Sendable {
        case head
        case body
        case complete
        case failed
    }

    private let maxBodyBytes: Int64
    private var buffer = Data()
    private var cursor = 0
    private var head: LANShareHTTPRequestHead?
    private var remainingBody: Int64 = 0
    private var bodyReceived: Int64 = 0
    private var failure: LANShareHTTPParseFailure?

    public private(set) var state: State = .head
    public private(set) var receivedByteCount: Int64 = 0
    public private(set) var consumedBodyBytes: Int64 = 0

    public init(maxBodyBytes: Int64 = LANShareLimits.maxRequestBodyBytes) {
        self.maxBodyBytes = maxBodyBytes
    }

    public var isComplete: Bool { state == .complete }
    public var isFailed: Bool { state == .failed }
    public var parseFailure: LANShareHTTPParseFailure? { failure }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
        cursor = 0
        head = nil
        remainingBody = 0
        bodyReceived = 0
        failure = nil
        receivedByteCount = 0
        consumedBodyBytes = 0
        state = .head
    }

    /// 追加数据并立即处理；事件按顺序同步回调。
    public func consume(_ data: Data, onEvent: (LANShareHTTPParseEvent) -> Void) {
        guard state == .head || state == .body else { return }
        guard !data.isEmpty else { return }
        receivedByteCount += Int64(data.count)
        buffer.append(data)

        if state == .head {
            processHead(onEvent: onEvent)
        }
        if state == .body {
            processBody(onEvent: onEvent)
        }
        compactBuffer()
    }

    /// 对端关闭：返回 true 表示是干净结束（已完成或零字节连接），false 表示半截请求。
    public func finish() -> Bool {
        if state == .complete { return true }
        if receivedByteCount == 0 { return true }
        if state == .head, head == nil, cursor == 0, buffer.isEmpty { return true }
        return false
    }

    // MARK: Head

    private func processHead(onEvent: (LANShareHTTPParseEvent) -> Void) {
        while state == .head {
            let available = buffer.count - cursor
            guard available > 0 else { return }

            guard let terminator = buffer.range(of: Data([13, 10, 13, 10]), in: cursor..<buffer.count) else {
                if available > LANShareLimits.maxHeaderBytes {
                    fail(status: 431, reason: "请求头过大", onEvent: onEvent)
                }
                return
            }

            let headerLength = terminator.lowerBound - cursor
            if headerLength > LANShareLimits.maxHeaderBytes {
                fail(status: 431, reason: "请求头过大", onEvent: onEvent)
                return
            }

            let headerData = buffer.subdata(in: cursor..<terminator.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                fail(status: 400, reason: "请求头不是有效文本", onEvent: onEvent)
                return
            }
            guard !containsBareLineBreak(headerText) else {
                fail(status: 400, reason: "请求头包含非法换行", onEvent: onEvent)
                return
            }

            let lines = headerText.components(separatedBy: "\r\n")
            guard let requestLine = lines.first, !requestLine.isEmpty else {
                fail(status: 400, reason: "缺少请求行", onEvent: onEvent)
                return
            }

            switch parseRequestLine(requestLine) {
            case .failure(let parseFailure):
                fail(status: parseFailure.status, reason: parseFailure.reason, onEvent: onEvent)
                return
            case .success(let parsed):
                var headers: [LANShareHTTPHeader] = []
                for line in lines.dropFirst() where !line.isEmpty {
                    guard headers.count < LANShareLimits.maxHeaderCount else {
                        fail(status: 431, reason: "请求头字段过多", onEvent: onEvent)
                        return
                    }
                    guard let header = parseHeaderLine(line) else {
                        fail(status: 400, reason: "请求头格式非法", onEvent: onEvent)
                        return
                    }
                    headers.append(header)
                }

                let requestHead = LANShareHTTPRequestHead(
                    method: parsed.method,
                    rawTarget: parsed.target,
                    rawPath: parsed.rawPath,
                    rawQuery: parsed.rawQuery,
                    decodedPath: parsed.decodedPath,
                    version: parsed.version,
                    headers: headers
                )

                switch validate(headers: headers, method: parsed.method) {
                case .failure(let parseFailure):
                    fail(status: parseFailure.status, reason: parseFailure.reason, onEvent: onEvent)
                    return
                case .success(let contentLength):
                    cursor = terminator.upperBound
                    head = requestHead
                    remainingBody = contentLength
                    bodyReceived = 0
                    state = contentLength > 0 ? .body : .complete
                    onEvent(.head(requestHead))
                    if state == .complete {
                        onEvent(.complete)
                    }
                    return
                }
            }
        }
    }

    private func parseRequestLine(_ line: String) -> Result<ParsedRequestLine, LANShareHTTPParseFailure> {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "请求行格式非法"))
        }
        let method = String(parts[0])
        guard ["GET", "HEAD", "POST", "DELETE"].contains(method) else {
            return .failure(LANShareHTTPParseFailure(status: 405, reason: "不支持的方法"))
        }
        let version = String(parts[2])
        guard version == "HTTP/1.1" else {
            return .failure(LANShareHTTPParseFailure(status: 501, reason: "仅支持 HTTP/1.1"))
        }
        let target = String(parts[1])
        guard target.hasPrefix("/"), !target.hasPrefix("//") else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "仅支持 origin-form 请求目标"))
        }

        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(pieces[0])
        let rawQuery = pieces.count > 1 ? String(pieces[1]) : nil
        guard let decodedPath = percentDecodeOnce(rawPath) else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "路径编码非法"))
        }
        guard isSafeDecodedPath(decodedPath) else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "路径包含非法字符"))
        }
        guard !containsDoubleEncoding(decodedPath) else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "路径存在双重编码"))
        }

        return .success(
            ParsedRequestLine(
                method: method,
                target: target,
                rawPath: rawPath,
                rawQuery: rawQuery,
                decodedPath: decodedPath,
                version: version
            )
        )
    }

    private func parseHeaderLine(_ line: String) -> LANShareHTTPHeader? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = String(line[..<colon])
        guard !name.isEmpty, name.utf8.allSatisfy(isTokenByte) else { return nil }
        var value = String(line[line.index(after: colon)...])
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        guard value.unicodeScalars.allSatisfy({ scalar in
            if scalar.value == 0x09 { return true }
            return scalar.value >= 0x20 && scalar.value != 0x7F
        }) else { return nil }
        return LANShareHTTPHeader(name: name, value: value)
    }

    private func validate(headers: [LANShareHTTPHeader], method: String) -> Result<Int64, LANShareHTTPParseFailure> {
        let hosts = headers.filter { $0.name.caseInsensitiveCompare("Host") == .orderedSame }
        guard hosts.count == 1, !hosts[0].value.isEmpty else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "Host 缺失或重复"))
        }

        let transferEncodings = headers.filter { $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame }
        if !transferEncodings.isEmpty {
            return .failure(LANShareHTTPParseFailure(status: 501, reason: "不支持分块传输编码"))
        }

        let lengths = headers.filter { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }
        if lengths.count > 1 {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "Content-Length 重复"))
        }

        let contentTypes = headers.filter { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
        if contentTypes.count > 1 {
            return .failure(LANShareHTTPParseFailure(status: 415, reason: "Content-Type 重复"))
        }

        let expects = headers.filter { $0.name.caseInsensitiveCompare("Expect") == .orderedSame }
        if let expect = expects.first, expect.value.caseInsensitiveCompare("100-continue") != .orderedSame {
            return .failure(LANShareHTTPParseFailure(status: 417, reason: "不支持的 Expect"))
        }

        if method == "GET" || method == "HEAD" || method == "DELETE" {
            return .success(0)
        }

        guard let rawLength = lengths.first?.value else {
            return .failure(LANShareHTTPParseFailure(status: 411, reason: "缺少 Content-Length"))
        }
        guard !rawLength.isEmpty,
              rawLength.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let parsed = Int64(rawLength) else {
            return .failure(LANShareHTTPParseFailure(status: 400, reason: "Content-Length 非法"))
        }
        if parsed > maxBodyBytes {
            return .failure(LANShareHTTPParseFailure(status: 413, reason: "请求体过大"))
        }
        return .success(parsed)
    }

    // MARK: Body

    private func processBody(onEvent: (LANShareHTTPParseEvent) -> Void) {
        while state == .body {
            let available = Int64(buffer.count - cursor)
            guard available > 0 else { return }
            let take = min(available, remainingBody)
            guard take > 0 else {
                state = .complete
                onEvent(.complete)
                return
            }
            let end = cursor + Int(take)
            let chunk = buffer.subdata(in: cursor..<end)
            cursor = end
            remainingBody -= take
            bodyReceived += take
            consumedBodyBytes += take
            onEvent(.body(chunk))
            if remainingBody == 0 {
                state = .complete
                onEvent(.complete)
                return
            }
        }
    }

    // MARK: Helpers

    private func fail(status: Int, reason: String, onEvent: (LANShareHTTPParseEvent) -> Void) {
        let parseFailure = LANShareHTTPParseFailure(status: status, reason: reason)
        failure = parseFailure
        state = .failed
        onEvent(.failure(parseFailure))
    }

    private func compactBuffer() {
        if cursor >= buffer.count {
            buffer.removeAll(keepingCapacity: false)
            cursor = 0
            return
        }
        if cursor >= 64 * 1024 {
            // 游标式压缩，避免 Data.removeFirst 造成底层容量线性增长
            buffer.removeSubrange(0..<cursor)
            cursor = 0
        }
    }

    private func containsBareLineBreak(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar.value == 10 {
                if index == 0 || scalars[index - 1].value != 13 { return true }
            } else if scalar.value == 13 {
                if index + 1 >= scalars.count || scalars[index + 1].value != 10 { return true }
            }
        }
        return false
    }

    private func isTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 33, 35...39, 42, 43, 45, 46, 48...57, 65...90, 94...122, 124, 126:
            return true
        default:
            return false
        }
    }

    private func percentDecodeOnce(_ raw: String) -> String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(raw.utf8.count)
        let scalars = Array(raw.utf8)
        var index = 0
        while index < scalars.count {
            let byte = scalars[index]
            if byte == 37 { // %
                guard index + 2 < scalars.count,
                      let high = hexValue(scalars[index + 1]),
                      let low = hexValue(scalars[index + 2]) else { return nil }
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(byte)
                index += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private func isSafeDecodedPath(_ path: String) -> Bool {
        guard !path.contains("\0"), !path.contains("\\"), !path.contains("//") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains("..")
    }

    private func containsDoubleEncoding(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("%2e") || lower.contains("%2f") || lower.contains("%5c") || lower.contains("%00")
    }
}

private struct ParsedRequestLine: Sendable {
    let method: String
    let target: String
    let rawPath: String
    let rawQuery: String?
    let decodedPath: String
    let version: String
}
