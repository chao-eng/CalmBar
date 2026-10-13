import SwiftUI

public struct LaunchManagerMainContainerView: View {
    @ObservedObject private var manager = LaunchManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var windowController = LaunchManagerWindowController.shared

    @State private var searchQuery: String = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedItemID: String?
    @State private var showNewAgentSheet: Bool = false
    @State private var showGuideSheet: Bool = false

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case running = "仅运行中"
        case disabled = "仅停用"
        case crashing = "仅异常"

        var id: String { rawValue }
    }

    private enum AllScopeFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case user = "用户级"
        case global = "全局"
        case daemon = "系统级"

        var id: String { rawValue }
    }

    @State private var allScopeFilter: AllScopeFilter = .all

    public init(initialTab: LaunchManagerTab = .all) {
        LaunchManagerWindowController.shared.activeTab = initialTab
    }

    private var activeTab: LaunchManagerTab {
        get { windowController.activeTab }
        nonmutating set { windowController.activeTab = newValue }
    }

    private var currentScope: LaunchScope? {
        switch activeTab {
        case .all:
            switch allScopeFilter {
            case .all: return nil
            case .user: return .userAgent
            case .global: return .systemAgent
            case .daemon: return .systemDaemon
            }
        case .userAgents: return .userAgent
        case .globalAgents: return .systemAgent
        case .daemons: return .systemDaemon
        case .crontab, .crashLooping, .services, .backups: return nil
        }
    }

    private var filteredItems: [LaunchItem] {
        var result = manager.items

        if activeTab == .crashLooping {
            result = manager.crashLoopingItems
        } else if let scope = currentScope {
            result = result.filter { $0.scope == scope }
        }

        switch statusFilter {
        case .all:
            break
        case .running:
            result = result.filter { $0.isRunning }
        case .disabled:
            result = result.filter { !$0.isLoaded || $0.isDisabledByOverride }
        case .crashing:
            result = result.filter { $0.isCrashLooping() }
        }

        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.label.lowercased().contains(q) ||
                ($0.appName?.lowercased().contains(q) ?? false) ||
                $0.programArguments.joined(separator: " ").lowercased().contains(q)
            }
        }

        return result
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            contentView
        }
        .sheet(isPresented: $showNewAgentSheet) {
            NewAgentSheetView(
                onDismiss: { showNewAgentSheet = false },
                onCreated: { showNewAgentSheet = false }
            )
        }
        .sheet(isPresented: $showGuideSheet) {
            LaunchManagerGuideSheetView(
                onDismiss: { showGuideSheet = false }
            )
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List {
            Section("自启管理") {
                sidebarButton(tab: .all, count: manager.items.count)
                sidebarButton(tab: .userAgents, count: count(for: .userAgent))
                if settings.launchManagerShowSystemDaemons {
                    sidebarButton(tab: .globalAgents, count: count(for: .systemAgent))
                    sidebarButton(tab: .daemons, count: count(for: .systemDaemon))
                }
                sidebarButton(tab: .crontab, count: manager.cronJobs.count)
            }

            Section("健康与安全") {
                Button {
                    activeTab = .crashLooping
                } label: {
                    HStack {
                        Label(LaunchManagerTab.crashLooping.titleZH, systemImage: LaunchManagerTab.crashLooping.icon)
                            .foregroundStyle(manager.crashLoopingItems.isEmpty ? Color.primary : Color.red)
                        Spacer()
                        if !manager.crashLoopingItems.isEmpty {
                            Text("\(manager.crashLoopingItems.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(activeTab == .crashLooping ? Color.accentColor.opacity(0.15) : Color.clear)

                Button {
                    activeTab = .backups
                } label: {
                    HStack {
                        Label(LaunchManagerTab.backups.titleZH, systemImage: LaunchManagerTab.backups.icon)
                        Spacer()
                        if !manager.backups.isEmpty {
                            Text("\(manager.backups.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(activeTab == .backups ? Color.accentColor.opacity(0.15) : Color.clear)
            }

            if settings.launchManagerDeveloperModeEnabled {
                Section("开发者工具") {
                    Button {
                        activeTab = .services
                    } label: {
                        HStack {
                            Label(LaunchManagerTab.services.titleZH, systemImage: LaunchManagerTab.services.icon)
                            Spacer()
                            if !manager.listeningServices.isEmpty {
                                Text("\(manager.listeningServices.count)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(activeTab == .services ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarButton(tab: LaunchManagerTab, count: Int) -> some View {
        Button {
            activeTab = tab
        } label: {
            HStack {
                Label(tab.titleZH, systemImage: tab.icon)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(activeTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private func count(for scope: LaunchScope) -> Int {
        manager.items.filter { $0.scope == scope }.count
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var contentView: some View {
        switch activeTab {
        case .services:
            ListeningServicesView()
        case .backups:
            LaunchBackupCenterView()
        case .crontab:
            CrontabManagementView()
        default:
            itemsListView
        }
    }

    private var itemsListView: some View {
        VStack(spacing: 0) {
            // Toolbar Header
            HStack(spacing: 12) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索自启项或应用名...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 240)

                // 作用域筛选 (仅在全部聚合页显示)
                if activeTab == .all {
                    Picker("", selection: $allScopeFilter) {
                        ForEach(AllScopeFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                // 状态筛选 Picker
                Picker("", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                // + 新建自启
                Button {
                    showNewAgentSheet = true
                } label: {
                    Label("新建自启", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                // 机制说明
                Button {
                    showGuideSheet = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("查看 macOS 自启与后台服务机制说明")

                // 刷新
                Button {
                    Task { await manager.refreshAll() }
                } label: {
                    if manager.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isLoading)
            }
            .padding(12)
            .background(.ultraThinMaterial)

            Divider()

            // 作用域说明与知识引导条
            scopeTipBanner

            // Main Content Area with Split Inspector if an item is selected
            HSplitView {
                // Item list with protected minimum width
                Group {
                    if filteredItems.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("无匹配的启动项")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredItems) { item in
                            LaunchItemRowView(
                                item: item,
                                isSelected: selectedItemID == item.id,
                                onSelect: {
                                    selectedItemID = item.id
                                },
                                onToggle: {
                                    Task { await manager.toggleItem(item) }
                                },
                                onReload: {
                                    Task { await manager.reloadItem(item) }
                                },
                                onDelete: {
                                    Task { await manager.deleteItem(item) }
                                }
                            )
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 320, idealWidth: 380)

                // Detail Pane (if selected)：按 id 从最新列表派生，保证刷新后状态同步
                if let selectedItemID, let item = manager.items.first(where: { $0.id == selectedItemID }) {
                    LaunchItemDetailView(
                        item: item,
                        onClose: { self.selectedItemID = nil }
                    )
                    .frame(minWidth: 340, idealWidth: 390, maxWidth: 520)
                }
            }
        }
    }

    @ViewBuilder
    private var scopeTipBanner: some View {
        if let desc = currentScopeDescription {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)

                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button("机制对比说明") {
                    showGuideSheet = true
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()
        }
    }

    private var currentScopeDescription: String? {
        switch activeTab {
        case .all:
            return "全部自启与常驻项 · 聚合展示系统中生效的各级 LaunchAgent、LaunchDaemon 配置"
        case .userAgents:
            return "当前用户自启 (目录: ~/Library/LaunchAgents) · 仅当前用户登录时启动 · 适合个人专用的后台任务"
        case .globalAgents:
            return "全局自启项 (目录: /Library/LaunchAgents) · 任意账号登录时均启动 · 适合跨用户的共享辅助工具"
        case .daemons:
            return "系统守护服务 (目录: /Library/LaunchDaemons) · 电脑开机即以 root 特权启动 · 适合底层常驻服务"
        case .crontab:
            return "计划任务 (Crontab) · 基于类 Unix 经典 Cron 调度器的自动化脚本与周期命令"
        case .crashLooping:
            return "异常崩溃告警 · 检测到近期退出码异常 (如78-程序已被删除) 的后台任务 · 建议停用或清理"
        default:
            return nil
        }
    }
}
