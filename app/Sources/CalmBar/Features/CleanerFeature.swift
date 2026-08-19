import Combine
import Foundation

@MainActor
public final class CleanerFeature: CalmFeature {
    public let id: FeatureID = .cleaner
    public let title: String = "应用与缓存清理"
    public let category: FeatureCategory = .cleanup
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .fullDiskAccess,
            level: .advanced,
            reason: "深层扫描应用残留与完整缓存需要完全磁盘访问权限"
        )
    ]

    private let manager: CleanerManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "cleaner.scanDev",
                title: "扫描开发工具链缓存",
                action: { [weak self] in
                    self?.manager.refreshDevCaches()
                }
            ),
            FeatureCommand(
                id: "cleaner.scanApps",
                title: "扫描已安装应用",
                action: { [weak self] in
                    self?.manager.refreshAllApps()
                }
            )
        ]
    }

    public init(manager: CleanerManager = .shared) {
        self.manager = manager
        updateState()

        Publishers.CombineLatest3(manager.$isScanningApps, manager.$isScanningDev, manager.$isScanningWorkspaces)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    private func updateState() {
        if manager.isScanningApps || manager.isScanningDev || manager.isScanningWorkspaces {
            state = .running
        } else {
            state = .enabled
        }
    }

    public func start() {
        updateState()
    }

    public func stop() {
        state = .disabled
    }

    public func cleanup() {}
}
