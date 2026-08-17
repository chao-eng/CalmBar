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

    public var openSettingsAction: () -> Void = {}

    public init(openSettingsAction: @escaping () -> Void = {}) {
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
        .background(.ultraThinMaterial)
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
            }
            .padding(8)
            .background(Color.yellow.opacity(0.12))
            .cornerRadius(8)
        }
    }

    // MARK: - Gauges Row
    private var gaugesSection: some View {
        CardSection {
            HStack(spacing: 12) {
                TemperatureGaugeView(
                    title: "CPU",
                    temp: thermal.cpuTemp,
                    icon: "cpu",
                    color: .orange
                )
                Spacer()
                TemperatureGaugeView(
                    title: "GPU",
                    temp: thermal.gpuTemp,
                    icon: "square.stack.3d.up.fill",
                    color: .purple
                )
                Spacer()
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
                    Spacer()
                    FanRPMGaugeView(fan: thermal.fanSnapshots[1], title: "风扇 2")
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Fan Control Section (Matching Reference UI)
    private var fanControlSection: some View {
        VStack(spacing: 10) {
            // Segmented Mode Selector (Unambiguous Single Selection)
            HStack(spacing: 4) {
                ModePillButton(
                    title: "自动",
                    isSelected: settings.fanPreset == .auto
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.fanPreset = .auto
                    }
                }

                ModePillButton(
                    title: "自定义",
                    isSelected: settings.fanPreset == .manual
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.fanPreset = .manual
                    }
                }

                ModePillButton(
                    title: "智能",
                    icon: "sparkles",
                    isSelected: settings.fanPreset == .smart
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.fanPreset = .smart
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.06))
            )

            // Main Linked Fan Control Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("左右风扇联动")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $settings.dualFanLinked)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                }

                HStack(spacing: 10) {
                    Image(systemName: "fan")
                        .font(.system(size: 15))
                        .foregroundColor(settings.fanPreset == .auto ? .secondary : .blue)

                    Slider(value: sliderBinding, in: 0.0...1.0)
                        .accentColor(.blue)

                    Text("\(Int(activeFanFraction * 100))%")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    if let firstFan = thermal.fanSnapshots.first {
                        let rpm0 = Int(firstFan.actualRPM)
                        Text("风扇 0 \(formattedRPM(rpm0))")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text("风扇 0 3,060")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    if thermal.fanSnapshots.count > 1 {
                        let rpm1 = Int(thermal.fanSnapshots[1].actualRPM)
                        Text("风扇 1 \(formattedRPM(rpm1))")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )

            // Separate Control Section (When Dual Fan Linked is disabled)
            if !settings.dualFanLinked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("分别控制")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    // Fan 0 Slider
                    HStack(spacing: 10) {
                        Text("风扇 0")
                            .font(.system(size: 12))
                            .frame(width: 48, alignment: .leading)

                        Slider(value: $settings.fan0CustomFraction, in: 0.0...1.0)
                            .accentColor(.blue)

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
                                .accentColor(.blue)

                            let rpm1 = Int(thermal.fanSnapshots[1].actualRPM)
                            Text(formattedRPM(rpm1))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            if settings.fanPreset == .smart {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.blue)
                        .font(.system(size: 11))
                    Text("智能温控加速区间: \(Int(settings.smartStartTemp))°C ~ \(Int(settings.smartFullTemp))°C")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Quick Actions: Menu Bar & Scroll Reverser
    private var quickActionsSection: some View {
        CardSection {
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
                }
            }
        }
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack {
            Button(action: {
                openSettingsAction()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("偏好设置...")
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

public struct ModePillButton: View {
    public let title: String
    public var icon: String? = nil
    public let isSelected: Bool
    public let action: () -> Void

    public init(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color.clear)
            )
            .foregroundColor(isSelected ? .white : .primary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
