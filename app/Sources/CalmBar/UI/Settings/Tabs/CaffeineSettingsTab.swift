import SwiftUI
import CalmBarKit

public struct CaffeineSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var caffeine = CaffeineManager.shared

    public init() {}

    private var isCaffeineActive: Binding<Bool> {
        Binding<Bool>(
            get: { caffeine.isActive },
            set: { enabled in
                if enabled {
                    caffeine.activate()
                } else {
                    caffeine.deactivate()
                }
            }
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.caffeine.icon,
                    iconColors: SettingsTab.caffeine.gradientColors,
                    title: "系统保持清醒 (防休眠)",
                    activeSubtitle: "已激活 · 阻止系统与显示器睡眠 (剩余时间: \(caffeine.formattedTimeRemaining()))",
                    inactiveSubtitle: "已停用 · 采用 macOS 默认节能策略，允许自动熄屏与休眠",
                    isEnabled: isCaffeineActive
                )

                // 1. 快速控制与时长预设
                GroupBox(label: Label("快速设置保持清醒时长", systemImage: "cup.and.saucer.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            durationPresetButton(title: "无限期", minutes: 0)
                            durationPresetButton(title: "15 分钟", minutes: 15)
                            durationPresetButton(title: "30 分钟", minutes: 30)
                            durationPresetButton(title: "1 小时", minutes: 60)
                            durationPresetButton(title: "2 小时", minutes: 120)
                            durationPresetButton(title: "5 小时", minutes: 300)
                        }
                    }
                    .padding(8)
                }

                // 2. 默认行为与自动化配置
                GroupBox(label: Label("自动化策略与默认行为", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("默认激活时长:")
                                .font(.system(size: 12.5, weight: .medium))

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
                            .font(.system(size: 12.5))
                            .pickerStyle(.menu)
                            .frame(width: 200)

                            Spacer()
                        }

                        Divider()

                        Toggle("启动 CalmBar 时自动开启保持清醒", isOn: $settings.caffeineActivateAtLaunch)
                            .font(.system(size: 12.5, weight: .medium))

                        Toggle("Mac 手动进入睡眠时自动解除保持清醒", isOn: $settings.caffeineDeactivateOnManualSleep)
                            .font(.system(size: 12.5, weight: .medium))
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
                        .font(.system(size: 12.5, weight: .medium))

                        Text("当系统闲置超过设定阈值时，自动在鼠标原位产生微小 HID 微动，重置系统 `IOHIDSystem` 闲置计数器，降低基于系统 idle time 的 Away 判定。（注：若某些协作应用依赖独立服务端心跳或主动按键钩子，可能需要保持窗口前台活动）。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        if settings.caffeineKeepAppsActive {
                            Divider()

                            HStack {
                                Text("触发空闲阈值:")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .frame(width: 100, alignment: .leading)
                                Slider(value: $settings.caffeineIdleThreshold, in: 30...300, step: 15)
                                Text("\(Int(settings.caffeineIdleThreshold)) 秒")
                                    .frame(width: 45, alignment: .trailing)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                        }
                    }
                    .padding(8)
                }

                // 4. 底层技术与原理
                GroupBox(label: Label("系统原理与电源管理说明", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **原生 IOKit 电源断言**：通过 macOS 原生 `IOKit.pwr_mgt` 的 `kIOPMAssertPreventUserIdleDisplaySleep` 向电源管理总线注册临时断言，超低能耗且不损伤电池寿命。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                        Text("• **安全释放机制 (Fail-Safe)**：CalmBar 退出、重启或系统锁屏切换用户时，将自动释放所有电源断言并暂停微动，确保节能策略正常。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }

    private func durationPresetButton(title: String, minutes: Int) -> some View {
        Button(title) {
            let seconds = minutes > 0 ? TimeInterval(minutes * 60) : 0
            caffeine.activate(withTimeout: seconds)
        }
        .buttonStyle(.bordered)
        .font(.system(size: 12, weight: .medium))
        .controlSize(.small)
    }
}
