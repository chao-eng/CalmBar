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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.thermal.icon,
                    iconColors: SettingsTab.thermal.gradientColors,
                    title: "硬件温控与风扇调控引擎",
                    activeSubtitle: "已激活 · 正在持续监听 CPU 传感器并调节转速曲线 (\(settings.fanPreset.titleZH))",
                    inactiveSubtitle: "已停用 · 已停止温度传感器监听，完全交由 macOS 系统散热",
                    isEnabled: $settings.thermalEnabled
                )

                // 特权驱动与控制权限
                GroupBox(label: Label("特权驱动与控制权限", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: (helper.isHelperAvailable && !helper.needsHelperUpdate) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle((helper.isHelperAvailable && !helper.needsHelperUpdate) ? .green : .orange)
                                .font(.system(size: 20))

                            VStack(alignment: .leading, spacing: 2) {
                                let titleText: String = {
                                    if helper.isHelperAvailable && !helper.needsHelperUpdate {
                                        return "SMC 特权服务已就绪"
                                    } else if helper.needsHelperUpdate {
                                        return "特权服务需更新以支持充电控制"
                                    } else if helper.isHelperBlockedBySystem {
                                        return "特权服务未响应 · 需开启系统后台权限"
                                    } else {
                                        return "需要特权助手以修改风扇与充电状态"
                                    }
                                }()

                                let descText: String = {
                                    if helper.isHelperAvailable && !helper.needsHelperUpdate {
                                        return "当前具备向 SMC 写入风扇转速与电池充电阻断的完整特权。"
                                    } else if helper.isHelperBlockedBySystem {
                                        return "特权文件已安装，但被 macOS「允许在后台」机制阻止或暂停，请开启开关。"
                                    } else {
                                        return "macOS 安全机制要求特权后台服务 (LaunchDaemon) 才能写入 SMC 寄存器。"
                                    }
                                }()

                                Text(titleText)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(descText)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }

                            Spacer()

                            if !helper.isHelperAvailable || helper.needsHelperUpdate {
                                HStack(spacing: 6) {
                                    if helper.isHelperBlockedBySystem {
                                        Button("开启后台权限...") {
                                            HelperClient.promptAndOpenBackgroundSettings()
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.system(size: 12, weight: .medium))
                                    }

                                    Button(helper.needsHelperUpdate ? "一键更新..." : (helper.isHelperBlockedBySystem ? "重新激活..." : "一键激活...")) {
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
                                    .font(.system(size: 12, weight: .medium))
                                }
                            }
                        }

                        if helper.isHelperBlockedBySystem {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Text("如已授权过，请前往「系统设置 ➔ 通用 ➔ 登录项与扩展」，确保开启【CalmBarHelper 允许在后台】。")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.thermalEnabled)
                .opacity(settings.thermalEnabled ? 1.0 : 0.6)

                // 温控调控模式
                GroupBox(label: Label("温控调控模式与曲线参数", systemImage: "fanblades")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("调控模式", selection: $settings.fanPreset) {
                            ForEach(FanPreset.allCases) { preset in
                                Text(preset.titleZH).tag(preset)
                            }
                        }
                        .font(.system(size: 12.5))
                        .pickerStyle(.radioGroup)
                        .padding(.vertical, 4)

                        if settings.fanPreset == .smart {
                            Divider()
                            Text("智能温控加速曲线参数")
                                .font(.system(size: 12.5, weight: .semibold))

                            VStack(spacing: 8) {
                                HStack {
                                    Text("起始加速温度:")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .frame(width: 110, alignment: .leading)
                                    Slider(value: $settings.smartStartTemp, in: 40...75, step: 1)
                                    Text("\(Int(settings.smartStartTemp))°C")
                                        .frame(width: 45, alignment: .trailing)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                }
                                HStack {
                                    Text("满速运行温度:")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .frame(width: 110, alignment: .leading)
                                    Slider(value: $settings.smartFullTemp, in: 70...95, step: 1)
                                    Text("\(Int(settings.smartFullTemp))°C")
                                        .frame(width: 45, alignment: .trailing)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                }
                            }
                            Text("低于起始温度时保持最低静音转速，达到满速温度时全速散热，中间区域线性平滑插值。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        } else if settings.fanPreset == .manual {
                            Divider()
                            if thermal.fanSnapshots.count > 1 {
                                Toggle("双风扇转速联动", isOn: $settings.dualFanLinked)
                                    .font(.system(size: 12.5, weight: .medium))

                                if !settings.dualFanLinked {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("风扇 1 (左):")
                                                .font(.system(size: 12.5, weight: .medium))
                                                .frame(width: 90, alignment: .leading)
                                            Slider(value: $settings.fan0CustomFraction, in: 0.0...1.0)
                                            Text("\(Int(settings.fan0CustomFraction * 100))%")
                                                .frame(width: 45, alignment: .trailing)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        }
                                        HStack {
                                            Text("风扇 2 (右):")
                                                .font(.system(size: 12.5, weight: .medium))
                                                .frame(width: 90, alignment: .leading)
                                            Slider(value: $settings.fan1CustomFraction, in: 0.0...1.0)
                                            Text("\(Int(settings.fan1CustomFraction * 100))%")
                                                .frame(width: 45, alignment: .trailing)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        }
                                    }
                                } else {
                                    HStack {
                                        Text("统一目标转速:")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .frame(width: 90, alignment: .leading)
                                        Slider(value: $settings.customFanFraction, in: 0.0...1.0)
                                        Text("\(Int(settings.customFanFraction * 100))%")
                                            .frame(width: 45, alignment: .trailing)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    }
                                }
                            } else {
                                HStack {
                                    Text("自定义转速:")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .frame(width: 90, alignment: .leading)
                                    Slider(value: $settings.customFanFraction, in: 0.0...1.0)
                                    Text("\(Int(settings.customFanFraction * 100))%")
                                        .frame(width: 45, alignment: .trailing)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.thermalEnabled || settings.fanPreset == .auto)
                .opacity((!settings.thermalEnabled || settings.fanPreset == .auto) ? 0.6 : 1.0)

                // 实时传感器读数
                GroupBox(label: Label("实时传感器读数", systemImage: "thermometer.medium")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !settings.thermalEnabled {
                            Text("温控引擎已停用，传感器监听已暂停。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        } else if thermal.allTemps.isEmpty {
                            Text("正在连接 SMC 驱动读取传感器...")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(thermal.allTemps) { item in
                                    HStack {
                                        Text(item.name)
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(String(format: "%.1f", item.celsius))°C")
                                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.thermalEnabled)
                .opacity(settings.thermalEnabled ? 1.0 : 0.6)
            }
            .padding(16)
        }
    }
}
