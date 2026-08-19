import SwiftUI
import CalmBarKit

public struct PopoverContentView: View {
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var menuBar = MenuBarOrganizer.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var caffeine = CaffeineManager.shared
    @ObservedObject private var batteryMonitor = BatteryMonitor.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared
    @ObservedObject private var ocr = OCRManager.shared
    @ObservedObject private var ocrHistory = OCRHistoryManager.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryManager.shared

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
            if settings.popoverShowGauges {
                gaugesSection
            }
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

            Button(action: {
                CommandPaletteWindowController.shared.showWindow()
            }) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("打开命令面板 (Command Palette)")
        }
    }

    // MARK: - Permission Banners
    @ViewBuilder
    private var permissionBanners: some View {
        if !helper.isHelperAvailable || helper.needsHelperUpdate {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(helper.needsHelperUpdate ? "特权助手需更新" : "特权助手未激活")
                        .font(.system(size: 11, weight: .semibold))
                    Text(helper.needsHelperUpdate ? "更新助手以支持电池充电上限阻断" : "温控与充电上限需要特权服务")
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
                            helper.checkHelperStatus()
                            chargeManager.evaluateChargingPolicy()
                        } else {
                            helperInstallMessage = err
                        }
                    }
                }) {
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

    // MARK: - Quick Action Item Enum
    private enum QuickActionItem {
        case menuBar
        case scrollReverser
        case noTunes
        case caffeine
        case battery
        case gatekeeper
        case ocr
        case clipboard
        case cleaner
    }

    private var activeQuickActions: [QuickActionItem] {
        var items: [QuickActionItem] = []
        if settings.popoverShowMenuBar { items.append(.menuBar) }
        if settings.popoverShowScrollReverser { items.append(.scrollReverser) }
        if settings.popoverShowNoTunes { items.append(.noTunes) }
        if settings.popoverShowCaffeine { items.append(.caffeine) }
        if settings.popoverShowBattery && batteryMonitor.hasBattery { items.append(.battery) }
        if settings.popoverShowGatekeeper { items.append(.gatekeeper) }
        if settings.popoverShowOCR { items.append(.ocr) }
        if settings.popoverShowClipboard { items.append(.clipboard) }
        if settings.popoverShowCleaner { items.append(.cleaner) }
        return items
    }

    // MARK: - Quick Actions Section
    @ViewBuilder
    private var quickActionsSection: some View {
        let items = activeQuickActions
        if !items.isEmpty {
            GroupBox {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        quickActionRowView(for: item)
                    }
                }
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private func quickActionRowView(for item: QuickActionItem) -> some View {
        switch item {
        case .menuBar:
            menuBarRow
        case .scrollReverser:
            scrollReverserRow
        case .noTunes:
            noTunesRow
        case .caffeine:
            caffeineRow
        case .battery:
            batteryChargeLimitRow
        case .gatekeeper:
            gatekeeperRow
        case .ocr:
            ocrRow
        case .clipboard:
            clipboardRow
        case .cleaner:
            cleanerRow
        }
    }

    private var cleanerRow: some View {
        HStack {
            Image(systemName: "trash.fill")
                .foregroundStyle(.purple)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("软件与开发清理")
                    .font(.system(size: 12, weight: .medium))
                Text("软件残留 · 开发缓存 · 孤立工作区")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button(action: {
                StatusBarManager.shared.closePopover()
                CleanerWindowController.shared.show()
            }) {
                Text("打开清理")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.purple)
            .help("打开 CalmBar 卸载与清理中心")
        }
    }

    // MARK: - Quick Action Row Views
    private var clipboardRow: some View {
        HStack {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.cyan)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("剪贴板历史")
                    .font(.system(size: 12, weight: .medium))
                if settings.clipboardHistoryEnabled {
                    Text("已记录 \(clipboardHistory.items.count) 条内容")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text("监听已关闭")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            Button(action: {
                StatusBarManager.shared.closePopover()
                ClipboardHistoryWindowController.shared.show()
            }) {
                Text("浏览历史")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.cyan)
            .help("打开剪贴板历史管理窗口")
        }
    }

    // MARK: - Quick Action Row Views
    private var ocrRow: some View {
        HStack {
            Image(systemName: "text.viewfinder")
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("屏幕文字识别")
                    .font(.system(size: 12, weight: .medium))
                if let status = ocr.statusMessage {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                } else if let latest = ocr.latestResult {
                    Text(latest.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("选区截图识字 · 二维码解析")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            HStack(spacing: 6) {
                Button(action: {
                    StatusBarManager.shared.closePopover()
                    OCRHistoryWindowController.shared.show()
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("查看识别历史记录")

                Button(action: {
                    ocr.startCaptureAndRecognize()
                }) {
                    Text("截屏识字")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
    }

    // MARK: - Quick Action Row Views
    private var menuBarRow: some View {
        HStack {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.indigo)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("菜单栏收纳")
                    .font(.system(size: 12, weight: .medium))
                Text(menuBar.isCollapsed ? "已收纳折叠" : "已展开显示")
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
    }

    private var scrollReverserRow: some View {
        HStack {
            Image(systemName: "computermouse.fill")
                .foregroundStyle(.teal)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("鼠标自然滚动")
                    .font(.system(size: 12, weight: .medium))
                Text(settings.scrollReverserEnabled ? "鼠标反转 · 触控板原生" : "已停用")
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
    }

    private var noTunesRow: some View {
        HStack {
            NoTunesIconView(size: 20)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("Apple Music 拦截")
                    .font(.system(size: 12, weight: .medium))
                Text(settings.noTunesEnabled ? "已开启防误触拦截" : "已暂停拦截")
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
    }

    private var caffeineRow: some View {
        HStack {
            CaffeineIconView(size: 20, isActive: caffeine.isActive)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("系统防休眠")
                        .font(.system(size: 12, weight: .medium))
                    if caffeine.isActive {
                        Text(caffeine.timeRemaining != nil ? "\(caffeine.formattedTimeRemaining())" : "无限期")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.brown.opacity(0.12))
                            .foregroundStyle(Color.brown)
                            .cornerRadius(3)
                    }
                }
                Text(caffeine.isActive ? (settings.caffeineKeepAppsActive ? "防休眠 · 防离开工作中" : "已阻止系统与显示器休眠") : "点击开启防休眠 (支持定时)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()

            Menu {
                Button("无限期保持清醒") {
                    caffeine.activate(withTimeout: nil)
                }
                Divider()
                Button("保持清醒 5 分钟") {
                    caffeine.activate(withTimeout: 5 * 60)
                }
                Button("保持清醒 15 分钟") {
                    caffeine.activate(withTimeout: 15 * 60)
                }
                Button("保持清醒 30 分钟") {
                    caffeine.activate(withTimeout: 30 * 60)
                }
                Button("保持清醒 1 小时") {
                    caffeine.activate(withTimeout: 60 * 60)
                }
                Button("保持清醒 2 小时") {
                    caffeine.activate(withTimeout: 120 * 60)
                }
                Button("保持清醒 5 小时") {
                    caffeine.activate(withTimeout: 300 * 60)
                }
                if caffeine.isActive {
                    Divider()
                    Button("停止保持清醒", role: .destructive) {
                        caffeine.deactivate()
                    }
                }
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
            .help("选择防休眠时长")

            Toggle("", isOn: Binding(
                get: { caffeine.isActive },
                set: { if $0 { caffeine.toggle() } else { caffeine.deactivate() } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .tint(.accentColor)
        }
    }

    private var batteryChargeLimitRow: some View {
        HStack {
            BatteryIconView(
                size: 20,
                isCharging: batteryMonitor.isCharging,
                isBypassed: chargeManager.isChargingInhibited,
                isDischarging: chargeManager.operationStatus == .discharging
            )
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("充电上限 \(settings.batteryChargeLimit)%")
                        .font(.system(size: 12, weight: .medium))

                    if settings.batteryTopUpActive {
                        Text("充至100%")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .cornerRadius(3)
                    } else if chargeManager.operationStatus == .discharging {
                        Text("放电中")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(3)
                    } else if chargeManager.isChargingInhibited {
                        Text("旁路供电")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(3)
                    }
                }
                Text(chargeManager.lastStatusMessage.isEmpty ? "电量 \(batteryMonitor.currentPercentage)%" : chargeManager.lastStatusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()

            if settings.batteryChargeLimitEnabled {
                Button(action: {
                    chargeManager.toggleTopUp()
                }) {
                    Text(settings.batteryTopUpActive ? "取消" : "充至100%")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Toggle("", isOn: $settings.batteryChargeLimitEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(.accentColor)
        }
    }

    private var gatekeeperRow: some View {
        HStack {
            GatekeeperIconView(size: 20)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("应用去隔离")
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
