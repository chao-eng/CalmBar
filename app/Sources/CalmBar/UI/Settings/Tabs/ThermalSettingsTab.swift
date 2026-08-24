import SwiftUI
import CalmBarKit

public struct ThermalSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared

    @State private var isInstallingHelper = false
    @State private var helperMessage: String?

    public init() {}

    private var isThermalControlEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { settings.fanPreset != .auto },
            set: { enabled in
                if enabled {
                    settings.fanPreset = .smart
                } else {
                    settings.fanPreset = .auto
                }
            }
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .thermal)

                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.thermal.icon,
                    iconColors: SettingsTab.thermal.gradientColors,
                    title: "硬件温控调控引擎",
                    activeSubtitle: "已激活 · 正在根据 CPU 传感器实时调节转速曲线 (\(settings.fanPreset.titleZH))",
                    inactiveSubtitle: "已停用 · macOS 系统原生托管散热，未覆写风扇转速",
                    isEnabled: isThermalControlEnabled
                )

                // 特权驱动与控制权限
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

                // 温控调控模式
                GroupBox(label: Label("温控调控模式与曲线参数", systemImage: "fanblades")) {
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
                .disabled(settings.fanPreset == .auto)
                .opacity(settings.fanPreset == .auto ? 0.6 : 1.0)

                // 实时传感器读数
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
            .padding(16)
        }
    }
}
