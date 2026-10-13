import Foundation
import Combine

@MainActor
public final class LaunchManagerFeature: CalmFeature {
    public let id: FeatureID = .launchManager
    public let title: String = "启动项与常驻服务"
    public let category: FeatureCategory = .system

    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .privilegedHelper,
            level: .optional,
            reason: "管理全局 LaunchAgents 与系统级 LaunchDaemons 需要特权助手支持"
        )
    ]

    @Published public private(set) var state: FeatureState = .enabled
    @Published public private(set) var crashLoopingCount: Int = 0

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "launchManager.open",
                title: "打开启动项与服务管理",
                action: {
                    LaunchManagerWindowController.shared.show()
                }
            ),
            FeatureCommand(
                id: "launchManager.crontab",
                title: "Crontab 计划任务",
                subtitle: "查看与配置系统及用户周期性定时指令",
                action: {
                    LaunchManagerWindowController.shared.show(initialTab: .crontab)
                }
            ),
            FeatureCommand(
                id: "launchManager.scanPorts",
                title: "查看本地监听端口与后台服务",
                action: {
                    LaunchManagerWindowController.shared.show(initialTab: .services)
                }
            ),
            FeatureCommand(
                id: "launchManager.refresh",
                title: "刷新所有自启项与服务状态",
                action: {
                    Task {
                        await LaunchManager.shared.refreshAll()
                    }
                }
            )
        ]
    }

    public init() {}

    public func start() {
        state = .running
        Task {
            await LaunchManager.shared.refreshAll()
            self.crashLoopingCount = LaunchManager.shared.crashLoopingItems.count
        }
    }

    public func stop() {
        state = .disabled
    }

    public func cleanup() {
        stop()
    }
}
