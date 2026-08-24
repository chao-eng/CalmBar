import SwiftUI
import CalmBarKit

public struct NoTunesSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var noTunes = NoTunesManager.shared

    @State private var terminateAlertMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .noTunes)

                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.noTunes.icon,
                    iconColors: SettingsTab.noTunes.gradientColors,
                    title: "Apple Music 自动启动拦截防护",
                    activeSubtitle: "已激活 · 连接蓝牙耳机或按键时阻止 Apple Music 强行弹起 (已拦截 \(noTunes.blockedCount) 次)",
                    inactiveSubtitle: "已停用 · 允许 Apple Music / iTunes 随系统按键与外设正常启动",
                    isEnabled: $settings.noTunesEnabled
                )

                // 1. 防护操作与拦截统计
                GroupBox(label: Label("防护操作与拦截统计", systemImage: "shield.checkerboard")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("开启拦截时自动关闭当前已在运行的 Music / iTunes", isOn: $settings.noTunesTerminateOnEnable)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("拦截统计")
                                    .font(.system(size: 11, weight: .medium))
                                Text("累计已拦截 \(noTunes.blockedCount) 次 · 最近: \(formattedDate(noTunes.lastBlockedDate))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("一键关闭后台 Music") {
                                let killed = noTunes.terminateRunningMusicApps()
                                if killed > 0 {
                                    terminateAlertMessage = "已成功强制关闭 \(killed) 个正在运行的 Music / iTunes 进程"
                                } else {
                                    terminateAlertMessage = "当前没有正在运行的 Apple Music / iTunes 进程"
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.noTunesEnabled)
                .opacity(settings.noTunesEnabled ? 1.0 : 0.6)

                // 2. 替代目标配置
                GroupBox(label: Label("拦截后替代启动 (Replacement)", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当拦截 Apple Music 启动后，可自动无缝拉起你常用的第三方音乐应用或网页：")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Picker("替代模式", selection: $settings.noTunesReplacementType) {
                            ForEach(NoTunesReplacementType.allCases) { type in
                                Text(type.titleZH).tag(type)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        if settings.noTunesReplacementType == .app {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("快速填入常用应用预设:")
                                    .font(.system(size: 11, weight: .medium))

                                HStack(spacing: 6) {
                                    presetAppButton(title: "Spotify", path: "/Applications/Spotify.app")
                                    presetAppButton(title: "网易云音乐", path: "/Applications/NeteaseMusic.app")
                                    presetAppButton(title: "QQ 音乐", path: "/Applications/QQMusic.app")
                                    presetAppButton(title: "TIDAL", path: "/Applications/TIDAL.app")
                                    presetAppButton(title: "foobar2000", path: "/Applications/foobar2000.app")
                                }

                                HStack(spacing: 8) {
                                    TextField("应用路径 (例如 /Applications/Spotify.app)", text: $settings.noTunesReplacementTarget)
                                        .textFieldStyle(.roundedBorder)

                                    Button("浏览...") {
                                        selectApplicationPath()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("测试启动") {
                                        noTunes.launchReplacement()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(settings.noTunesReplacementTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        } else if settings.noTunesReplacementType == .url {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("快速填入网页播放器预设:")
                                    .font(.system(size: 11, weight: .medium))

                                HStack(spacing: 6) {
                                    presetUrlButton(title: "YouTube Music", url: "https://music.youtube.com")
                                    presetUrlButton(title: "Spotify Web", url: "https://open.spotify.com")
                                    presetUrlButton(title: "SoundCloud", url: "https://soundcloud.com")
                                    presetUrlButton(title: "Bilibili 音乐", url: "https://www.bilibili.com")
                                }

                                HStack(spacing: 8) {
                                    TextField("网页 URL (例如 https://music.youtube.com)", text: $settings.noTunesReplacementTarget)
                                        .textFieldStyle(.roundedBorder)

                                    Button("测试打开") {
                                        noTunes.launchReplacement()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(settings.noTunesReplacementTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.noTunesEnabled)
                .opacity(settings.noTunesEnabled ? 1.0 : 0.6)

                // 3. 原理解释
                GroupBox(label: Label("功能说明", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **蓝牙耳机防流氓唤醒**：macOS 默认在 AirPods / 蓝牙耳机重新连接或误触耳机柄时强制启动 Apple Music，开启本功能可彻底根除该困扰。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("• **轻量无感知**：仅在系统收到应用启动通知时进行毫秒级判断，不轮询进程，CPU 占用为 0%。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
        .alert(item: Binding<AlertItem?>(
            get: { terminateAlertMessage.map { AlertItem(message: $0) } },
            set: { _ in terminateAlertMessage = nil }
        )) { item in
            Alert(title: Text("提示"), message: Text(item.message), dismissButton: .default(Text("好的")))
        }
    }

    private func presetAppButton(title: String, path: String) -> some View {
        Button(title) {
            settings.noTunesReplacementTarget = path
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func presetUrlButton(title: String, url: String) -> some View {
        Button(title) {
            settings.noTunesReplacementTarget = url
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func selectApplicationPath() {
        let panel = NSOpenPanel()
        panel.title = "选择替代音乐播放器应用程序"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.noTunesReplacementTarget = url.path
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "暂无" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
