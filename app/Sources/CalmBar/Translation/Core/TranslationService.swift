import Foundation

public enum TranslationServiceError: LocalizedError, Sendable {
    case emptyText
    case invalidURL(String)
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "翻译文本不能为空"
        case .invalidURL(let url):
            return "无效的 API 地址: \(url)"
        case .httpError(let code, let msg):
            return "服务请求失败 (HTTP \(code)): \(msg)"
        case .decodingError(let msg):
            return "响应解析错误: \(msg)"
        case .cancelled:
            return "翻译任务已取消"
        case .unknown(let msg):
            return msg
        }
    }
}

public final class TranslationService: Sendable {
    public static let shared = TranslationService()

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 300
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Prompt Construction

    public static func buildPrompt(
        text: String,
        targetLanguage: TranslationLanguage,
        customPromptTemplate: String? = nil
    ) -> String {
        if let template = customPromptTemplate, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return template
                .replacingOccurrences(of: "{targetLanguage}", with: targetLanguage.englishName)
                .replacingOccurrences(of: "{targetLanguageZH}", with: targetLanguage.chineseName)
                .replacingOccurrences(of: "{text}", with: text)
        }

        // 标准 HY-MT2 / OpenAI 翻译提示词
        return "Translate the following segment into \(targetLanguage.englishName), without additional explanation:\n\n\(text)"
    }

    // MARK: - Streaming Translation

    public func translateStream(
        text: String,
        targetLanguage: TranslationLanguage,
        baseURL: String,
        apiKey: String?,
        model: String,
        customPromptTemplate: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> (fullText: String, usage: TranslationUsage?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationServiceError.emptyText
        }

        let prompt = Self.buildPrompt(
            text: trimmed,
            targetLanguage: targetLanguage,
            customPromptTemplate: customPromptTemplate
        )

        let request = try makeRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            stream: true
        )

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.unknown("未收到有效的 HTTP 响应")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 1000 { break }
            }
            throw TranslationServiceError.httpError(statusCode: httpResponse.statusCode, message: errorBody.isEmpty ? "Server Error" : errorBody)
        }

        var accumulated = ""
        var usage: TranslationUsage?
        var lastChunkTime: CFAbsoluteTime = 0

        for try await line in bytes.lines {
            try Task.checkCancellation()

            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix(":") {
                continue
            }

            guard trimmedLine.hasPrefix("data:") else {
                continue
            }

            let dataContent = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if dataContent == "[DONE]" {
                break
            }

            guard let jsonData = dataContent.data(using: .utf8) else {
                continue
            }

            if let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData) {
                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                    accumulated += delta
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastChunkTime >= 0.035 { // ~30fps 节流，避免高频 token 频繁唤醒主线程
                        lastChunkTime = now
                        onChunk(accumulated)
                    }
                }
                if let u = chunk.usage {
                    usage = TranslationUsage(
                        promptTokens: u.prompt_tokens,
                        completionTokens: u.completion_tokens,
                        totalTokens: u.total_tokens
                    )
                }
            }
        }

        return (accumulated, usage)
    }

    // MARK: - Connection Test

    public func testConnection(
        baseURL: String,
        apiKey: String?,
        model: String
    ) async throws -> (latencyMs: Int, sampleResponse: String) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let prompt = "Translate the following segment into Chinese, without additional explanation:\n\nHello, world!"

        let request = try makeRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            stream: false
        )

        let (data, response) = try await session.data(for: request)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.unknown("未收到有效的 HTTP 响应")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "未知错误"
            throw TranslationServiceError.httpError(statusCode: httpResponse.statusCode, message: body)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let reply = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (elapsed, reply)
    }

    // MARK: - Helper Methods

    private func makeRequest(
        baseURL: String,
        apiKey: String?,
        model: String,
        prompt: String,
        stream: Bool
    ) throws -> URLRequest {
        var cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBase.hasSuffix("/") {
            cleanBase.removeLast()
        }

        let fullURLString: String
        if cleanBase.hasSuffix("/chat/completions") {
            fullURLString = cleanBase
        } else if cleanBase.hasSuffix("/v1") {
            fullURLString = cleanBase + "/chat/completions"
        } else {
            fullURLString = cleanBase + "/v1/chat/completions"
        }

        guard let url = URL(string: fullURLString) else {
            throw TranslationServiceError.invalidURL(fullURLString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("no", forHTTPHeaderField: "X-Accel-Buffering")
        }

        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "user", content: prompt)
            ],
            stream: stream,
            temperature: 0.3
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
}

// MARK: - Internal DTOs for OpenAI Protocol

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
    let usage: Usage?

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
    let usage: Usage?

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}
