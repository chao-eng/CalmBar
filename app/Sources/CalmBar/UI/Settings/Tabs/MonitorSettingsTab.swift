import AppKit
import SwiftUI
import UserNotifications

// MARK: - 系统监控设置（PRD §5.5）

public struct MonitorSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var monitor = SystemMonitorService.shared
    @ObservedObject private var alerts = MonitorAlertEngine.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeatureMasterToggleCard(
                    icon: SettingsTab.monitor.icon,
                    iconColors: SettingsTab.monitor.gradientColors,
                    title: "系统监控与告警",
                    activeSubtitle: "已激活 · 采样间隔 \(settings.systemMonitorSampleInterval)s · 菜单栏 \(settings.menuBarReadoutItems.count) 项",
                    inactiveSubtitle: "已停用 · 不采样、不发送告警，菜单栏仅保留原有图标",
                    isEnabled: $settings.systemMonitorEnabled
                )

                samplingGroup
                readoutGroup
                alertGroup
            }
            .padding(20)
        }
    }

    // MARK: 采样与显示

    private var samplingGroup: some View {
        GroupBox(label: Label("采样与显示", systemImage: "waveform.path.ecg")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("采样间隔")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 82, alignment: .leading)
                    Picker("", selection: $settings.systemMonitorSampleInterval) {
                        Text("1s").tag(1)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("历史范围")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 82, alignment: .leading)
                    Picker("", selection: $settings.systemMonitorHistoryWindow) {
                        Text("1 分钟").tag(60)
                        Text("5 分钟").tag(300)
                        Text("1 小时").tag(3600)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    Spacer()
                }

                Toggle("显示 GPU（不可读时自动隐藏）", isOn: $settings.systemMonitorShowGPU)
                    .font(.system(size: 12.5, weight: .medium))

                Text("面板关闭后自动降频至 3s；睡眠、锁屏或熄屏期间暂停采样，唤醒后重新对齐。历史仅保存在内存，退出即清空。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!settings.systemMonitorEnabled)
    }

    // MARK: 菜单栏读数

    private var readoutGroup: some View {
        GroupBox(label: Label("菜单栏读数（最多 3 项）", systemImage: "menubar.rectangle")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    readoutToggle("温度", id: "temperature")
                    readoutToggle("CPU %", id: "cpu")
                    readoutToggle("内存 %", id: "memory")
                    readoutToggle("网络", id: "network")
                    readoutToggle("磁盘 %", id: "disk")
                }

                Text("已选 \(settings.menuBarReadoutItems.count)/\(AppSettings.menuBarReadoutLimit) 项 · 超过 140pt 时按「温度 > CPU > 内存 > 网络 > 磁盘」自动省略末位。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "wind")
                        .font(.system(size: 12))
                    Text(previewText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!settings.systemMonitorEnabled)
    }

    private var previewText: String {
        let title = MenuBarReadout.title(
            sample: monitor.snapshot,
            temperature: Double(ThermalMonitor.shared.primaryTemp),
            thermalEnabled: settings.thermalEnabled,
            items: settings.menuBarReadoutItems,
            monitorEnabled: settings.systemMonitorEnabled
        )
        return title.isEmpty ? "仅显示图标" : title.trimmingCharacters(in: .whitespaces)
    }

    private func readoutToggle(_ title: String, id: String) -> some View {
        let selected = settings.menuBarReadoutItems.contains(id)
        let atLimit = settings.menuBarReadoutItems.count >= AppSettings.menuBarReadoutLimit
        return Toggle(title, isOn: Binding(
            get: { selected },
            set: { settings.setMenuBarReadoutItem(id, enabled: $0) }
        ))
        .toggleStyle(.checkbox)
        .font(.system(size: 12.5))
        .disabled(!selected && atLimit)
    }

    // MARK: 告警阈值

    private var alertGroup: some View {
        GroupBox(label: Label("告警阈值", systemImage: "bell.badge")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用阈值告警", isOn: $settings.monitorAlertsEnabled)
                    .font(.system(size: 12.5, weight: .medium))

                Divider()

                cpuAlertRow
                memoryAlertRow
                diskAlertRow
                batteryAlertRow
                temperatureAlertRow

                Divider()

                HStack(spacing: 8) {
                    Text("提醒冷却")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 70, alignment: .leading)
                    Picker("", selection: $settings.monitorAlertCooldownMinutes) {
                        Text("10 分钟").tag(10)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                        Text("120 分钟").tag(120)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 130)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("通知权限")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 70, alignment: .leading)
                    Text(authorizationText)
                        .font(.system(size: 12))
                        .foregroundStyle(authorizationColor)
                    Spacer()
                    Button(authorizationActionTitle) {
                        handleAuthorizationAction()
                    }
                    .font(.system(size: 12))
                }

                Text("每类告警需连续 2 个采样点确认；睡眠、锁屏期间不发送通知；通知不可用时降级为面板顶部橙色胶囊。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)

                HStack {
                    Spacer()
                    Button("重置默认阈值") {
                        resetThresholds()
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!settings.systemMonitorEnabled || !settings.monitorAlertsEnabled)
        }
    }

    private var cpuAlertRow: some View {
        HStack(spacing: 6) {
            Toggle("CPU 持续 ≥", isOn: $settings.monitorAlertCPU)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .frame(width: 116, alignment: .leading)

            TextField("", value: $settings.monitorAlertCPUThreshold, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Text("%").font(.system(size: 12)).foregroundStyle(.secondary)

            Text("超过").font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("", selection: $settings.monitorAlertCPUDuration) {
                Text("10s").tag(10)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("120s").tag(120)
            }
            .labelsHidden()
            .frame(width: 76)
            Spacer()
        }
    }

    private var memoryAlertRow: some View {
        HStack(spacing: 6) {
            Toggle("内存压力持续", isOn: $settings.monitorAlertMemory)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .frame(width: 116, alignment: .leading)

            Picker("", selection: $settings.monitorAlertMemoryDuration) {
                Text("10s").tag(10)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("120s").tag(120)
            }
            .labelsHidden()
            .frame(width: 76)
            Text("（内存压力等级为警告或严重时触发，与已用百分比无关）")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
    }

    private var diskAlertRow: some View {
        HStack(spacing: 6) {
            Toggle("磁盘剩余 <", isOn: $settings.monitorAlertDisk)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .frame(width: 116, alignment: .leading)

            TextField("", value: $settings.monitorAlertDiskFreeGB, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Text("GB").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var batteryAlertRow: some View {
        HStack(spacing: 6) {
            Toggle("电池低于", isOn: $settings.monitorAlertBattery)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .frame(width: 116, alignment: .leading)

            TextField("", value: $settings.monitorAlertBatteryThreshold, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Text("%（未接电源）").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var temperatureAlertRow: some View {
        HStack(spacing: 6) {
            Toggle("温度 ≥", isOn: $settings.monitorAlertTemperature)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .frame(width: 116, alignment: .leading)

            TextField("", value: $settings.monitorAlertTemperatureThreshold, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Text("°C（复用温控）").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: 通知权限

    private var authorizationText: String {
        switch alerts.notificationAuthorization {
        case .authorized, .provisional: "已授权"
        case .denied: "已拒绝（降级为面板胶囊）"
        case .notDetermined: "未请求"
        @unknown default: "未知"
        }
    }

    private var authorizationColor: Color {
        switch alerts.notificationAuthorization {
        case .authorized, .provisional: .green
        case .denied: .orange
        default: .secondary
        }
    }

    private var authorizationActionTitle: String {
        switch alerts.notificationAuthorization {
        case .authorized, .provisional: "去管理"
        case .denied: "去系统设置"
        default: "请求权限"
        }
    }

    private func handleAuthorizationAction() {
        switch alerts.notificationAuthorization {
        case .authorized, .provisional, .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        default:
            alerts.requestAuthorization()
        }
    }

    private func resetThresholds() {
        settings.monitorAlertCPUThreshold = 90
        settings.monitorAlertCPUDuration = 60
        settings.monitorAlertMemoryDuration = 30
        settings.monitorAlertDiskFreeGB = 10
        settings.monitorAlertBatteryThreshold = 20
        settings.monitorAlertTemperatureThreshold = 95
        settings.monitorAlertCooldownMinutes = 30
    }
}
