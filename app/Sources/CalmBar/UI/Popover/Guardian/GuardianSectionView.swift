import SwiftUI
import CalmBarKit

// MARK: - M3 守护分区：单列卡片 + 辅助功能横幅

struct GuardianSectionView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var caffeine = CaffeineManager.shared
    @ObservedObject private var batteryMonitor = BatteryMonitor.shared
    @ObservedObject private var chargeManager = BatteryChargeManager.shared
    @ObservedObject private var menuBar = MenuBarOrganizer.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared

    var viewportHeight: CGFloat
    var stressExtraHeight: CGFloat = 0
    var allHidden: Bool = false
    var onMeasure: ((CGFloat) -> Void)?

    private var visibleItems: [PopoverVisibilityItem] {
        guard !allHidden else { return [] }
        return PopoverVisibilityGroup.guardian.items.filter { item in
            if item == .battery && !batteryMonitor.hasBattery { return false }
            return item.isEnabled(settings)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PopoverLayout.blockGap) {
                if !scroll.hasAccessibilityPermission {
                    accessibilityBanner
                }
                ForEach(visibleItems) { item in
                    card(for: item)
                }
                if visibleItems.isEmpty {
                    PopoverEmptyState(group: .guardian)
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

    @ViewBuilder
    private func card(for item: PopoverVisibilityItem) -> some View {
        switch item {
        case .caffeine: caffeineCard
        case .battery: batteryCard
        case .scrollReverser: scrollReverserCard
        case .noTunes: noTunesCard
        case .menuBar: menuBarCard
        default: EmptyView()
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

    // MARK: 辅助功能横幅（M3 从温控拆出）

    private var accessibilityBanner: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.secondary)
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
            .tint(PopoverPalette.guardianAccent)
        }
        .padding(8)
        .background(PopoverPalette.surfaceWell)
        .cornerRadius(8)
    }

    // MARK: 防休眠

    private var caffeineCard: some View {
        HStack(spacing: 6) {
            CaffeineIconView(size: 18, isActive: caffeine.isActive, monochrome: false)

            VStack(alignment: .leading, spacing: 1) {
                Text("防休眠")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(caffeine.isActive ? (caffeine.timeRemaining != nil ? caffeine.formattedTimeRemaining() : "无限期") : "已停用")
                    .font(.system(size: 9, weight: caffeine.isActive ? .semibold : .regular))
                    .foregroundColor(caffeine.isActive ? .primary : .secondary)
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
            .accessibilityLabel("选择防休眠时长")

            Toggle("", isOn: Binding(
                get: { caffeine.isActive },
                set: { newValue in
                    if newValue {
                        caffeine.toggle()
                    } else {
                        caffeine.deactivate()
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .tint(PopoverPalette.guardianAccent)
            .accessibilityLabel("防休眠开关")
        }
        .guardianCardStyle()
    }

    // MARK: 充电保护

    private var batteryCard: some View {
        HStack(spacing: 6) {
            BatteryIconView(
                size: 18,
                isCharging: batteryMonitor.isCharging,
                isBypassed: chargeManager.isChargingInhibited,
                isDischarging: chargeManager.operationStatus == .discharging,
                monochrome: false
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("充电保护")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(settings.batteryChargeLimitEnabled ? (settings.batteryTopUpActive ? "临时充满" : "\(settings.batteryChargeLimit)% 旁路") : "已停用")
                    .font(.system(size: 9, weight: settings.batteryChargeLimitEnabled ? .semibold : .regular))
                    .foregroundColor(settings.batteryChargeLimitEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if settings.batteryChargeLimitEnabled {
                Button(action: {
                    chargeManager.toggleTopUp()
                }) {
                    Image(systemName: settings.batteryTopUpActive ? "bolt.slash" : "bolt.badge.checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(settings.batteryTopUpActive ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(settings.batteryTopUpActive ? "取消单次充至100%" : "临时充至 100%")
                .accessibilityLabel(settings.batteryTopUpActive ? "取消单次充至100%" : "临时充至 100%")
            }

            Toggle("", isOn: $settings.batteryChargeLimitEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(PopoverPalette.guardianAccent)
                .accessibilityLabel("充电保护开关")
        }
        .guardianCardStyle()
    }

    // MARK: 自然滚动

    private var scrollReverserCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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
                .tint(PopoverPalette.guardianAccent)
                .accessibilityLabel("自然滚动开关")
        }
        .guardianCardStyle()
    }

    // MARK: Music 拦截

    private var noTunesCard: some View {
        HStack(spacing: 6) {
            NoTunesIconView(size: 18, monochrome: false)
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
                .tint(PopoverPalette.guardianAccent)
                .accessibilityLabel("Music 拦截开关")
        }
        .guardianCardStyle()
    }

    // MARK: 菜单收纳

    private var menuBarCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 13))
                .foregroundStyle(settings.menuBarOrganizerEnabled ? .primary : .secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("菜单收纳")
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
                Text(settings.menuBarOrganizerEnabled ? (menuBar.isCollapsed ? "已收纳" : "已展开") : "已停用")
                    .font(.system(size: 9))
                    .foregroundColor(settings.menuBarOrganizerEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if settings.menuBarOrganizerEnabled {
                Button(action: {
                    menuBar.toggleExpandCollapse()
                }) {
                    Image(systemName: menuBar.isCollapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(menuBar.isCollapsed ? "点击展开菜单栏图标" : "点击折叠隐藏菜单栏图标")
                .accessibilityLabel(menuBar.isCollapsed ? "展开菜单栏图标" : "折叠菜单栏图标")
            }

            Toggle("", isOn: $settings.menuBarOrganizerEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(PopoverPalette.guardianAccent)
                .accessibilityLabel("菜单收纳开关")
        }
        .guardianCardStyle()
    }
}

// MARK: - 单列卡片外观

private extension View {
    func guardianCardStyle() -> some View {
        self
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PopoverPalette.surfaceCard)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(PopoverPalette.separatorHairline, lineWidth: 0.5)
            }
    }
}
