import SwiftUI
import CalmBarKit

public enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case thermal
    case menuBar
    case scroll
    case noTunes
    case caffeine
    case battery
    case gatekeeper
    case general

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .thermal: return "硬件温控"
        case .menuBar: return "菜单收纳"
        case .scroll: return "滚动手势"
        case .noTunes: return "音乐拦截"
        case .caffeine: return "防休眠"
        case .battery: return "充电管理"
        case .gatekeeper: return "应用授权"
        case .general: return "通用设置"
        }
    }

    public var icon: String {
        switch self {
        case .thermal: return "flame.fill"
        case .menuBar: return "menubar.rectangle"
        case .scroll: return "computermouse.fill"
        case .noTunes: return "music.note"
        case .caffeine: return "cup.and.saucer.fill"
        case .battery: return "battery.100.bolt"
        case .gatekeeper: return "lock.shield.fill"
        case .general: return "gearshape.fill"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var noTunes = NoTunesManager.shared
    @ObservedObject private var caffeine = CaffeineManager.shared
    @ObservedObject private var batteryMonitor = BatteryMonitor.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared

    @ObservedObject private var statusBarManager = StatusBarManager.shared

    @State private var selectedTab: SettingsTab = StatusBarManager.shared.selectedSettingsTab
    @State private var isInstallingHelper = false
    @State private var helperMessage: String?
    @State private var terminateAlertMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 14) {
            // Top Tab Navigation Bar (Dynamic Expandable Capsule)
            HStack {
                Spacer()
                HStack(spacing: 3) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = tab
                                statusBarManager.selectedSettingsTab = tab
                            }
                        }) {
                            SettingsTabItemView(
                                iconName: tab.icon,
                                title: tab.titleZH,
                                isSelected: selectedTab == tab
                            )
                        }
                        .buttonStyle(.plain)
                        .help(tab.titleZH)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                Spacer()
            }

            Divider()

            // Active Tab Content
            Group {
                switch selectedTab {
                case .thermal:
                    thermalTab
                case .menuBar:
                    menuBarTab
                case .scroll:
                    scrollTab
                case .noTunes:
                    noTunesTab
                case .caffeine:
                    caffeineTab
                case .battery:
                    batteryTab
                case .gatekeeper:
                    GatekeeperUnlockerView()
                case .general:
                    generalTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(width: 660, height: 560)
        .onChange(of: statusBarManager.selectedSettingsTab) { _, newTab in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = newTab
            }
        }
    }

    // MARK: - Thermal Tab
    private var thermalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("特权驱动与控制权限", systemImage: "lock.shield")) {
                    HStack {
                        Image(systemName: (helper.isHelperAvailable && !helper.needsHelperUpdate) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle((helper.isHelperAvailable && !helper.needsHelperUpdate) ? .green : .orange)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text((helper.isHelperAvailable && !helper.needsHelperUpdate) ? "SMC 特权服务已就绪" : (helper.needsHelperUpdate ? "特权服务需更新以支持充电控制" : "需要特权助手以修改风扇与充电状态"))
                                .font(.system(size: 13, weight: .semibold))
                            Text((helper.isHelperAvailable && !helper.needsHelperUpdate) ? "当前具备向 SMC 写入风扇转速与电池充电阻断的完整特权。" : "macOS 安全机制要求特权后台服务 (LaunchDaemon) 才能写入 SMC 寄存器。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !helper.isHelperAvailable || helper.needsHelperUpdate {
                            Button(helper.needsHelperUpdate ? "一键更新..." : "一键激活...") {
                                isInstallingHelper = true
                                helper.requestInstallHelper { success, err in
                                    isInstallingHelper = false
                                    if success {
                                        thermal.checkAuthorization()
                                        helper.checkHelperStatus()
                                        chargeManager.evaluateChargingPolicy()
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

    // MARK: - Caffeine Tab (Keep Awake)
    private var caffeineTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. 状态与快速控制
                GroupBox(label: Label("防休眠状态与快速启动", systemImage: "cup.and.saucer.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            CaffeineIconView(size: 36, isActive: caffeine.isActive)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(caffeine.isActive ? "保持清醒已激活 (防休眠)" : "防休眠处于停用状态")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(caffeine.isActive ? "已阻止休眠" : "节能模式")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(caffeine.isActive ? Color.brown.opacity(0.12) : Color.secondary.opacity(0.15))
                                        .foregroundStyle(caffeine.isActive ? Color.brown : Color.secondary)
                                        .cornerRadius(4)
                                }
                                Text(caffeine.isActive ? "剩余时间: \(caffeine.formattedTimeRemaining())" : "系统将按照 macOS 默认节能设置自动熄屏与睡眠。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { caffeine.isActive },
                                set: { if $0 { caffeine.activate() } else { caffeine.deactivate() } }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(.accentColor)
                        }

                        Divider()

                        // 快速时长预设按钮组
                        VStack(alignment: .leading, spacing: 8) {
                            Text("快速设置保持清醒时长:")
                                .font(.system(size: 11, weight: .medium))

                            HStack(spacing: 6) {
                                durationPresetButton(title: "无限期", minutes: 0)
                                durationPresetButton(title: "15 分钟", minutes: 15)
                                durationPresetButton(title: "30 分钟", minutes: 30)
                                durationPresetButton(title: "1 小时", minutes: 60)
                                durationPresetButton(title: "2 小时", minutes: 120)
                                durationPresetButton(title: "5 小时", minutes: 300)
                            }
                        }
                    }
                    .padding(8)
                }

                // 2. 默认行为与自动化配置
                GroupBox(label: Label("自动化策略与默认行为", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("默认激活时长:")
                                .font(.system(size: 13))

                            Picker("", selection: $settings.caffeineDefaultDuration) {
                                Text("无限期 (直到手动关闭)").tag(0)
                                Text("5 分钟").tag(5)
                                Text("10 分钟").tag(10)
                                Text("15 分钟").tag(15)
                                Text("30 分钟").tag(30)
                                Text("1 小时").tag(60)
                                Text("2 小时").tag(120)
                                Text("5 小时").tag(300)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)

                            Spacer()
                        }

                        Divider()

                        Toggle("启动 CalmBar 时自动开启保持清醒", isOn: $settings.caffeineActivateAtLaunch)
                        Toggle("Mac 手动进入睡眠时自动解除保持清醒", isOn: $settings.caffeineDeactivateOnManualSleep)
                    }
                    .padding(8)
                }

                // 3. 办公软件防离开 (Activity Simulator)
                GroupBox(label: Label("办公软件防离开与防挂起 (Keep Apps Active)", systemImage: "sparkles")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("防止办公软件闲置离开状态 (Teams / Slack / 飞书 / 钉钉)", isOn: Binding(
                            get: { settings.caffeineKeepAppsActive },
                            set: { newVal in
                                settings.caffeineKeepAppsActive = newVal
                                caffeine.updateActivitySimulation(enabled: newVal)
                            }
                        ))
                        .font(.system(size: 13, weight: .medium))

                        Text("当系统闲置超过设定阈值时，自动在鼠标原位产生微小的系统 HID 级微动，阻止 Microsoft Teams、Slack、飞书等协同办公软件将你的状态自动变更为「离开 (Away)」，同时防止屏幕保护程序启动。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if settings.caffeineKeepAppsActive {
                            Divider()

                            HStack {
                                Text("触发空闲阈值:")
                                    .frame(width: 100, alignment: .leading)
                                Slider(value: $settings.caffeineIdleThreshold, in: 30...300, step: 15)
                                Text("\(Int(settings.caffeineIdleThreshold)) 秒")
                                    .frame(width: 45, alignment: .trailing)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    .padding(8)
                }

                // 4. 底层技术与原理
                GroupBox(label: Label("系统原理与电源管理说明", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **原生 IOKit 电源断言**：通过 macOS 原生 `IOKit.pwr_mgt` 的 `kIOPMAssertPreventUserIdleDisplaySleep` 向电源管理总线注册临时断言，零 CPU 占用且不损伤电池寿命。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("• **安全释放机制 (Fail-Safe)**：CalmBar 退出、重启或系统锁屏切换用户时，将自动释放所有电源断言并暂停微动，确保节电策略正常。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(10)
        }
    }

    private func durationPresetButton(title: String, minutes: Int) -> some View {
        Button(title) {
            let seconds = minutes > 0 ? TimeInterval(minutes * 60) : 0
            caffeine.activate(withTimeout: seconds)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Battery Tab (Charging Limit & Health)
    private var batteryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !helper.isHelperAvailable || helper.needsHelperUpdate {
                    GroupBox(label: Label("特权助手状态", systemImage: "lock.shield")) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(helper.needsHelperUpdate ? "特权助手需更新以支持充电控制" : "充电上限控制需要特权助手")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("修改 SMC 充电寄存器需要系统特权守护服务，请点击右侧按钮一键激活或更新。")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(helper.needsHelperUpdate ? "一键更新" : "一键激活") {
                                isInstallingHelper = true
                                helper.requestInstallHelper { success, err in
                                    isInstallingHelper = false
                                    if success {
                                        thermal.checkAuthorization()
                                        helper.checkHelperStatus()
                                        chargeManager.evaluateChargingPolicy()
                                    } else {
                                        helperMessage = err
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(6)
                    }
                }

                // 1. 电池健康与实时读数
                GroupBox(label: Label("电池实时状态与健康度", systemImage: "battery.100.bolt")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            BatteryIconView(
                                size: 36,
                                isCharging: batteryMonitor.isCharging,
                                isBypassed: chargeManager.isChargingInhibited,
                                isDischarging: chargeManager.operationStatus == .discharging
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("当前电量 \(batteryMonitor.currentPercentage)%")
                                        .font(.system(size: 14, weight: .bold))

                                    Text(chargeManager.operationStatus.titleZH)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.12))
                                        .foregroundStyle(Color.accentColor)
                                        .cornerRadius(4)
                                }

                                Text(chargeManager.lastStatusMessage)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $settings.batteryChargeLimitEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .tint(.accentColor)
                        }

                        Divider()

                        // 4 格指标面板
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            statCard(title: "电池健康度", value: "\(batteryMonitor.healthPercentage)%", icon: "heart.fill", color: .pink)
                            statCard(title: "循环计数", value: "\(batteryMonitor.cycleCount) 次", icon: "arrow.triangle.2.circlepath", color: .blue)
                            statCard(title: "供电来源", value: chargeManager.operationStatus == .discharging ? "自动放电中" : (batteryMonitor.isACPowered ? "电源适配器" : "电池供电"), icon: "powerplug.fill", color: .orange)
                            statCard(title: "电池温度", value: batteryMonitor.temperatureCelsius > 0 ? "\(String(format: "%.1f", batteryMonitor.temperatureCelsius))°C" : "\(Int(thermal.batteryTemp > 0 ? thermal.batteryTemp : 30))°C", icon: "thermometer.medium", color: .green)
                        }
                    }
                    .padding(8)
                }

                // 2. 充电上限控制策略
                GroupBox(label: Label("充电上限控制策略", systemImage: "slider.horizontal.2")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("目标充电上限:")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(settings.batteryChargeLimit)%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.accentColor)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settings.batteryChargeLimit) },
                                set: { settings.batteryChargeLimit = Int($0) }
                            ),
                            in: 50...100,
                            step: 1
                        )
                        .tint(.accentColor)

                        // 快速预设按钮组
                        HStack(spacing: 6) {
                            batteryPresetButton(title: "70%", limit: 70)
                            batteryPresetButton(title: "80% (推荐)", limit: 80)
                            batteryPresetButton(title: "85%", limit: 85)
                            batteryPresetButton(title: "90%", limit: 90)
                            batteryPresetButton(title: "100%", limit: 100)
                        }

                        Divider()

                        // 回差巡航模式
                        Toggle("启用回差巡航模式 (Sailing Mode)", isOn: $settings.batterySailingModeEnabled)
                            .font(.system(size: 13, weight: .medium))

                        if settings.batterySailingModeEnabled {
                            HStack {
                                Text("回差跨度:")
                                    .frame(width: 80, alignment: .leading)
                                Slider(
                                    value: Binding(
                                        get: { Double(settings.batterySailingDelta) },
                                        set: { settings.batterySailingDelta = Int($0) }
                                    ),
                                    in: 2...10,
                                    step: 1
                                )
                                Text("\(settings.batterySailingDelta)% (\(max(20, settings.batteryChargeLimit - settings.batterySailingDelta))% ~ \(settings.batteryChargeLimit)%)")
                                    .frame(width: 90, alignment: .trailing)
                                    .font(.system(size: 11, design: .monospaced))
                            }

                            Text("当电量达到 \(settings.batteryChargeLimit)% 后停止充电，电量自然消耗回落到 \(max(20, settings.batteryChargeLimit - settings.batterySailingDelta))% 时才恢复补充充电，避免在临界值反复触发微充微放。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        // 自动放电至上限 (Automatic Discharge)
                        Toggle("自动放电至目标上限 (Auto Discharge)", isOn: $settings.batteryAutoDischargeEnabled)
                            .font(.system(size: 13, weight: .medium))

                        Text("当插入充电器但当前电量（如 98%）高于设定的充电上限（如 80%）时，通过 SMC 硬件指令主动切断电源适配器供电，使用电池供电直至电量回落到目标上限。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // 3. 临时充至 100% (Top Up)
                GroupBox(label: Label("临时满电模式 (Top Up)", systemImage: "bolt.badge.clock")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("临时充至 100% 满电")
                                .font(.system(size: 13, weight: .medium))
                            Text("临时放开充电限制充满至 100%，充满后自动恢复设定的电量保护，适合出门前临时蓄电。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if settings.batteryTopUpActive {
                            Button("取消满电") {
                                chargeManager.toggleTopUp()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("立即充至 100%") {
                                chargeManager.toggleTopUp()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                }

                // 4. 原理与技术说明
                GroupBox(label: Label("硬件充电阻断说明", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **硬件级适配器旁路供电**：通过向 SMC 写入 `CH0C` / `CHTE` 寄存器指令，使 Mac 在接通电源时直接使用适配器电流供电，完全切断流入电池的涓流电流，保护电池化学活性。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("• **安全回退保障 (Fail-Safe)**：CalmBar 退出或系统重启时，特权助手将自动解除阻断，确保 Mac 恢复原生充电逻辑。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(10)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            Spacer()
        }
        .padding(6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }

    private func batteryPresetButton(title: String, limit: Int) -> some View {
        Button(title) {
            settings.batteryChargeLimit = limit
        }
        .buttonStyle(.bordered)
        .tint(settings.batteryChargeLimit == limit ? .accentColor : .secondary)
        .controlSize(.small)
    }

    // MARK: - General Tab
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("启动与外观", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("登录时自动启动 CalmBar", isOn: $settings.launchAtLogin)
                        Toggle("在菜单栏图标旁实时显示 SoC 温度", isOn: $settings.showTempInMenuBar)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("任务栏左键面板显示项目", systemImage: "list.bullet.rectangle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自定义左键点击菜单栏图标时在面板中展示的功能模块（风扇控制模块作为核心默认常驻）：")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            Toggle(isOn: $settings.popoverShowGauges) {
                                Label("硬件温度仪表盘", systemImage: "gauge.with.needle")
                            }
                            Toggle(isOn: $settings.popoverShowMenuBar) {
                                Label("菜单栏图标收纳", systemImage: "menubar.rectangle")
                            }
                            Toggle(isOn: $settings.popoverShowScrollReverser) {
                                Label("鼠标自然滚动解耦", systemImage: "computermouse.fill")
                            }
                            Toggle(isOn: $settings.popoverShowNoTunes) {
                                Label("Apple Music 启动拦截", systemImage: "music.note")
                            }
                            Toggle(isOn: $settings.popoverShowCaffeine) {
                                Label("系统防休眠 (保持清醒)", systemImage: "cup.and.saucer.fill")
                            }
                            Toggle(isOn: $settings.popoverShowBattery) {
                                Label("电池充电上限控制", systemImage: "battery.100.bolt")
                            }
                            Toggle(isOn: $settings.popoverShowGatekeeper) {
                                Label("软件去隔离与签名授权", systemImage: "lock.shield.fill")
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text("整合硬件温控 (AirPulse)、菜单栏收纳 (Hidden Bar)、滚动手势解耦 (Scroll Reverser)、媒体启动拦截 (noTunes)、防休眠与防离开 (Caffeine)、电池充电上限 (Aidente) 及应用去隔离授权的全能 macOS 菜单栏综合增强套件。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
    }
}

private struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

private struct SettingsTabItemView: View {
    let iconName: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .frame(width: 18, height: 18)

            // 只有选中时才显示文字
            if isSelected {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    // 确保文字在动画收缩时不会截断
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, isSelected ? 12 : 8)
        .padding(.vertical, 6)
        // 选中的胶囊背景
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .clipShape(Capsule())
        // 给整个 HStack 加上春天的回弹动画，极具苹果原生质感
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
