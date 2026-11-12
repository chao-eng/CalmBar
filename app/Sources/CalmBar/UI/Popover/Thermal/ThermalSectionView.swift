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
        // 控制权已交还系统时显示真实转速，避免滑杆仍停在用户目标值造成误导
        if thermal.isControlReleased {
            return dashboard.fanSnapshots.first?.percentage ?? 0
        }
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
            return max(Double(smart), thermal.safetyFloorFraction)
        case .manual:
            return max(settings.customFanFraction, thermal.safetyFloorFraction)
        }
    }

    private var hasMultipleFans: Bool {
        thermal.fanCapability.fanCount > 1
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { activeFanFraction },
            set: { newValue in
                // 先写入目标值，再切换模式：模式切换会触发一次应用，
                // 避免先切模式时用旧值写入一帧
                if !settings.dualFanLinked, hasMultipleFans {
                    settings.fan0CustomFraction = newValue
                    settings.fan1CustomFraction = newValue
                } else {
                    settings.customFanFraction = newValue
                }
                if settings.fanPreset != .manual {
                    settings.fanPreset = .manual
                }
            }
        )
    }

    private func perFanBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                if settings.fanPreset != .manual {
                    settings.fanPreset = .manual
                }
            }
        )
    }

    private var showsIndependentFanControls: Bool {
        settings.fanPreset == .manual && !settings.dualFanLinked && hasMultipleFans
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
                    .foregroundStyle(.secondary)
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
                        .tint(PopoverPalette.thermalAccent)

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
                    .tint(PopoverPalette.thermalAccent)
                }
            }
            .padding(8)
            .background(PopoverPalette.surfaceWell)
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
                color: PopoverPalette.tempColor(Double(settings.thermalEnabled ? thermal.cpuTemp : 0))
            )
            TemperatureGaugeView(
                title: "GPU",
                temp: settings.thermalEnabled ? thermal.gpuTemp : 0,
                icon: "square.stack.3d.up.fill",
                color: PopoverPalette.tempColor(Double(settings.thermalEnabled ? thermal.gpuTemp : 0))
            )

            if supportsFanControl, let firstFan = thermal.fanSnapshots.first, settings.thermalEnabled {
                FanRPMGaugeView(fan: firstFan, title: thermal.fanSnapshots.count > 1 ? "风扇 1" : "风扇")
            } else if thermal.batteryTemp > 0, settings.thermalEnabled {
                TemperatureGaugeView(
                    title: "电池",
                    temp: thermal.batteryTemp,
                    icon: "battery.100.bolt",
                    color: PopoverPalette.tempColor(Double(thermal.batteryTemp))
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
            .tint(PopoverPalette.thermalAccent)
            // 关闭系统焦点环绘制，避免选中态出现蓝色方框
            .focusable(false)
            .focusEffectDisabled()

            if let reason = thermal.controlReleaseReason {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(PopoverPalette.statusWarning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(thermal.isControlHandoffConfirmed ? "已由系统接管" : "风扇写入已暂停")
                            .font(.system(size: 11, weight: .semibold))
                        Text(reason)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("重新接管") {
                        thermal.clearControlRelease()
                        thermal.applyCurrentMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(PopoverPalette.surfaceWell)
                .cornerRadius(8)
            }

            if hasMultipleFans {
                HStack {
                    Text("左右风扇联动")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.dualFanLinked)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .tint(PopoverPalette.thermalAccent)
                        .accessibilityLabel("左右风扇联动")
                }
                .padding(.top, 2)
            }

            if !showsIndependentFanControls {
                HStack(spacing: 10) {
                    Image(systemName: "fan")
                        .font(.system(size: 14))
                        .foregroundColor((settings.fanPreset == .auto || !settings.thermalEnabled) ? .secondary : .primary)

                    Slider(value: sliderBinding, in: 0.0...1.0)
                        .tint(PopoverPalette.thermalAccent)
                        .accessibilityLabel("风扇转速")
                        .accessibilityValue("\(Int(activeFanFraction * 100))%")

                    Text("\(Int(activeFanFraction * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 38, alignment: .trailing)
                }
            }

            HStack(spacing: 12) {
                let hasMultipleFanSnapshots = thermal.fanSnapshots.count > 1
                let fan0Title = hasMultipleFanSnapshots ? "风扇 1" : "风扇"
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

                if hasMultipleFanSnapshots, settings.thermalEnabled {
                    let rpm1 = Int(thermal.fanSnapshots[1].actualRPM)
                    Text("风扇 2 \(formattedRPM(rpm1)) RPM")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            if showsIndependentFanControls {
                Divider()

                Text("分别控制")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Text("风扇 1")
                        .font(.system(size: 12))
                        .frame(width: 48, alignment: .leading)

                    Slider(value: perFanBinding(\.fan0CustomFraction), in: 0.0...1.0)
                        .tint(PopoverPalette.thermalAccent)
                        .accessibilityLabel("风扇 1 转速")

                    Text("\(Int(max(settings.fan0CustomFraction, thermal.safetyFloorFraction) * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Text("风扇 2")
                        .font(.system(size: 12))
                        .frame(width: 48, alignment: .leading)

                    Slider(value: perFanBinding(\.fan1CustomFraction), in: 0.0...1.0)
                        .tint(PopoverPalette.thermalAccent)
                        .accessibilityLabel("风扇 2 转速")

                    Text("\(Int(max(settings.fan1CustomFraction, thermal.safetyFloorFraction) * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
            }

            if settings.fanPreset == .smart {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
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
                .fill(PopoverPalette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PopoverPalette.separatorHairline, lineWidth: 0.5)
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
                .fill(PopoverPalette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PopoverPalette.separatorHairline, lineWidth: 0.5)
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
