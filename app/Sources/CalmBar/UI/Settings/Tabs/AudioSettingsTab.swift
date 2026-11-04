import AppKit
import SwiftUI
import CalmBarKit

// MARK: - 音频控制设置（PRD UC-A01 ~ UC-A04）

public struct AudioSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var mixer = AudioMixerService.shared
    @State private var bundleInput = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeatureMasterToggleCard(
                    icon: SettingsTab.audio.icon,
                    iconColors: SettingsTab.audio.gradientColors,
                    title: "按应用路由与混音音频",
                    activeSubtitle: "已激活 · 可按应用调节音量与静音，并把声音发送到不同输出设备",
                    inactiveSubtitle: "已停用 · 应用保持系统原生播放路径，不进行任何接管",
                    isEnabled: $settings.audioHubEnabled
                )

                GroupBox(label: Label("音量与增强", systemImage: "speaker.wave.3.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("允许把应用音量增强到 100% 以上", isOn: $settings.audioBoostEnabled)
                            .font(.system(size: 12.5, weight: .medium))

                        HStack {
                            Text("增强上限")
                                .font(.system(size: 12.5, weight: .medium))
                            Slider(
                                value: Binding(
                                    get: { Double(settings.audioBoostMaxPercent) },
                                    set: { settings.audioBoostMaxPercent = Int($0.rounded()) }
                                ),
                                in: 100...200,
                                step: 5
                            )
                            .frame(width: 220)
                            .disabled(!settings.audioBoostEnabled)
                            Text("\(settings.audioBoostMaxPercent)%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 46, alignment: .trailing)
                        }

                        Text("增强仅供临时放大安静的应用；过高的增益可能造成失真，请谨慎使用。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                .disabled(!settings.audioHubEnabled)
                .opacity(settings.audioHubEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("输出路由", systemImage: "arrow.triangle.branch")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("允许把应用声音单独发送到其他输出设备", isOn: $settings.audioRoutingEnabled)
                            .font(.system(size: 12.5, weight: .medium))

                        HStack {
                            Text("最多同时路由应用数")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Stepper(
                                value: $settings.audioRoutingMaxApps,
                                in: 1...10
                            ) {
                                Text("\(settings.audioRoutingMaxApps) 个")
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 54, alignment: .trailing)
                            }
                            .disabled(!settings.audioRoutingEnabled)
                        }

                        Divider()

                        HStack {
                            Text("路由失败时")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Picker("路由失败时", selection: $settings.audioRoutingFallback) {
                                ForEach(AudioRoutingFallback.allCases) { fallback in
                                    Text(fallback.title).tag(fallback)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 320)
                            .focusable(false)
                            .focusEffectDisabled()
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.audioHubEnabled)
                .opacity(settings.audioHubEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("当前状态", systemImage: "waveform")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(mixer.isRunning ? Color.green : Color.secondary)
                                .frame(width: 7, height: 7)
                            Text(mixer.statusSummary)
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Text("系统输出：\(mixer.systemOutputName)")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let lastError = mixer.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.system(size: 11.5))
                                .foregroundColor(.orange)
                                .lineSpacing(2)
                        }

                        HStack(spacing: 8) {
                            Button("打开音频控制窗口") {
                                AudioMixerWindowController.shared.show()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!settings.audioHubEnabled)

                            Button("恢复全部默认") {
                                mixer.resetAllApps()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!mixer.isRunning)
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("不接管的音频", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("系统提示音、来电与通话音频属于受保护音频，CalmBar 始终不会接管，以免影响系统提醒与通话质量。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        Text("如需排除某个应用，可添加其 Bundle ID：")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("例如 com.apple.Music", text: $bundleInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Button("添加") {
                                addExcludedBundle()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(trimmedBundleInput.isEmpty)
                        }

                        if !settings.audioExcludedBundleIDs.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(settings.audioExcludedBundleIDs, id: \.self) { bundleID in
                                    HStack(spacing: 4) {
                                        Text(bundleID)
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                        Button {
                                            settings.audioExcludedBundleIDs.removeAll { $0 == bundleID }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("移除排除项")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.audioHubEnabled)
                .opacity(settings.audioHubEnabled ? 1.0 : 0.6)
            }
            .padding(16)
        }
    }

    private var trimmedBundleInput: String {
        bundleInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addExcludedBundle() {
        let value = trimmedBundleInput
        guard !value.isEmpty,
              !settings.audioExcludedBundleIDs.contains(value) else { return }
        settings.audioExcludedBundleIDs.append(value)
        bundleInput = ""
        mixer.refresh()
    }
}
