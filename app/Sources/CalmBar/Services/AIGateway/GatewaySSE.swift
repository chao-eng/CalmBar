import Foundation

// MARK: - SSE 解析

public struct GatewaySSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }

    public var isDone: Bool {
        data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]"
    }
}

/// 增量 SSE 解析器：支持跨 chunk 拆分、CRLF/CR/LF 三种换行、注释与多行 data
public struct GatewaySSEParser {
    private var buffer = Data()
    private var pendingCR = false
    private var lastEventID: String?
    private let maxEventBytes: Int

    public private(set) var overflowed = false

    public init(maxEventBytes: Int = 1_048_576) {
        self.maxEventBytes = maxEventBytes
    }

    public mutating func feed(_ data: Data) -> [GatewaySSEEvent] {
        guard !overflowed else { return [] }
        var normalized = Data()
        normalized.reserveCapacity(data.count + buffer.count)

        for byte in data {
            if pendingCR {
                pendingCR = false
                normalized.append(0x0A)
                if byte == 0x0A { continue }
            }
            if byte == 0x0D {
                pendingCR = true
                continue
            }
            normalized.append(byte)
        }

        buffer.append(normalized)

        var events: [GatewaySSEEvent] = []
        while let range = buffer.range(of: Data([0x0A, 0x0A])) {
            let block = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let event = parseBlock(block) {
                events.append(event)
            }
        }

        if buffer.count > maxEventBytes {
            overflowed = true
            buffer.removeAll(keepingCapacity: false)
            events.removeAll()
        }
        return events
    }

    /// 流结束时冲刷最后一个未以空行结尾的事件
    public mutating func finish() -> [GatewaySSEEvent] {
        guard !overflowed, !buffer.isEmpty else { return [] }
        let block = buffer
        buffer.removeAll(keepingCapacity: false)
        if let event = parseBlock(block) {
            return [event]
        }
        return []
    }

    private mutating func parseBlock(_ block: Data) -> GatewaySSEEvent? {
        guard !block.isEmpty, let text = String(data: block, encoding: .utf8) else { return nil }
        var eventName: String?
        var dataLines: [String] = []
        var eventID: String?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            if line.hasPrefix(":") { continue }
            let content = String(line)
            let field: String
            var value: String
            if let colon = content.firstIndex(of: ":") {
                field = String(content[..<colon])
                value = String(content[content.index(after: colon)...])
                if value.hasPrefix(" ") { value.removeFirst() }
            } else {
                field = content
                value = ""
            }
            switch field {
            case "event":
                eventName = value
            case "data":
                dataLines.append(value)
            case "id":
                eventID = value
                lastEventID = value
            default:
                break
            }
        }

        guard !dataLines.isEmpty || eventName != nil else { return nil }
        return GatewaySSEEvent(
            event: eventName,
            data: dataLines.joined(separator: "\n"),
            id: eventID ?? lastEventID
        )
    }
}

// MARK: - Token 估算

public enum GatewayTokenEstimator {
    /// 轻量估算：CJK 按字计，拉丁按 4 字符 1 token，向上取整
    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x2E80 { cjk += 1 } else { other += 1 }
        }
        return cjk + Int(ceil(Double(other) / 4.0))
    }

    public static func estimateInput(from body: Data) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let json = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: json, encoding: .utf8) else {
            return estimate(String(decoding: body, as: UTF8.self))
        }
        return estimate(text)
    }
}

// MARK: - 协议与用量

public enum GatewayStreamProtocol: String, Sendable {
    case chat
    case responses

    public var displayName: String {
        switch self {
        case .chat: return "Chat Completions"
        case .responses: return "Responses"
        }
    }

    public init?(endpoint: String) {
        switch endpoint {
        case "/v1/chat/completions": self = .chat
        case "/v1/responses": self = .responses
        default: return nil
        }
    }
}

public struct GatewayUsage: Sendable, Equatable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    public var isEmpty: Bool {
        inputTokens == nil && outputTokens == nil && totalTokens == nil
    }
}

public struct GatewayStreamError: Sendable, Equatable {
    public var code: String?
    public var message: String

    public init(code: String? = nil, message: String) {
        self.code = code
        self.message = message
    }
}

public enum GatewayStreamSignal: Sendable, Equatable {
    case none
    case commit
    case terminal
    case error
}

// MARK: - 流内容分析（首内容判定 / Token 估算 / usage 捕获）

public struct GatewayStreamAnalyzer: Sendable {
    public let protocolName: GatewayStreamProtocol
    public private(set) var firstContentAt: Date?
    public private(set) var lastContentAt: Date?
    public private(set) var estimatedOutputTokens = 0
    public private(set) var usage: GatewayUsage?
    public private(set) var responseID: String?
    public private(set) var upstreamModel: String?
    public private(set) var streamError: GatewayStreamError?
    public private(set) var isTerminal = false
    public private(set) var eventCount = 0
    /// 已经通过 delta 累加过文本的 item，避免 output_item.done 重复计 token
    private var deltaItemIDs: Set<String> = []

    public init(protocolName: GatewayStreamProtocol) {
        self.protocolName = protocolName
    }

    public var hasCommitted: Bool { firstContentAt != nil }

    public mutating func consume(_ event: GatewaySSEEvent, at date: Date = Date()) -> GatewayStreamSignal {
        eventCount += 1

        switch protocolName {
        case .chat:
            return consumeChat(event, at: date)
        case .responses:
            return consumeResponses(event, at: date)
        }
    }

    // MARK: Chat Completions

    private mutating func consumeChat(_ event: GatewaySSEEvent, at date: Date) -> GatewayStreamSignal {
        if event.isDone {
            isTerminal = true
            return .terminal
        }
        guard let object = Self.jsonObject(event.data) else {
            if hasCommitted { lastContentAt = date }
            return .none
        }

        captureMetadata(from: object)

        if let error = object["error"] {
            streamError = Self.parseError(error)
            isTerminal = true
            return .error
        }
        if let usage = object["usage"] as? [String: Any] {
            merge(usage: usage)
        }

        var committed = false
        var addedTokens = 0

        if let choices = object["choices"] as? [[String: Any]] {
            for choice in choices {
                guard let delta = choice["delta"] as? [String: Any] else { continue }
                var pieces: [String] = []
                if let content = delta["content"] as? String { pieces.append(content) }
                if let reasoning = delta["reasoning_content"] as? String { pieces.append(reasoning) }
                if let reasoning = delta["reasoning"] as? String { pieces.append(reasoning) }
                if let calls = delta["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        if let function = call["function"] as? [String: Any],
                           let arguments = function["arguments"] as? String,
                           !arguments.isEmpty {
                            pieces.append(arguments)
                        }
                    }
                }
                let text = pieces.joined()
                if !text.isEmpty {
                    committed = true
                    addedTokens += GatewayTokenEstimator.estimate(text)
                }
            }
        }

        if committed {
            estimatedOutputTokens += addedTokens
            if firstContentAt == nil { firstContentAt = date }
            lastContentAt = date
            return .commit
        }
        return .none
    }

    // MARK: Responses

    private mutating func consumeResponses(_ event: GatewaySSEEvent, at date: Date) -> GatewayStreamSignal {
        let name = event.event ?? ""
        if name == "error" {
            let parsed = Self.jsonObject(event.data)
            streamError = parsed.flatMap { Self.parseError($0["error"] ?? $0) } ?? GatewayStreamError(message: event.data)
            isTerminal = true
            return .error
        }

        guard let object = Self.jsonObject(event.data) else {
            return .none
        }
        if let response = object["response"] as? [String: Any] {
            captureMetadata(from: response)
            if let usage = response["usage"] as? [String: Any] {
                merge(usage: usage)
            }
        }
        captureMetadata(from: object)
        if let usage = object["usage"] as? [String: Any] {
            merge(usage: usage)
        }

        if let error = object["error"], name != "response.incomplete" {
            streamError = Self.parseError(error)
            isTerminal = true
            return .error
        }

        var committed = false
        var addedTokens = 0

        switch name {
        case "response.output_text.delta", "response.refusal.delta",
             "response.reasoning_text.delta", "response.function_call_arguments.delta", "response.reasoning_summary_text.delta":
            if let delta = object["delta"] as? String, !delta.isEmpty {
                committed = true
                addedTokens += GatewayTokenEstimator.estimate(delta)
                if let itemID = object["item_id"] as? String {
                    deltaItemIDs.insert(itemID)
                }
            }
        case "response.output_item.done", "response.output_item.added":
            if let item = object["item"] as? [String: Any] {
                let text = Self.extractItemText(item)
                if !text.isEmpty {
                    committed = true
                    // delta 已经累加过同一个 item 的文本，这里只做提交判定，避免重复计 token
                    let itemID = item["id"] as? String
                    if itemID.map({ !deltaItemIDs.contains($0) }) ?? true {
                        addedTokens += GatewayTokenEstimator.estimate(text)
                    }
                }
            }
        case "response.completed", "response.incomplete":
            if let response = object["response"] as? [String: Any],
               let output = response["output"] as? [[String: Any]] {
                let text = output.map(Self.extractItemText).joined()
                if !text.isEmpty {
                    committed = true
                    if firstContentAt == nil || eventCount <= 1 {
                        addedTokens += GatewayTokenEstimator.estimate(text)
                    }
                }
            }
            if let response = object["response"] as? [String: Any],
               let status = response["status"] as? String,
               status == "failed" {
                streamError = GatewayStreamError(message: "上游生成失败")
            }
            isTerminal = true
        case "response.failed":
            streamError = GatewayStreamError(message: "上游生成失败")
            isTerminal = true
            return .error
        default:
            break
        }

        if committed {
            estimatedOutputTokens += addedTokens
            if firstContentAt == nil { firstContentAt = date }
            lastContentAt = date
            return .commit
        }
        if isTerminal {
            return .terminal
        }
        return .none
    }

    // MARK: 工具

    private mutating func captureMetadata(from object: [String: Any]) {
        if responseID == nil, let id = object["id"] as? String {
            responseID = id
        }
        if upstreamModel == nil, let model = object["model"] as? String {
            upstreamModel = model
        }
    }

    private mutating func merge(usage payload: [String: Any]) {
        let input = payload["input_tokens"] as? Int ?? payload["prompt_tokens"] as? Int
        let output = payload["output_tokens"] as? Int ?? payload["completion_tokens"] as? Int
        let total = payload["total_tokens"] as? Int
        guard input != nil || output != nil || total != nil else { return }
        self.usage = GatewayUsage(
            inputTokens: input ?? self.usage?.inputTokens,
            outputTokens: output ?? self.usage?.outputTokens,
            totalTokens: total ?? self.usage?.totalTokens
        )
    }

    private static func parseError(_ value: Any) -> GatewayStreamError {
        if let dict = value as? [String: Any] {
            let message = dict["message"] as? String ?? "上游返回错误"
            return GatewayStreamError(code: dict["code"] as? String ?? dict["type"] as? String, message: message)
        }
        if let text = value as? String {
            return GatewayStreamError(message: text)
        }
        return GatewayStreamError(message: "上游返回错误")
    }

    private static func extractItemText(_ item: [String: Any]) -> String {
        var pieces: [String] = []
        if let content = item["content"] as? [[String: Any]] {
            for part in content {
                if let text = part["text"] as? String { pieces.append(text) }
                if let refusal = part["refusal"] as? String { pieces.append(refusal) }
            }
        }
        if let text = item["text"] as? String { pieces.append(text) }
        if let arguments = item["arguments"] as? String { pieces.append(arguments) }
        if let summary = item["summary"] as? [[String: Any]] {
            for part in summary {
                if let text = part["text"] as? String { pieces.append(text) }
            }
        }
        return pieces.joined()
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
