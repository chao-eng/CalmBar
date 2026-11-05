import AppKit
import Combine
import Foundation

/// AI API Gateway 功能入口：负责生命周期与命令注册
@MainActor
public final class AIGatewayFeature: CalmFeature {
    public let id: FeatureID = .aiGateway
    public let title: String = "AI 网关"
    public let category: FeatureCategory = .productivity
    public var requiredPermissions: [FeaturePermissionRequirement] { [] }

    @Published public private(set) var state: FeatureState = .disabled

    private let service: GatewayService
    private var cancellables = Set<AnyCancellable>()

    public init(service: GatewayService = .shared) {
        self.service = service
        updateState()

        service.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)

        AppSettings.shared.$aiGatewayEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "gateway.settings",
                title: "打开 AI 网关设置",
                subtitle: "配置渠道、模型别名与网关访问密钥",
                action: {
                    StatusBarManager.shared.openSettingsWindow(tab: .aiGateway)
                }
            ),
            FeatureCommand(
                id: "gateway.history",
                title: "打开网关请求历史",
                subtitle: "查看请求耗时、Token 用量与重试原因",
                action: {
                    GatewayHistoryWindowController.shared.show()
                }
            ),
            FeatureCommand(
                id: "gateway.toggle",
                title: "启用/停用 AI 网关",
                subtitle: "切换本地 OpenAI 兼容接口",
                action: {
                    AppSettings.shared.aiGatewayEnabled.toggle()
                }
            ),
            FeatureCommand(
                id: "gateway.copyEndpoint",
                title: "复制网关 Base URL",
                subtitle: "复制类似 http://127.0.0.1:8317/v1 的地址",
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(GatewayService.endpoint, forType: .string)
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        guard AppSettings.shared.aiGatewayEnabled else { return nil }
        return FeatureDashboardItem(
            id: "dashboard.gateway",
            featureID: .aiGateway,
            title: "AI 网关",
            subtitle: service.status.title,
            iconName: "arrow.triangle.branch",
            state: state,
            isHighlighted: service.status.isRunning
        )
    }

    public func start() {
        service.applyConfiguration()
        updateState()
    }

    public func stop() {
        service.shutdown()
        updateState()
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        guard AppSettings.shared.aiGatewayEnabled else {
            state = .disabled
            return
        }
        switch service.status {
        case .stopped, .starting:
            state = .enabled
        case .running:
            state = .running
        case .failed(let message):
            state = .failed(message)
        }
    }
}
