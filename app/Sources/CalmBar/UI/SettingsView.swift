import SwiftUI
import CalmBarKit

public enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case thermal
    case menuBar
    case scroll
    case noTunes
    case gatekeeper
    case general

    public var id: String { rawValue }
}

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var noTunes = NoTunesManager.shared

    @ObservedObject private var statusBarManager = StatusBarManager.shared

    @State private var isInstallingHelper = false
    @State private var helperMessage: String?
    @State private var terminateAlertMessage: String?

    public init() {}

    public var body: some View {
        TabView(selection: $statusBarManager.selectedSettingsTab) {
            thermalTab
                .tabItem {
                    Label("硬件温控", systemImage: "flame")
                }
                .tag(SettingsTab.thermal)

            menuBarTab
                .tabItem {
                    Label("菜单栏收纳", systemImage: "menubar.rectangle")
                }
                .tag(SettingsTab.menuBar)

            scrollTab
                .tabItem {
                    Label("滚动手势", systemImage: "computermouse")
                }
                .tag(SettingsTab.scroll)

            noTunesTab
                .tabItem {
                    Label("音乐拦截", systemImage: "music.note")
                }
                .tag(SettingsTab.noTunes)

            GatekeeperUnlockerView()
                .tabItem {
                    Label("应用授权", systemImage: "lock.shield")
                }
                .tag(SettingsTab.gatekeeper)

            generalTab
                .tabItem {
                    Label("通用设置", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
        }
        .frame(width: 550, height: 540)
        .padding(16)
    }

    // MARK: - Thermal Tab
    private var thermalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("特权驱动与控制权限", systemImage: "lock.shield")) {
                    HStack {
                        Image(systemName: thermal.isFanControlAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(thermal.isFanControlAuthorized ? .green : .orange)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(thermal.isFanControlAuthorized ? "SMC 风扇控制特权已就绪" : "需要特权助手以修改风扇转速")
                                .font(.system(size: 13, weight: .semibold))
                            Text(thermal.isFanControlAuthorized ? "当前具备向 SMC 写入转速与模式的完整特权。" : "macOS 安全机制要求特权后台服务 (LaunchDaemon) 才能写入 SMC 寄存器。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !thermal.isFanControlAuthorized {
                            Button("一键激活...") {
                                isInstallingHelper = true
                                helper.requestInstallHelper { success, err in
                                    isInstallingHelper = false
                                    if success {
                                        thermal.checkAuthorization()
                                    } else {
                                        helperMessage = err
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("温控调控模式", systemImage: "fanblades")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("调控模式", selection: $settings.fanPreset) {
                            ForEach(FanPreset.allCases) { preset in
                                Text(preset.titleZH).tag(preset)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .padding(.vertical, 4)

                        if settings.fanPreset == .smart {
                            Divider()
                            Text("智能温控加速曲线参数")
                                .font(.system(size: 12, weight: .semibold))

                            VStack(spacing: 8) {
                                HStack {
                                    Text("起始加速温度:")
                                        .frame(width: 110, alignment: .leading)
                                    Slider(value: $settings.smartStartTemp, in: 40...75, step: 1)
                                    Text("\(Int(settings.smartStartTemp))°C")
                                        .frame(width: 45, alignment: .trailing)
                                        .font(.system(.body, design: .monospaced))
                                }
                                HStack {
                                    Text("满速运行温度:")
                                        .frame(width: 110, alignment: .leading)
                                    Slider(value: $settings.smartFullTemp, in: 70...95, step: 1)
                                    Text("\(Int(settings.smartFullTemp))°C")
                                        .frame(width: 45, alignment: .trailing)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                            Text("低于起始温度时保持最低静音转速，达到满速温度时全速散热，中间区域线性平滑插值。")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else if settings.fanPreset == .manual {
                            Divider()
                            if thermal.fanSnapshots.count > 1 {
                                Toggle("双风扇转速联动", isOn: $settings.dualFanLinked)

                                if !settings.dualFanLinked {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("风扇 1 (左):")
                                                .frame(width: 90, alignment: .leading)
                                            Slider(value: $settings.fan0CustomFraction, in: 0.0...1.0)
                                            Text("\(Int(settings.fan0CustomFraction * 100))%")
                                                .frame(width: 45, alignment: .trailing)
                                        }
                                        HStack {
                                            Text("风扇 2 (右):")
                                                .frame(width: 90, alignment: .leading)
                                            Slider(value: $settings.fan1CustomFraction, in: 0.0...1.0)
                                            Text("\(Int(settings.fan1CustomFraction * 100))%")
                                                .frame(width: 45, alignment: .trailing)
                                        }
                                    }
                                } else {
                                    HStack {
                                        Text("统一目标转速:")
                                            .frame(width: 90, alignment: .leading)
                                        Slider(value: $settings.customFanFraction, in: 0.0...1.0)
                                        Text("\(Int(settings.customFanFraction * 100))%")
                                            .frame(width: 45, alignment: .trailing)
                                    }
                                }
                            } else {
                                HStack {
                                    Text("自定义转速:")
                                        .frame(width: 90, alignment: .leading)
                                    Slider(value: $settings.customFanFraction, in: 0.0...1.0)
                                    Text("\(Int(settings.customFanFraction * 100))%")
                                        .frame(width: 45, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("实时传感器读数", systemImage: "thermometer.medium")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if thermal.allTemps.isEmpty {
                            Text("正在连接 SMC 驱动读取传感器...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(thermal.allTemps) { item in
                                    HStack {
                                        Text(item.name)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(String(format: "%.1f", item.celsius))°C")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Menu Bar Tab
    private var menuBarTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("自动化与交互", systemImage: "sparkles")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("展开后无操作自动折叠收纳", isOn: $settings.autoCollapseEnabled)

                        if settings.autoCollapseEnabled {
                            HStack {
                                Text("折叠延迟:")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $settings.autoCollapseDelay, in: 2...20, step: 1)
                                Text("\(Int(settings.autoCollapseDelay)) 秒")
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }

                        Toggle("鼠标指针悬停自动展开", isOn: $settings.hoverToExpand)
                    }
                    .padding(8)
                }

                GroupBox(label: Label("使用指南与快捷键", systemImage: "questionmark.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .font(.system(size: 12, weight: .bold))
                            Text("按住键盘 **Command (⌘)** 键，用鼠标将不常用的菜单栏图标拖动到 **`<` 折叠图标的左侧**。")
                                .font(.system(size: 12))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .font(.system(size: 12, weight: .bold))
                            Text("点击菜单栏的箭头 **`<`** 图标，或按下全局热键 **⌥ + ⌘ + H** 即可一键展开/收起。")
                                .font(.system(size: 12))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .font(.system(size: 12, weight: .bold))
                            Text("软件退出或重启时，所有图标将自动恢复系统原生排列。")
                                .font(.system(size: 12))
                        }
                    }
                    .padding(8)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Scroll Tab
    private var scrollTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("系统权限状态", systemImage: "lock.shield")) {
                    HStack {
                        Image(systemName: scroll.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(scroll.hasAccessibilityPermission ? .green : .orange)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scroll.hasAccessibilityPermission ? "辅助功能权限已就绪" : "需要授予辅助功能权限")
                                .font(.system(size: 13, weight: .semibold))
                            Text("滚动手势解耦需要通过辅助功能权限拦截并翻转鼠标滚轮事件。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !scroll.hasAccessibilityPermission {
                            Button("去授权...") {
                                AccessibilityHelper.requestAccessibilityPermission()
                                AccessibilityHelper.openSystemSettingsAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("设备独立滚动方向配置", systemImage: "slider.horizontal.2")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("启用滚动手势反转引擎", isOn: $settings.scrollReverserEnabled)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("传统外接鼠标 (Mouse)")
                                .font(.system(size: 12, weight: .semibold))

                            Toggle("反转垂直滚轮 (恢复 Windows/经典滚轮方向)", isOn: $settings.reverseMouseVertical)
                                .disabled(!settings.scrollReverserEnabled)
                            Toggle("反转水平滚轮 (X 轴)", isOn: $settings.reverseMouseHorizontal)
                                .disabled(!settings.scrollReverserEnabled)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("内建触控板 (Trackpad)")
                                .font(.system(size: 12, weight: .semibold))

                            Toggle("反转触控板双指垂直滑动", isOn: $settings.reverseTrackpadVertical)
                                .disabled(!settings.scrollReverserEnabled)
                            Toggle("反转触控板双指水平滑动", isOn: $settings.reverseTrackpadHorizontal)
                                .disabled(!settings.scrollReverserEnabled)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(10)
        }
    }

    // MARK: - NoTunes Tab (Music Blocker)
    private var noTunesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. 防护状态与总开关
                GroupBox(label: Label("Apple Music 防自动启动保护", systemImage: "shield.checkerboard")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            NoTunesIconView(size: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(settings.noTunesEnabled ? "防启动防护已激活" : "防启动保护已暂停")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(settings.noTunesEnabled ? "监控中" : "已暂停")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(settings.noTunesEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                                        .foregroundStyle(settings.noTunesEnabled ? .green : .secondary)
                                        .cornerRadius(4)
                                }
                                Text(settings.noTunesEnabled ? "系统检测到连接耳机或按键唤醒 Apple Music / iTunes 时，将瞬间阻止其启动。" : "系统将允许 Apple Music / iTunes 正常启动。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $settings.noTunesEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()

                        Toggle("开启拦截时自动关闭当前已在运行的 Music / iTunes", isOn: $settings.noTunesTerminateOnEnable)

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
            .padding(10)
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

    // MARK: - General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("启动与外观", systemImage: "gearshape")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("登录时自动启动 CalmBar", isOn: $settings.launchAtLogin)
                    Toggle("在菜单栏图标旁实时显示 SoC 温度", isOn: $settings.showTempInMenuBar)
                }
                .padding(8)
            }

            GroupBox(label: Label("关于 CalmBar", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "wind")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CalmBar (MacPulse)")
                                .font(.system(size: 14, weight: .bold))
                            Text("Version 1.0.0 (Native Swift 6 & SwiftUI)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Divider()
                    Text("整合硬件温控 (AirPulse)、菜单栏收纳 (Hidden Bar)、滚动手势解耦 (Scroll Reverser) 与媒体启动拦截 (noTunes) 的高性能 macOS 菜单栏综合增强套件。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(10)
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
