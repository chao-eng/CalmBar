import Combine
import Foundation

@MainActor
public final class AudioFeature: CalmFeature {
    public let id: FeatureID = .audio
    public let title: String = "音频路由与混音"
    public let category: FeatureCategory = .system
    public let requiredPermissions: [FeaturePermissionRequirement] = []

    private let mixer: AudioMixerService
    private var cancellables = Set<AnyCancellable>()

    @Published public private(set) var state: FeatureState = .disabled

    public var commands: [FeatureCommand] {
        [
            FeatureCommand(
                id: "audio.openMixer",
                title: "打开音频混音器",
                subtitle: "按应用调节音量与输出设备",
                action: {
                    AudioMixerWindowController.shared.show()
                }
            ),
            FeatureCommand(
                id: "audio.toggleOutputMute",
                title: "静音全部输出",
                subtitle: "切换系统默认输出设备的静音状态",
                action: {
                    AudioMixerService.shared.toggleSystemMute()
                }
            )
        ]
    }

    public var dashboardItem: FeatureDashboardItem? {
        FeatureDashboardItem(
            id: "dashboard.audio",
            featureID: .audio,
            title: "音频输出",
            subtitle: mixer.systemOutputName,
            iconName: "speaker.wave.2.fill",
            state: state
        )
    }

    public init() {
        self.mixer = AudioMixerService.shared
        updateState()

        AppSettings.shared.$audioHubEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.mixer.start()
                } else {
                    self.mixer.stop()
                }
                self.updateState()
            }
            .store(in: &cancellables)

        mixer.$isRunning
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
        guard AppSettings.shared.audioHubEnabled else {
            state = .disabled
            return
        }
        guard AudioMixerService.isSupported else {
            state = .unavailable
            return
        }
        state = mixer.isRunning ? .running : (mixer.lastError == nil ? .enabled : .failed(mixer.lastError ?? ""))
    }

    public func start() {
        if AppSettings.shared.audioHubEnabled {
            mixer.start()
        }
        updateState()
    }

    public func stop() {
        mixer.stop()
        updateState()
    }

    public func cleanup() {
        mixer.stop()
    }
}
