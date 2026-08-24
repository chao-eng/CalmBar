import SwiftUI
import CalmBarKit

public struct SettingsView: View {
    @ObservedObject private var statusBarManager = StatusBarManager.shared
    @ObservedObject private var helper = HelperClient.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    @State private var selectedTab: SettingsTab? = StatusBarManager.shared.selectedSettingsTab
    @State private var searchText: String = ""

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 165, ideal: 185, max: 220)
        } detail: {
            detailContent
                .frame(minWidth: 500, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 520)
        .onChange(of: statusBarManager.selectedSettingsTab) { _, newTab in
            if selectedTab != newTab {
                selectedTab = newTab
                statusBarManager.updateSettingsWindowTitle(newTab.titleZH)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if let newTab = newTab {
                if statusBarManager.selectedSettingsTab != newTab {
                    statusBarManager.selectedSettingsTab = newTab
                }
                statusBarManager.updateSettingsWindowTitle(newTab.titleZH)
            }
        }
        .onAppear {
            if selectedTab == nil {
                selectedTab = statusBarManager.selectedSettingsTab
            }
            if let tab = selectedTab {
                statusBarManager.updateSettingsWindowTitle(tab.titleZH)
            }
        }
    }

    // MARK: - Sidebar View
    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            // Categorized Settings Sections
            ForEach(SettingsCategory.allCases) { category in
                let filteredTabs = category.tabs.filter { $0.matchesSearch(searchText) }
                if !filteredTabs.isEmpty {
                    Section {
                        ForEach(filteredTabs) { tab in
                            NavigationLink(value: tab) {
                                sidebarItemRow(for: tab)
                            }
                        }
                    } header: {
                        Text(category.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索设置")
    }

    // MARK: - Sidebar Item Row
    @ViewBuilder
    private func sidebarItemRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 10) {
            SettingsIconBadge(
                icon: tab.icon,
                gradientColors: tab.gradientColors,
                size: 24,
                cornerRadius: 6,
                iconScale: 0.58
            )

            Text(tab.titleZH)
                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundColor(.primary)

            Spacer()

            // Badges / Warning dots
            if tab == .permissions && (!permissionManager.accessibilityGranted || !permissionManager.helperInstalled) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
            } else if (tab == .thermal || tab == .battery) && (!helper.isHelperAvailable || helper.needsHelperUpdate) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Content View
    @ViewBuilder
    private var detailContent: some View {
        if let currentTab = selectedTab {
            VStack(spacing: 0) {
                // 顶栏 38pt 紧凑占位，标题底部/分割线严格水平对齐侧边栏搜索框顶部
                Color.clear
                    .frame(height: 38)

                Divider()
                    .opacity(0.4)

                // 下方滚动内容区
                Group {
                    switch currentTab {
                    case .thermal:
                        ThermalSettingsTab()
                    case .battery:
                        BatterySettingsTab()
                    case .menuBar:
                        MenuBarSettingsTab()
                    case .scroll:
                        ScrollSettingsTab()
                    case .caffeine:
                        CaffeineSettingsTab()
                    case .noTunes:
                        NoTunesSettingsTab()
                    case .clipboard:
                        ClipboardSettingsTab()
                    case .translation:
                        TranslationSettingsTab()
                    case .ocr:
                        OCRSettingsTab()
                    case .cleaner:
                        CleanerSettingsTab()
                    case .permissions:
                        PermissionCenterView()
                    case .gatekeeper:
                        GatekeeperUnlockerView()
                    case .general:
                        GeneralSettingsTab()
                    }
                }
                .id(currentTab)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("请从左侧选择一个功能设置")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
