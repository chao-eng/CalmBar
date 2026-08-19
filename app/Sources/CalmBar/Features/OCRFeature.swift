import Combine
import Foundation

@MainActor
public final class OCRFeature: CalmFeature {
    public let id: FeatureID = .ocr
    public let title: String = "屏幕识字"
    public let category: FeatureCategory = .productivity
    public let requiredPermissions: [FeaturePermissionRequirement] = [
        FeaturePermissionRequirement(
            type: .screenRecording,
            level: .required,
            reason: "需要屏幕录制权限以捕获选区画面进行文字与二维码识别"
        )
    ]

    private let manager: OCRManager
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .enabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "ocr.capture",
                title: "开始屏幕选区识字",
                subtitle: "框选屏幕区域离线识别文字与二维码",
                requiredPermission: .screenRecording,
                action: { [weak self] in
                    self?.manager.startCaptureAndRecognize()
                }
            ),
            FeatureCommand(
                id: "ocr.history",
                title: "打开 OCR 历史记录",
                subtitle: "查看和复制历史识别结果",
                action: {
                    OCRHistoryWindowController.shared.show()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.ocr",
            featureID: .ocr,
            title: "屏幕识字",
            subtitle: manager.isRecognizing ? "识别中" : "就绪",
            iconName: "text.viewfinder",
            state: state,
            isHighlighted: manager.isRecognizing
        )
    }

    public init(manager: OCRManager = .shared) {
        self.manager = manager
        updateState()

        PermissionManager.shared.$screenRecordingGranted
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)

        manager.$isRecognizing
            .sink { [weak self] _ in
                self?.updateState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        updateState()
    }

    private func updateState() {
        if manager.isRecognizing {
            state = .running
        } else if !PermissionManager.shared.screenRecordingGranted {
            state = .needsPermission
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
