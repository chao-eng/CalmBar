import Combine
import Foundation

@MainActor
public final class TranslationFeature: CalmFeature {
    public let id: FeatureID = .translation
    public let title: String = "AI 划词翻译"
    public let category: FeatureCategory = .productivity
    public let requiredPermissions: [FeaturePermissionRequirement] = []

    private let manager: TranslationManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "translation.clipboard",
                title: "翻译当前剪贴板",
                subtitle: "将剪贴板中的内容发送至 AI 翻译",
                action: { [weak self] in
                    self?.manager.translateFromClipboard()
                }
            ),
            FeatureCommand(
                id: "translation.history",
                title: "打开翻译历史记录",
                subtitle: "查看和搜索以往的 AI 翻译结果",
                action: {
                    TranslationHistoryWindowController.shared.show()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.translation",
            featureID: .translation,
            title: "AI 翻译",
            subtitle: manager.isTranslating ? "翻译中..." : (AppSettings.shared.translationEnabled ? "就绪 (双击⌘C)" : "已停用"),
            iconName: "character.bubble.fill",
            state: state,
            isHighlighted: manager.isTranslating
        )
    }

    public init(manager: TranslationManager = .shared) {
        self.manager = manager
        updateState()

        AppSettings.shared.$translationEnabled
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)

        manager.$isTranslating
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        if !AppSettings.shared.translationEnabled {
            state = .disabled
        } else if manager.isTranslating {
            state = .running
        } else {
            state = .enabled
        }
    }

    public func start() {
        manager.start()
        updateState()
    }

    public func stop() {
        manager.stop()
        state = .disabled
    }

    public func cleanup() {
        stop()
    }
}
