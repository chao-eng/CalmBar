import Combine
import Foundation

@MainActor
public final class ScrollFeature: CalmFeature {
    public let id: FeatureID = .scroll
    public let title: String = "滚轮方向解耦"
    public let category: FeatureCategory = .input
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .accessibility,
            level: .required,
            reason: "需要辅助功能权限以通过系统 CGEventTap 拦截并独立反转鼠标滚轮事件"
        )
    ]

    private let manager: ScrollReverserManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .disabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "scroll.toggle",
                title: "切换鼠标滚轮反转",
                subtitle: "反转外接鼠标滚轮方向，匹配触控板自然滚动",
                requiredPermission: .accessibility,
                action: {
                    AppSettings.shared.scrollReverserEnabled.toggle()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.scroll",
            featureID: .scroll,
            title: "滚轮方向解耦",
            subtitle: AppSettings.shared.scrollReverserEnabled ? "已启用" : "已停用",
            iconName: "computermouse.fill",
            state: state,
            isHighlighted: AppSettings.shared.scrollReverserEnabled
        )
    }

    public init(manager: ScrollReverserManager = .shared) {
        self.manager = manager
        updateState()

        Publishers.CombineLatest(manager.$isRunning, manager.$hasAccessibilityPermission)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        guard manager.hasAccessibilityPermission else {
            state = .needsPermission
            return
        }
        if AppSettings.shared.scrollReverserEnabled {
            state = manager.isRunning ? .running : .enabled
        } else {
            state = .disabled
        }
    }

    public func start() {
        manager.start()
        updateState()
    }

    public func stop() {
        manager.stop()
        updateState()
    }

    public func cleanup() {
        manager.stop()
    }
}
