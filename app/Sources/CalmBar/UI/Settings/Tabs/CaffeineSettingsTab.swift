import SwiftUI
import CalmBarKit

public struct CaffeineSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var caffeine = CaffeineManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .caffeine)

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

                        Text("当系统闲置超过设定阈值时，自动在鼠标原位产生微小 HID 微动，重置系统 `IOHIDSystem` 闲置计数器，降低基于系统 idle time 的 Away 判定。（注：若某些协作应用依赖独立服务端心跳或主动按键钩子，可能需要保持窗口前台活动）。")
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
                        Text("• **原生 IOKit 电源断言**：通过 macOS 原生 `IOKit.pwr_mgt` 的 `kIOPMAssertPreventUserIdleDisplaySleep` 向电源管理总线注册临时断言，超低能耗且不损伤电池寿命。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("• **安全释放机制 (Fail-Safe)**：CalmBar 退出、重启或系统锁屏切换用户时，将自动释放所有电源断言并暂停微动，确保节能策略正常。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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
        .controlSize(.small)
    }
}
