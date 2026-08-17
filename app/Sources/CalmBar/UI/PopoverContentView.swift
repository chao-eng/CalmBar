import SwiftUI
import CalmBarKit

public struct PopoverContentView: View {
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var menuBar = MenuBarOrganizer.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared
    @ObservedObject private var helper = HelperClient.shared

    @State private var isInstallingHelper = false
    @State private var helperInstallMessage: String?

    public var openSettingsAction: (SettingsTab) -> Void = { _ in }

    public init(openSettingsAction: @escaping (SettingsTab) -> Void = { _ in }) {
        self.openSettingsAction = openSettingsAction
    }

    private var activeFanFraction: Double {
        switch settings.fanPreset {
        case .auto:
            return thermal.fanSnapshots.first?.percentage ?? 0.25
        case .smart:
            let smart = FanCurveCalculator.fraction(
                forCelsius: thermal.primaryTemp,
                startTemp: Float(settings.smartStartTemp),
                fullSpeedTemp: Float(settings.smartFullTemp),
                minFraction: 0.0,
                maxFraction: 1.0
            )
            return Double(smart)
        case .manual:
            return settings.customFanFraction
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                activeFanFraction
            },
            set: { newVal in
                if settings.fanPreset != .manual {
                    settings.fanPreset = .manual
                }
                settings.customFanFraction = newVal
            }
        )
    }

    public var body: some View {
        VStack(spacing: 12) {
            headerView
            permissionBanners
            gaugesSection
            fanControlSection
            quickActionsSection
            footerView
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial)
    }

    // MARK: - Header Bar
    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "wind")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("CalmBar")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Spacer()
            if !thermal.isSMCConnected {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("无 SMC 驱动")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if thermal.currentSafetyAction != .none {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.red)
                    Text("温控保护中")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Permission Banners
    @ViewBuilder
    private var permissionBanners: some View {
        if !thermal.isFanControlAuthorized {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("风扇调控未激活")
                        .font(.system(size: 11, weight: .semibold))
                    Text("需要特权助手以修改风扇转速")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    isInstallingHelper = true
                    helper.requestInstallHelper { success, err in
                        isInstallingHelper = false
                        if success {
                            thermal.checkAuthorization()
                        } else {
                            helperInstallMessage = err
                        }
                    }
                }) {
                    if isInstallingHelper {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("一键激活")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.accentColor)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(8)
        }

        if !scroll.hasAccessibilityPermission {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("未授予辅助功能权限")
                        .font(.system(size: 11, weight: .semibold))
                    Text("鼠标滚轮反转需要辅助功能权限")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("去授权") {
                    AccessibilityHelper.requestAccessibilityPermission()
                    AccessibilityHelper.openSystemSettingsAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.accentColor)
            }
            .padding(8)
            .background(Color.yellow.opacity(0.12))
            .cornerRadius(8)
        }
    }

    // MARK: - Gauges Row
    private var gaugesSection: some View {
        HStack(spacing: 8) {
            TemperatureGaugeView(
                title: "CPU",
                temp: thermal.cpuTemp,
                icon: "cpu",
                color: .orange
            )
            TemperatureGaugeView(
                title: "GPU",
                temp: thermal.gpuTemp,
                icon: "square.stack.3d.up.fill",
                color: .purple
            )
            if let firstFan = thermal.fanSnapshots.first {
                FanRPMGaugeView(fan: firstFan, title: "风扇 1")
            } else {
                TemperatureGaugeView(
                    title: "电池",
                    temp: thermal.batteryTemp > 0 ? thermal.batteryTemp : 32,
                    icon: "battery.100.bolt",
                    color: .green
                )
            }

            if thermal.fanSnapshots.count > 1 {
                FanRPMGaugeView(fan: thermal.fanSnapshots[1], title: "风扇 2")
            }
        }
    }

    // MARK: - Fan Control Section (Native macOS HIG Style)
    private var fanControlSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Native Segmented Picker
                Picker("风扇模式", selection: $settings.fanPreset) {
                    Text("自动").tag(FanPreset.auto)
                    Text("自定义").tag(FanPreset.manual)
                    Label("智能", systemImage: "sparkles").tag(FanPreset.smart)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Linked Fan Toggle & Slider
                HStack {
                    Text("左右风扇联动")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.dualFanLinked)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .tint(.accentColor)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    Image(systemName: "fan")
                        .font(.system(size: 14))
                        .foregroundColor(settings.fanPreset == .auto ? .secondary : .accentColor)

                    Slider(value: sliderBinding, in: 0.0...1.0)
                        .tint(.accentColor)

                    Text("\(Int(activeFanFraction * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 38, alignment: .trailing)
                }

                // RPM Readouts
                HStack(spacing: 12) {
                    if let firstFan = thermal.fanSnapshots.first {
                        let rpm0 = Int(firstFan.actualRPM)
                        Text("风扇 0 \(formattedRPM(rpm0)) RPM")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text("风扇 0 3,060 RPM")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    if thermal.fanSnapshots.count > 1 {
                        let rpm1 = Int(thermal.fanSnapshots[1].actualRPM)
                        Text("风扇 1 \(formattedRPM(rpm1)) RPM")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                // Separate Control Section (When Dual Fan Linked is disabled)
                if !settings.dualFanLinked {
                    Divider()

                    Text("分别控制")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    // Fan 0 Slider
                    HStack(spacing: 10) {
                        Text("风扇 0")
                            .font(.system(size: 12))
                            .frame(width: 48, alignment: .leading)

                        Slider(value: $settings.fan0CustomFraction, in: 0.0...1.0)
                            .tint(.accentColor)

                        let rpm0 = Int(thermal.fanSnapshots.first?.actualRPM ?? Float(settings.fan0CustomFraction * 5000 + 1200))
                        Text(formattedRPM(rpm0))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 48, alignment: .trailing)
                    }

                    // Fan 1 Slider (if hardware has fan 1)
                    if thermal.fanSnapshots.count > 1 {
                        HStack(spacing: 10) {
                            Text("风扇 1")
                                .font(.system(size: 12))
                                .frame(width: 48, alignment: .leading)

                            Slider(value: $settings.fan1CustomFraction, in: 0.0...1.0)
                                .tint(.accentColor)

                            let rpm1 = Int(thermal.fanSnapshots[1].actualRPM)
                            Text(formattedRPM(rpm1))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                if settings.fanPreset == .smart {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.tint)
                            .font(.system(size: 11))
                        Text("加速区间: \(Int(settings.smartStartTemp))°C ~ \(Int(settings.smartFullTemp))°C")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Quick Actions: Menu Bar & Scroll Reverser
    private var quickActionsSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                // Menu Bar Collapse/Expand Row
                HStack {
                    Image(systemName: "menubar.rectangle")
                        .foregroundStyle(.indigo)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("菜单栏图标收纳")
                            .font(.system(size: 12, weight: .medium))
                        Text(menuBar.isCollapsed ? "当前处于收纳折叠状态" : "当前处于展开显示状态")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        menuBar.toggleExpandCollapse()
                    }) {
                        Text(menuBar.isCollapsed ? "展开" : "折叠")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.accentColor)
                }

                Divider()

                // Scroll Reverser Row
                HStack {
                    Image(systemName: "computermouse.fill")
                        .foregroundStyle(.teal)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("外接鼠标自然滚动解耦")
                            .font(.system(size: 12, weight: .medium))
                        Text(settings.scrollReverserEnabled ? "鼠标已反转 (触控板保持原生)" : "已停用")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.scrollReverserEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .tint(.accentColor)
                }

                Divider()

                // Apple Music Blocker Row
                HStack {
                    NoTunesIconView(size: 20)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Apple Music 启动拦截")
                            .font(.system(size: 12, weight: .medium))
                        Text(settings.noTunesEnabled ? "已启用防误触拉起" : "已暂停拦截")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.noTunesEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .tint(.accentColor)
                }

                Divider()

                // Gatekeeper App Unlocker Row
                HStack {
                    GatekeeperIconView(size: 20)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("软件去隔离与签名授权")
                            .font(.system(size: 12, weight: .medium))
                        Text("修复未签名或损坏应用提示")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        openSettingsAction(.gatekeeper)
                    }) {
                        Text("去授权")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack {
            Button(action: {
                openSettingsAction(.thermal)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("偏好设置")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("退出 CalmBar")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.top, 2)
    }

    private func formattedRPM(_ rpm: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rpm)) ?? "\(rpm)"
    }
}
