import SwiftUI
import CalmBarKit

public struct PopoverContentView: View {
    @ObservedObject private var dashboard = DashboardViewModel.shared
    @ObservedObject private var featureManager = FeatureManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var menuBar = MenuBarOrganizer.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var caffeine = CaffeineManager.shared
    @ObservedObject private var batteryMonitor = BatteryMonitor.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared
    @ObservedObject private var ocr = OCRManager.shared

    @State private var isInstallingHelper = false
    @State private var helperInstallMessage: String?

    public var openSettingsAction: (SettingsTab) -> Void = { _ in }

    public init(openSettingsAction: @escaping (SettingsTab) -> Void = { _ in }) {
        self.openSettingsAction = openSettingsAction
    }

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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            if !dashboard.isSMCConnected {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("无 SMC 驱动")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if dashboard.safetyAction != .none {
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("打开命令面板 (Command Palette)")
        }
    }

    // MARK: - Permission Banners
    @ViewBuilder
    private var permissionBanners: some View {
        if dashboard.needsHelperAttention {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(helper.needsHelperUpdate ? "特权助手需更新" : "特权助手未激活")
                        .font(.system(size: 11, weight: .semibold))
                    Text(dashboard.helperAttentionMessage)
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

    // MARK: - Quick Action Item Enums
    private enum QuickToolItem: Hashable {
        case ocr
        case translation
        case clipboard
        case cleaner
        case gatekeeper
    }

    private enum GuardianItem: Hashable {
        case caffeine
        case battery
        case scrollReverser
        case noTunes
        case menuBar
    }

    private var activeQuickTools: [QuickToolItem] {
        var items: [QuickToolItem] = []
        if settings.popoverShowOCR { items.append(.ocr) }
        if settings.popoverShowTranslation { items.append(.translation) }
        if settings.popoverShowClipboard { items.append(.clipboard) }
        if settings.popoverShowCleaner { items.append(.cleaner) }
        if settings.popoverShowGatekeeper { items.append(.gatekeeper) }
        return items
    }

    private var activeGuardians: [GuardianItem] {
        var items: [GuardianItem] = []
        if settings.popoverShowCaffeine { items.append(.caffeine) }
        if settings.popoverShowBattery && batteryMonitor.hasBattery { items.append(.battery) }
        if settings.popoverShowScrollReverser { items.append(.scrollReverser) }
        if settings.popoverShowNoTunes { items.append(.noTunes) }
        if settings.popoverShowMenuBar { items.append(.menuBar) }
        return items
    }

    // MARK: - Quick Actions Section
    @ViewBuilder
    private var quickActionsSection: some View {
        if !activeQuickTools.isEmpty || !activeGuardians.isEmpty {
            VStack(spacing: 8) {
                quickToolsSection
                guardiansSection
            }
        }
    }

    // MARK: - Quick Tools Grid
    @ViewBuilder
    private var quickToolsSection: some View {
        let tools = activeQuickTools
        if !tools.isEmpty {
            HStack(spacing: 6) {
                ForEach(tools, id: \.self) { tool in
                    quickToolTileView(for: tool)
                }
            }
        }
    }

    @ViewBuilder
    private func quickToolTileView(for item: QuickToolItem) -> some View {
        switch item {
        case .ocr:
            ToolTileButton(
                icon: "text.viewfinder",
                title: "截屏识字",
                color: .blue,
                action: {
                    ocr.startCaptureAndRecognize()
                }
            )
            .contextMenu {
                Button("打开 OCR 历史记录") {
                    StatusBarManager.shared.closePopover()
                    OCRHistoryWindowController.shared.show()
                }
            }
            .help("选区截图识字与二维码解析 (右键打开历史)")

        case .translation:
            ToolTileButton(
                icon: "character.bubble.fill",
                title: "AI 翻译",
                color: .blue,
                action: {
                    StatusBarManager.shared.closePopover()
                    TranslationManager.shared.translateFromClipboard()
                }
            )
            .contextMenu {
                Button("打开翻译历史记录") {
                    StatusBarManager.shared.closePopover()
                    TranslationHistoryWindowController.shared.show()
                }
            }
            .help("翻译当前剪贴板文本 (双击 ⌘C 或 ⌥⌘T 快速触发，右键打开历史)")

        case .clipboard:
            ToolTileButton(
                icon: "doc.on.clipboard",
                title: "剪贴板",
                color: .cyan,
                action: {
                    StatusBarManager.shared.closePopover()
                    ClipboardHistoryWindowController.shared.show()
                }
            )
            .help(settings.clipboardHistoryEnabled ? "浏览剪贴板历史 (已记录 \(dashboard.clipboardCount) 条)" : "打开剪贴板历史 (监听已关闭)")

        case .cleaner:
            ToolTileButton(
                icon: "trash.fill",
                title: "清理中心",
                color: .purple,
                action: {
                    StatusBarManager.shared.closePopover()
                    CleanerWindowController.shared.show()
                }
            )
            .help("软件残留 · 开发缓存 · 孤立工作区清理")

        case .gatekeeper:
            ToolTileButton(
                icon: "lock.shield",
                title: "应用去隔离",
                color: .teal,
                action: {
                    openSettingsAction(.gatekeeper)
                }
            )
            .help("修复未签名或损坏应用提示")
        }
    }

    // MARK: - Guardians Grid
    @ViewBuilder
    private var guardiansSection: some View {
        let guardians = activeGuardians
        if !guardians.isEmpty {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(guardians, id: \.self) { guardian in
                    guardianCardView(for: guardian)
                }
            }
        }
    }

    @ViewBuilder
    private func guardianCardView(for item: GuardianItem) -> some View {
        switch item {
        case .caffeine:
            caffeineGuardianCard
        case .battery:
            batteryGuardianCard
        case .scrollReverser:
            scrollReverserGuardianCard
        case .noTunes:
            noTunesGuardianCard
        case .menuBar:
            menuBarGuardianCard
        }
    }

    private var caffeineGuardianCard: some View {
        HStack(spacing: 6) {
            CaffeineIconView(size: 18, isActive: caffeine.isActive)

            VStack(alignment: .leading, spacing: 1) {
                Text("防休眠")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(caffeine.isActive ? (caffeine.timeRemaining != nil ? caffeine.formattedTimeRemaining() : "无限期") : "已停用")
                    .font(.system(size: 9, weight: caffeine.isActive ? .semibold : .regular))
                    .foregroundColor(caffeine.isActive ? .brown : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

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
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 14)
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
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private var batteryGuardianCard: some View {
        HStack(spacing: 6) {
            BatteryIconView(
                size: 18,
                isCharging: batteryMonitor.isCharging,
                isBypassed: chargeManager.isChargingInhibited,
                isDischarging: chargeManager.operationStatus == .discharging
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("充电保护")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(settings.batteryChargeLimitEnabled ? (settings.batteryTopUpActive ? "临时充满" : "\(settings.batteryChargeLimit)% 旁路") : "已停用")
                    .font(.system(size: 9, weight: settings.batteryChargeLimitEnabled ? .semibold : .regular))
                    .foregroundColor(settings.batteryChargeLimitEnabled ? .accentColor : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if settings.batteryChargeLimitEnabled {
                Button(action: {
                    chargeManager.toggleTopUp()
                }) {
                    Image(systemName: settings.batteryTopUpActive ? "bolt.slash" : "bolt.badge.checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(settings.batteryTopUpActive ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(settings.batteryTopUpActive ? "取消单次充至100%" : "临时充至 100%")
            }

            Toggle("", isOn: $settings.batteryChargeLimitEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(.accentColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private var scrollReverserGuardianCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 13))
                .foregroundStyle(.teal)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("自然滚动")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(settings.scrollReverserEnabled ? "鼠标反转" : "已停用")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Toggle("", isOn: $settings.scrollReverserEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(.accentColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private var noTunesGuardianCard: some View {
        HStack(spacing: 6) {
            NoTunesIconView(size: 18)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Music 拦截")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(settings.noTunesEnabled ? "拦截中" : "已暂停")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Toggle("", isOn: $settings.noTunesEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(.accentColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private var menuBarGuardianCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 13))
                .foregroundStyle(.indigo)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("菜单收纳")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(menuBar.isCollapsed ? "已收纳" : "已展开")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Button(action: {
                menuBar.toggleExpandCollapse()
            }) {
                Text(menuBar.isCollapsed ? "展开" : "折叠")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
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

// MARK: - Tool Tile Button Component
private struct ToolTileButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
