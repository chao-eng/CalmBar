import Foundation
import Combine
import AppKit

@MainActor
public final class TranslationManager: ObservableObject {
    public static let shared = TranslationManager()

    @Published public private(set) var isTranslating: Bool = false
    @Published public private(set) var currentStreamText: String = ""
    @Published public private(set) var currentItem: TranslationItem?

    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupDoubleCopyBinding()
    }

    private func setupDoubleCopyBinding() {
        DoubleCopyMonitor.shared.onDoubleCopyDetected = { [weak self] text in
            guard AppSettings.shared.translationEnabled,
                  AppSettings.shared.translationDoubleCopyEnabled else {
                return
            }
            self?.translate(text: text)
        }
    }

    public func start() {
        if AppSettings.shared.translationEnabled && AppSettings.shared.translationDoubleCopyEnabled {
            DoubleCopyMonitor.shared.start(interval: AppSettings.shared.translationDoubleCopyInterval)
        }
    }

    public func stop() {
        DoubleCopyMonitor.shared.stop()
        currentTask?.cancel()
        currentTask = nil
        isTranslating = false
    }

    public func translate(
        text: String,
        targetLanguage: TranslationLanguage? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let settings = AppSettings.shared
        let target = targetLanguage ?? TranslationLanguage.find(byCode: settings.translationTargetLanguageCode)

        var item = TranslationItem(
            originalText: trimmed,
            translatedText: "",
            sourceLanguage: "auto",
            targetLanguage: target.code,
            model: settings.translationModel,
            status: .loading,
            timestamp: Date()
        )

        self.currentItem = item
        self.currentStreamText = ""
        self.isTranslating = true

        // 立即展示/更新悬浮窗
        TranslationToastWindowController.shared.show(item: item)

        currentTask?.cancel()
        currentTask = Task { @MainActor [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let result = try await TranslationService.shared.translateStream(
                    text: trimmed,
                    targetLanguage: target,
                    baseURL: settings.translationAPIBaseURL,
                    apiKey: settings.translationAPIKey.isEmpty ? nil : settings.translationAPIKey,
                    model: settings.translationModel,
                    customPromptTemplate: settings.translationCustomPrompt.isEmpty ? nil : settings.translationCustomPrompt
                ) { chunk in
                    Task { @MainActor in
                        TranslationManager.shared.handleStreamChunk(chunk)
                    }
                }

                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                guard !Task.isCancelled else { return }

                item.translatedText = result.fullText
                item.status = .completed
                item.latencyMs = elapsed
                item.usage = result.usage

                self?.currentItem = item
                self?.isTranslating = false
                self?.currentStreamText = result.fullText

                TranslationToastWindowController.shared.update(item: item)
                TranslationHistoryManager.shared.add(item: item)
            } catch {
                guard !Task.isCancelled else { return }
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

                item.status = .failed
                item.errorMessage = error.localizedDescription
                item.latencyMs = elapsed

                self?.currentItem = item
                self?.isTranslating = false

                TranslationToastWindowController.shared.update(item: item)
                TranslationHistoryManager.shared.add(item: item)
            }
        }
    }

    public func handleStreamChunk(_ chunk: String) {
        self.currentStreamText = chunk
        self.currentItem?.status = .streaming
        self.currentItem?.translatedText = chunk
        if let item = self.currentItem {
            TranslationToastWindowController.shared.update(item: item)
        }
    }

    public func translateFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translate(text: text)
        }
    }
}
