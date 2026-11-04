import SwiftUI

// MARK: - 声音分区（PRD §5.5：最多 4 行真实应用，超出请打开混音窗口）

struct AudioSectionView: View {
    var onOpenMixer: (() -> Void)?

    @ObservedObject private var service = AudioMixerService.shared
    @ObservedObject private var settings = AppSettings.shared

    private var rows: [AudioAppInfo] {
        service.displayRows(limit: 4)
    }

    var body: some View {
        Group {
            if !service.isRunning {
                disabledState
            } else if rows.isEmpty {
                PopoverEmptyState(
                    icon: "waveform.slash",
                    title: "暂无应用发声",
                    detail: "播放声音后，这里会按应用列出音量",
                    accessibilityValue: "声音"
                )
            } else {
                VStack(spacing: 6) {
                    VStack(spacing: 6) {
                        ForEach(rows) { app in
                            audioRow(app)
                        }
                    }

                    HStack(spacing: 4) {
                        Text("最多显示 4 行，更多应用请打开混音窗口")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 2)

                        if let onOpenMixer {
                            Button("混音窗口") {
                                onOpenMixer()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(PopoverPalette.audioAccent)
                            .help("打开音频控制窗口，管理全部应用")
                            .accessibilityLabel("打开混音窗口")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: PopoverLayout.contentWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: 未启用

    private var disabledState: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text(service.lastError ?? "音频控制未启用")
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)

            Text("开启后可按应用调节音量、静音与输出设备")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)

            Button("开启音频控制") {
                settings.audioHubEnabled = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
            .disabled(!AudioMixerService.isSupported)
            .help(AudioMixerService.isSupported ? "在任意应用上按应用调节音频" : "当前系统版本不支持进程级音频接管")
            .accessibilityLabel("开启音频控制")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: 单行

    private func audioRow(_ app: AudioAppInfo) -> some View {
        HStack(spacing: 6) {
            iconView(for: app)
                .frame(width: 18, height: 18)

            Text(app.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("跟随系统") {
                    service.setOutputDevice(nil, for: app.id)
                }
                Divider()
                ForEach(service.outputDevices) { device in
                    Button(device.name) {
                        service.setOutputDevice(device.uid, for: app.id)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(deviceName(for: app))
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .frame(width: 70, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(PopoverPalette.surfaceWell)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 70)
            .disabled(app.isProtected || !settings.audioRoutingEnabled)
            .help("切换「\(app.name)」的输出设备")
            .accessibilityLabel("\(app.name) 输出设备，\(deviceName(for: app))")

            Slider(
                value: Binding(
                    get: { min(app.volume, service.boostUpperBoundGain) },
                    set: { service.setVolume($0, for: app.id) }
                ),
                in: 0...service.boostUpperBoundGain
            )
            .controlSize(.mini)
            .frame(width: 44)
            .tint(PopoverPalette.audioAccent)
            .disabled(app.isProtected)
            .opacity(app.isMuted ? 0.45 : 1)
            .help("「\(app.name)」音量")
            .accessibilityLabel("\(app.name) 音量")

            Text("\(Int((min(app.volume, service.boostUpperBoundGain) * 100).rounded()))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button {
                service.toggleMute(for: app.id)
            } label: {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(app.isMuted ? Color.secondary : Color.primary)
                    .frame(width: 16, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.isProtected)
            .help(app.isMuted ? "取消静音" : "静音")
            .accessibilityLabel("\(app.name) 静音")
            .accessibilityValue(app.isMuted ? "已静音" : "未静音")
        }
        .frame(height: 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(app.name) 音量行")
        .accessibilityValue("\(Int((app.volume * 100).rounded()))%")
    }

    @ViewBuilder
    private func iconView(for app: AudioAppInfo) -> some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PopoverPalette.audioAccent.opacity(0.14))
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(PopoverPalette.audioAccent)
                }
        }
    }

    private func deviceName(for app: AudioAppInfo) -> String {
        guard let uid = app.outputDeviceUID,
              let device = service.outputDevices.first(where: { $0.uid == uid }) else {
            return "跟随系统"
        }
        return device.name
    }
}
