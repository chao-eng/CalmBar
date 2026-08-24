import SwiftUI
import CalmBarKit

public struct BatterySettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var batteryMonitor = BatteryMonitor.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var helper = HelperClient.shared

    @State private var isInstallingHelper = false
    @State private var helperMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .battery)

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
                GroupBox(label: Label("硬件充电阻断与安全熔断机制", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **SMC 寄存器充电控制**：通过向 SMC 写入 `CH0C` / `CHTE` 寄存器指令，在接通电源且达到目标上限时停止对电池充入电流，直接转由适配器供电。（适配具备相关寄存器的 Apple Silicon 与 Intel Mac 机型）。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("• **底层安全熔断保护 (Safety Melt)**：电量 ≤ 15% 或电池温度过高时，CalmBar 将立即强行终止放电并取消阻断，确保电芯寿命安全。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("• **安全回退保障 (Fail-Safe)**：CalmBar 退出、系统休眠或关机时，特权助手将自动安全交还控制权，Mac 恢复官方默认充电策略。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(16)
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
}
