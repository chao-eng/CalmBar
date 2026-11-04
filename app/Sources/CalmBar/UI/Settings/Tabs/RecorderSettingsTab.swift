import AppKit
import SwiftUI
import CalmBarKit

// MARK: - 屏幕录制设置（PRD UC-R01 ~ UC-R04）

public struct RecorderSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeatureMasterToggleCard(
                    icon: SettingsTab.recorder.icon,
                    iconColors: SettingsTab.recorder.gradientColors,
                    title: "启用屏幕录制",
                    activeSubtitle: "已激活 · 可从面板工具、快捷键 ⌥⌘R 或录制设置随时开始录制",
                    inactiveSubtitle: "已停用 · 录制入口隐藏，正在进行的录制会自动保存并停止",
                    isEnabled: $settings.screenRecorderEnabled
                )

                GroupBox(label: Label("画质与编码", systemImage: "film")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("画质")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Picker("画质", selection: $settings.recorderQuality) {
                                ForEach(RecorderQuality.allCases) { quality in
                                    Text(quality.title).tag(quality)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 240)
                            .focusable(false)
                            .focusEffectDisabled()
                        }

                        HStack {
                            Text("帧率")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Picker("帧率", selection: $settings.recorderFPS) {
                                Text("24 fps").tag(24)
                                Text("30 fps").tag(30)
                                Text("60 fps").tag(60)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 240)
                            .focusable(false)
                            .focusEffectDisabled()
                        }

                        HStack {
                            Text("编码格式")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Picker("编码格式", selection: $settings.recorderCodec) {
                                ForEach(RecorderCodec.allCases) { codec in
                                    Text(codec.title).tag(codec)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 240)
                            .focusable(false)
                            .focusEffectDisabled()
                        }

                        Toggle("录制时包含鼠标指针", isOn: $settings.recorderIncludeCursor)
                            .font(.system(size: 12.5, weight: .medium))

                        Text("HEVC 在同画质下体积更小，但部分播放器与剪辑软件兼容性不如 H.264。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                .disabled(!settings.screenRecorderEnabled)
                .opacity(settings.screenRecorderEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("声音采集", systemImage: "waveform.badge.mic")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("录制系统声音", isOn: $settings.recorderCaptureSystemAudio)
                            .font(.system(size: 12.5, weight: .medium))
                        Toggle("录制麦克风", isOn: $settings.recorderCaptureMicrophone)
                            .font(.system(size: 12.5, weight: .medium))

                        Text("系统声音与麦克风分别写入独立音轨，便于后期单独调节；首次使用麦克风时系统会请求权限，若拒绝授权，本次录制仅保存系统声音。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(8)
                }
                .disabled(!settings.screenRecorderEnabled)
                .opacity(settings.screenRecorderEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("保存位置与倒计时", systemImage: "folder")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(settings.recorderSaveDirectory.isEmpty ? "默认：~/Movies/CalmBar Recordings" : settings.recorderSaveDirectory)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("选择…") {
                                chooseDirectory()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("默认") {
                                settings.recorderSaveDirectory = ""
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(settings.recorderSaveDirectory.isEmpty)

                            Button("打开文件夹") {
                                recorder.openRecordingsFolder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Divider()

                        HStack {
                            Text("开始前倒计时")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Picker("开始前倒计时", selection: $settings.recorderCountdown) {
                                Text("立即").tag(0)
                                Text("3 秒").tag(3)
                                Text("5 秒").tag(5)
                                Text("10 秒").tag(10)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 260)
                            .focusable(false)
                            .focusEffectDisabled()
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.screenRecorderEnabled)
                .opacity(settings.screenRecorderEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("录制状态", systemImage: "record.circle")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(recorder.state.isActive ? Color.red : Color.secondary)
                                .frame(width: 7, height: 7)
                            Text(stateDescription)
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()

                            if recorder.isRecording {
                                Button("停止并保存") {
                                    recorder.stop()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button("开始录制") {
                                    RecorderPreparationWindowController.shared.show()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!settings.screenRecorderEnabled)
                            }
                        }

                        if let lastError = recorder.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.system(size: 11.5))
                                .foregroundColor(.orange)
                                .lineSpacing(2)
                        }
                    }
                    .padding(8)
                }

                if !recorder.pendingPartials.isEmpty {
                    GroupBox(label: Label("发现未完成的录制", systemImage: "exclamationmark.triangle")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("这些临时文件可能因异常退出未收尾。可尝试恢复为可播放视频，或移入废纸篓。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)

                            ForEach(recorder.pendingPartials, id: \.self) { url in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.badge.clock")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    Button("尝试恢复") {
                                        recorder.repairPartial(url)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Button("移入废纸篓") {
                                        recorder.discardPartial(url)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Button("忽略") {
                                        recorder.ignorePartial(url)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                GroupBox(label: Label("最近录制", systemImage: "clock.arrow.circlepath")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if recorder.recentRecordings.isEmpty {
                            Text("暂无录制记录")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(recorder.recentRecordings.prefix(6)) { recording in
                                HStack(spacing: 8) {
                                    Image(systemName: "film")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(recording.fileName)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text("\(recording.formattedDuration) · \(recording.formattedSize)")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer(minLength: 6)
                                    Button("访达显示") {
                                        recorder.reveal(recording)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Button("移除记录") {
                                        recorder.delete(recording)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Divider()

                        Button("打开录制文件夹") {
                            recorder.openRecordingsFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }

    private var stateDescription: String {
        switch recorder.state {
        case .idle: return "待命，尚未开始录制"
        case .preparing: return "正在准备录制参数"
        case .countdown: return "\(recorder.countdownRemaining) 秒后开始录制"
        case .recording: return "录制中 · \(recorder.formattedElapsed)"
        case .paused: return "已暂停 · \(recorder.formattedElapsed)"
        case .finalizing: return "正在保存录制文件…"
        case .done: return "已保存 · \(recorder.formattedElapsed)"
        case .failed: return "录制失败"
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择录制保存目录"
        panel.prompt = "使用此目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = recorder.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.recorderSaveDirectory = url.path
        }
    }
}
