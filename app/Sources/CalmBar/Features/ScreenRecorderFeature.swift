import Combine
import Foundation

@MainActor
public final class ScreenRecorderFeature: CalmFeature {
    public let id: FeatureID = .screenRecorder
    public let title: String = "屏幕录制"
    public let category: FeatureCategory = .productivity

    public var requiredPermissions: [FeaturePermissionRequirement] {
        guard AppSettings.shared.screenRecorderEnabled else { return [] }
        return [
            FeaturePermissionRequirement(
                type: .screenRecording,
                level: .required,
                reason: "录制屏幕与系统声音需要屏幕录制权限"
            )
        ]
    }

    private let recorder: ScreenRecorderService
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "recorder.start",
                title: "开始屏幕录制",
                subtitle: "沿用上次配置，打开录制准备面板",
                requiredPermission: .screenRecording,
                action: {
                    RecorderPreparationWindowController.shared.show()
                }
            ),
            FeatureCommand(
                id: "recorder.toggle",
                title: "开始/停止录制",
                subtitle: "录制中立即停止并保存，否则打开准备面板",
                requiredPermission: .screenRecording,
                action: {
                    if ScreenRecorderService.shared.isRecording {
                        ScreenRecorderService.shared.stop()
                    } else {
                        RecorderPreparationWindowController.shared.show()
                    }
                }
            ),
            FeatureCommand(
                id: "recorder.openFolder",
                title: "打开录制文件夹",
                subtitle: "在访达中显示录制保存目录",
                action: {
                    ScreenRecorderService.shared.openRecordingsFolder()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.recorder",
            featureID: .screenRecorder,
            title: "屏幕录制",
            subtitle: recorder.isRecording ? recorder.formattedElapsed : "待命",
            iconName: "record.circle",
            state: state,
            isHighlighted: recorder.isRecording
        )
    }

    public init(recorder: ScreenRecorderService = .shared) {
        self.recorder = recorder
        updateState()

        AppSettings.shared.$screenRecorderEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.recorder.stop()
                }
                self?.updateState()
            }
            .store(in: &cancellables)

        recorder.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        guard AppSettings.shared.screenRecorderEnabled else {
            state = .disabled
            return
        }
        state = recorder.isRecording ? .running : .enabled
    }

    public func start() {
        updateState()
    }

    public func stop() {
        recorder.stop()
        updateState()
    }

    public func cleanup() {
        recorder.stop()
    }
}
