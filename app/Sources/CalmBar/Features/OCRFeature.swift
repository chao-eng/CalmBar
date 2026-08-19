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
                requiredPermission: .screenRecording,
                action: { [weak self] in
                    self?.manager.startCaptureAndRecognize()
                }
            )
        ]
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
