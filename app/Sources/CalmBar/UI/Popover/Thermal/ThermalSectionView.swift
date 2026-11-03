import SwiftUI
import CalmBarKit

// MARK: - M2 温控分区：迁移自 PopoverContentView 的仪表、风扇、权限横幅

struct ThermalSectionView: View {
    @ObservedObject private var dashboard = DashboardViewModel.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared

    @State private var isInstallingHelper = false
    @State private var helperInstallMessage: String?

    var viewportHeight: CGFloat
    var stressExtraHeight: CGFloat = 0
    var allHidden: Bool = false
    var onMeasure: ((CGFloat) -> Void)?

    private var activeFanFraction: Double {
        switch settings.fanPreset {
        case .auto:
            return dashboard.fanSnapshots.first?.percentage ?? 0.25
        case .smart:
            let smart = FanCurveCalculator.fraction(
                forCelsius: dashboard.primaryTemperature,
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
            get: { activeFanFraction },
            set: { newValue in
                if settings.fanPreset != .manual {
                    settings.fanPreset = .manual
                }
                settings.customFanFraction = newValue
            }
        )
    }

    private var isFanless: Bool { thermal.isFanless }
    private var supportsFanControl: Bool { thermal.supportsFanControl }

    var body: some View {
        if allHidden || !settings.popoverShowGauges {
            PopoverEmptyState(group: .thermal)
                .frame(width: PopoverLayout.contentWidth, height: viewportHeight)
        } else {
            ScrollView {
                VStack(spacing: PopoverLayout.blockGap) {
                    permissionBanners
                    gaugesSection
                    if supportsFanControl {
                        fanControlSection
                    } else if isFanless {
                        fanlessMonitoringSection
                    }
                    if stressExtraHeight > 0 {
                        Color.clear.frame(height: stressExtraHeight)
                    }
                }
                .frame(width: PopoverLayout.contentWidth)
                .background(heightReader)
            }
            .scrollIndicators(.never)
            .frame(width: PopoverLayout.contentWidth, height: viewportHeight)
        }
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onMeasure?(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in
                    onMeasure?(height)
                }
        }
    }

    // MARK: Helper 横幅（辅助功能横幅已迁至守护分区）

    @ViewBuilder
    private var permissionBanners: some View {
        if dashboard.needsHelperAttention {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    let title = helper.needsHelperUpdate ? "特权助手需更新" : (helper.isHelperBlockedBySystem ? "特权助手被后台阻止" : "特权助手未激活")
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(dashboard.helperAttentionMessage)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if helper.isHelperBlockedBySystem {
                    HStack(spacing: 4) {
                        Button("开启后台权限") {
                            HelperClient.promptAndOpenBackgroundSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(.accentColor)

                        Button {
                            HelperClient.shared.checkHelperStatus()
                            PermissionManager.shared.refreshAll()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("刷新检测状态")
                    }
                } else {
                    Button(action: requestHelperInstall) {
                        if isInstallingHelper {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(helper.needsHelperUpdate ? "一键更新" : "一键激活")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.accentColor)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(8)
        }
    }

    private func requestHelperInstall() {
        isInstallingHelper = true
        helper.requestInstallHelper { success, error in
            isInstallingHelper = false
            if success {
                thermal.checkAuthorization()
                helper.checkHelperStatus()
                chargeManager.evaluateChargingPolicy()
            } else {
                helperInstallMessage = error
            }
        }
    }

    // MARK: Gauges

    private var gaugesSection: some View {
        HStack(spacing: 6) {
            TemperatureGaugeView(
                title: "CPU",
                temp: settings.thermalEnabled ? thermal.cpuTemp : 0,
                icon: "cpu",
                color: .orange
            )
            TemperatureGaugeView(
                title: "GPU",
                temp: settings.thermalEnabled ? thermal.gpuTemp : 0,
                icon: "square.stack.3d.up.fill",
                color: .purple
            )

            if supportsFanControl, let firstFan = thermal.fanSnapshots.first, settings.thermalEnabled {
                FanRPMGaugeView(fan: firstFan, title: thermal.fanSnapshots.count > 1 ? "风扇 1" : "风扇")
            } else if thermal.batteryTemp > 0, settings.thermalEnabled {
                TemperatureGaugeView(
                    title: "电池",
                    temp: thermal.batteryTemp,
                    icon: "battery.100.bolt",
                    color: .green
                )
            }

            if supportsFanControl, thermal.fanSnapshots.count > 1, settings.thermalEnabled {
                FanRPMGaugeView(fan: thermal.fanSnapshots[1], title: "风扇 2")
            }
        }
        .disabled(!settings.thermalEnabled)
        .opacity(settings.thermalEnabled ? 1.0 : 0.45)
    }

    // MARK: Fan Control

    private var fanControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("风扇模式", selection: $settings.fanPreset) {
                Text("自动").tag(FanPreset.auto)
                Text("自定义").tag(FanPreset.manual)
                Label("智能", systemImage: "sparkles").tag(FanPreset.smart)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 保留键盘可聚焦，仅关闭系统焦点环绘制
            .focusEffectDisabled()

            HStack {
                Text("左右风扇联动")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $settings.dualFanLinked)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .tint(.accentColor)
                    .accessibilityLabel("左右风扇联动")
            }
            .padding(.top, 2)

            HStack(spacing: 10) {
                Image(systemName: "fan")
                    .font(.system(size: 14))
                    .foregroundColor((settings.fanPreset == .auto || !settings.thermalEnabled) ? .secondary : .accentColor)

                Slider(value: sliderBinding, in: 0.0...1.0)
                    .tint(.accentColor)
                    .accessibilityLabel("风扇转速")
                    .accessibilityValue("\(Int(activeFanFraction * 100))%")

                Text("\(Int(activeFanFraction * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 12) {
                let hasMultipleFans = thermal.fanSnapshots.count > 1
                let fan0Title = hasMultipleFans ? "风扇 1" : "风扇"
                if let firstFan = thermal.fanSnapshots.first, settings.thermalEnabled {
                    let rpm0 = Int(firstFan.actualRPM)
                    Text("\(fan0Title) \(formattedRPM(rpm0)) RPM")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                } else {
                    Text("\(fan0Title) \(settings.thermalEnabled ? "3,060" : "0") RPM")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }

                if hasMultipleFans, settings.thermalEnabled {
                    let rpm1 = Int(thermal.fanSnapshots[1].actualRPM)
                    Text("风扇 2 \(formattedRPM(rpm1)) RPM")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            if !settings.dualFanLinked {
                Divider()

                Text("分别控制")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Text(thermal.fanSnapshots.count > 1 ? "风扇 1" : "风扇")
                        .font(.system(size: 12))
                        .frame(width: 48, alignment: .leading)

                    Slider(value: $settings.fan0CustomFraction, in: 0.0...1.0)
                        .tint(.accentColor)
                        .accessibilityLabel(thermal.fanSnapshots.count > 1 ? "风扇 1 转速" : "风扇转速")

                    let rpm0 = Int(thermal.fanSnapshots.first?.actualRPM ?? Float(settings.fan0CustomFraction * 5000 + 1200))
                    Text(formattedRPM(rpm0))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }

                if thermal.fanSnapshots.count > 1 {
                    HStack(spacing: 10) {
                        Text("风扇 2")
                            .font(.system(size: 12))
                            .frame(width: 48, alignment: .leading)

                        Slider(value: $settings.fan1CustomFraction, in: 0.0...1.0)
                            .tint(.accentColor)
                            .accessibilityLabel("风扇 2 转速")

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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .disabled(!settings.thermalEnabled)
        .opacity(settings.thermalEnabled ? 1.0 : 0.45)
    }

    // MARK: Fanless

    private var fanlessMonitoringSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "fan.slash")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("本机无内置风扇 · 纯温度监控")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("被动散热机型，无需调速。温度读数 \(Int(thermal.primaryTemp))°C")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .disabled(!settings.thermalEnabled)
        .opacity(settings.thermalEnabled ? 1.0 : 0.45)
    }

    private func formattedRPM(_ rpm: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rpm)) ?? "\(rpm)"
    }
}
