import Combine
import Foundation

// MARK: - 局域网互传功能接入

@MainActor
public final class LANShareFeature: CalmFeature {
    public let id: FeatureID = .lanShare
    public let title: String = "局域网互传"
    public let category: FeatureCategory = .productivity
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(type: .localNetwork, level: .optional, reason: "局域网设备访问")
    ]

    private let service: LANShareService
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .disabled

    public var commands: [FeatureCommand] {
        var items: [FeatureCommand] = [
            FeatureCommand(
                id: "lanShare.window",
                title: "打开局域网互传",
                subtitle: "查看分享链接、已分享内容与传输进度",
                action: {
                    LANShareWindowController.shared.show()
                }
            )
        ]

        if service.isRunning {
            items.append(FeatureCommand(
                id: "lanShare.copyLink",
                title: "复制分享链接",
                subtitle: service.shareURL,
                action: { [weak self] in
                    self?.service.copyShareLink()
                }
            ))
            items.append(FeatureCommand(
                id: "lanShare.stop",
                title: "停止局域网互传",
                subtitle: "关闭监听端口并清空当前会话",
                action: {
                    AppSettings.shared.lanShareEnabled = false
                }
            ))
        } else {
            items.append(FeatureCommand(
                id: "lanShare.start",
                title: "开启局域网互传",
                subtitle: "在同一 Wi-Fi 下与手机、平板互传文件",
                action: {
                    AppSettings.shared.lanShareEnabled = true
                }
            ))
        }
        return items
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.lanShare",
            featureID: .lanShare,
            title: "局域网互传",
            subtitle: dashboardSubtitle,
            iconName: "wifi",
            state: state,
            isHighlighted: service.isRunning && !service.transfers.isEmpty
        )
    }

    public init(service: LANShareService = .shared) {
        self.service = service
        updateState()

        AppSettings.shared.$lanShareEnabled
            .sink { [weak self] _ in self?.updateState() }
            .store(in: &cancellables)

        service.$status
            .sink { [weak self] _ in self?.updateState() }
            .store(in: &cancellables)

        service.$sessionCount
            .sink { [weak self] _ in self?.updateState() }
            .store(in: &cancellables)
    }

    private var dashboardSubtitle: String {
        switch service.status {
        case .running:
            return service.sessionCount > 0 ? "已开启 · \(service.sessionCount) 台设备在线" : "已开启 · 等待设备访问"
        case .starting:
            return "正在启动服务"
        case .restricted:
            return "未连接局域网"
        case .failed:
            return service.lastError?.userMessage ?? "启动失败"
        case .stopped:
            return AppSettings.shared.lanShareEnabled ? "已停用" : "未开启"
        }
    }

    private func updateState() {
        if !AppSettings.shared.lanShareEnabled {
            state = .disabled
            return
        }
        switch service.status {
        case .stopped:
            state = .disabled
        case .starting, .running:
            state = .running
        case .restricted:
            state = .degraded
        case .failed:
            state = .failed(service.lastError?.userMessage ?? "服务启动失败")
        }
    }

    public func refreshState() {
        updateState()
    }

    public func start() {
        AppSettings.shared.lanShareEnabled = true
    }

    public func stop() {
        AppSettings.shared.lanShareEnabled = false
        service.stop()
        state = .disabled
    }

    public func cleanup() {
        service.stop()
    }
}
