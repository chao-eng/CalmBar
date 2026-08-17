import SwiftUI
import CalmBarKit

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared
    @ObservedObject private var helper = HelperClient.shared

    @State private var isInstallingHelper = false
    @State private var helperMessage: String?

    public init() {}

    public var body: some View {
        TabView {
            thermalTab
                .tabItem {
                    Label("硬件温控", systemImage: "flame")
                }

            menuBarTab
                .tabItem {
                    Label("菜单栏收纳", systemImage: "menubar.rectangle")
                }

            scrollTab
                .tabItem {
                    Label("滚动手势", systemImage: "computermouse")
                }

            generalTab
                .tabItem {
                    Label("通用设置", systemImage: "gearshape")
                }
        }
        .frame(width: 520, height: 500)
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
                    Text("整合硬件温控 (AirPulse)、菜单栏收纳 (Hidden Bar) 与滚动手势解耦 (Scroll Reverser) 的高性能 macOS 菜单栏综合增强套件。")
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
