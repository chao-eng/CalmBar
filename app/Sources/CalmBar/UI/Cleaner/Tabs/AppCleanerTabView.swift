import SwiftUI
import AppKit

public struct AppCleanerTabView: View {
    @ObservedObject private var manager = CleanerManager.shared
    @State private var showConfirmSheet = false
    @State private var isUninstalling = false
    @State private var uninstallMessage: String?
    @State private var isTargetedForDrop = false

    public init() {}

    public var body: some View {
        HSplitView {
            // MARK: - Left App List
            VStack(spacing: 0) {
                // Search & Filter Header
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索应用名称或 Bundle ID...", text: $manager.appSearchQuery)
                            .textFieldStyle(.plain)
                        if !manager.appSearchQuery.isEmpty {
                            Button {
                                manager.appSearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Picker("排序", selection: $manager.appSortOption) {
                            ForEach(AppSortOption.allCases) { opt in
                                Text(opt.titleZH).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)

                        Spacer()

                        Button {
                            manager.refreshAllApps()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("重新扫描应用")
                        .disabled(manager.isScanningApps)
                    }
                }
                .padding(10)
                .background(.bar)

                Divider()

                // List
                if manager.isScanningApps && manager.apps.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                        Text("正在扫描已安装应用...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if manager.filteredApps.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("未找到匹配的应用")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(manager.filteredApps) { app in
                                AppItemRowView(
                                    app: app,
                                    isSelected: manager.selectedApp?.id == app.id
                                )
                                .onTapGesture {
                                    manager.selectApp(app)
                                }
                            }
                        }
                        .padding(6)
                    }
                }

                Divider()

                // Footer count
                HStack {
                    Text("\(manager.filteredApps.count) 款应用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if manager.isScanningApps {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)
            }
            .frame(minWidth: 260, idealWidth: 290, maxWidth: 360)

            // MARK: - Right Detail & Remnants
            if let selectedApp = manager.selectedApp {
                VStack(spacing: 0) {
                    // App Header
                    HStack(alignment: .center, spacing: 14) {
                        Image(nsImage: selectedApp.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(selectedApp.appName)
                                    .font(.system(size: 16, weight: .bold))

                                Text(selectedApp.architecture.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(selectedApp.architecture.badgeColor.opacity(0.15))
                                    .foregroundStyle(selectedApp.architecture.badgeColor)
                                    .clipShape(Capsule())

                                if selectedApp.isSystemApp {
                                    Text("系统应用")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                            }

                            Text("\(selectedApp.bundleIdentifier) • v\(selectedApp.version)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Text(selectedApp.path)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.selectFile(selectedApp.path, inFileViewerRootedAtPath: "")
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.bordered)
                        .help("在 Finder 中打开")
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.04))

                    Divider()

                    // Running Warning
                    if selectedApp.isRunning {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("应用当前正在运行中，清理前将自动安全退出")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("退出应用") {
                                Task {
                                    _ = await AppUninstaller.shared.terminateApp(bundleIdentifier: selectedApp.bundleIdentifier)
                                    manager.refreshAllApps()
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                    }

                    // Associated Files List
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("关联文件与残留 (\(selectedApp.associatedItems.count + 1) 项)")
                                .font(.system(size: 12, weight: .bold))

                            Spacer()

                            if manager.isScanningAssociated {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("正在探测残留...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("全选") {
                                    setAllSelection(true)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)

                                Text("•")
                                    .foregroundStyle(.secondary)

                                Button("取消全选") {
                                    setAllSelection(false)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                        Divider()

                        ScrollView {
                            VStack(spacing: 4) {
                                // App Bundle row
                                HStack(spacing: 8) {
                                    Image(systemName: "app.badge.fill")
                                        .foregroundStyle(.blue)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("应用程序本体 (.app)")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(selectedApp.path)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(selectedApp.formattedBundleSize)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(Color.blue.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                // Associated Remnants rows
                                ForEach(bindingForAssociatedItems()) { $item in
                                    AssociatedFileRowView(item: $item)
                                }
                            }
                            .padding(10)
                        }
                    }

                    Divider()

                    // Bottom Action Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("预计释放空间")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(selectedApp.formattedTotalSelectedSize)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        Button {
                            showConfirmSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text("移入废纸篓")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedApp.isSystemApp ? Color.gray : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedApp.isSystemApp || isUninstalling)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("请从左侧选择一款应用，或将外部 .app 拖拽至此处分析")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "确认清理应用",
            isPresented: $showConfirmSheet,
            actions: {
                Button("将选中项移入废纸篓", role: .destructive) {
                    guard let app = manager.selectedApp else { return }
                    isUninstalling = true
                    Task {
                        let result = await manager.uninstallApp(app)
                        isUninstalling = false
                        uninstallMessage = result.message
                    }
                }
                Button("取消", role: .cancel) {}
            },
            message: {
                if let app = manager.selectedApp {
                    Text("确定要将 \(app.appName) 及其选中的关联文件（共 \(app.formattedTotalSelectedSize)）移入废纸篓吗？可在废纸篓中恢复。")
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.pathExtension == "app" {
                    DispatchQueue.main.async {
                        manager.handleDroppedApp(url: url)
                    }
                }
            }
            return true
        }
    }

    private func setAllSelection(_ select: Bool) {
        guard var app = manager.selectedApp else { return }
        for idx in app.associatedItems.indices {
            app.associatedItems[idx].isSelected = select
        }
        manager.selectedApp = app
    }

    private func bindingForAssociatedItems() -> Binding<[AssociatedFileItem]> {
        Binding(
            get: { manager.selectedApp?.associatedItems ?? [] },
            set: { newItems in
                manager.selectedApp?.associatedItems = newItems
            }
        )
    }
}
