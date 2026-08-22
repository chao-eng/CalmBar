import Foundation

public enum TranslationStatus: String, Codable, Sendable {
    case idle
    case loading
    case streaming
    case completed
    case failed
}

public struct TranslationUsage: Codable, Equatable, Sendable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct TranslationItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let originalText: String
    public var translatedText: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let model: String
    public var status: TranslationStatus
    public var errorMessage: String?
    public var latencyMs: Int?
    public var usage: TranslationUsage?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        originalText: String,
        translatedText: String = "",
        sourceLanguage: String = "auto",
        targetLanguage: String = "zh",
        model: String = "Hy-MT2",
        status: TranslationStatus = .idle,
        errorMessage: String? = nil,
        latencyMs: Int? = nil,
        usage: TranslationUsage? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.model = model
        self.status = status
        self.errorMessage = errorMessage
        self.latencyMs = latencyMs
        self.usage = usage
        self.timestamp = timestamp
    }
}
