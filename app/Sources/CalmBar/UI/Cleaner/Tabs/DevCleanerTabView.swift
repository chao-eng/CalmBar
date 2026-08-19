import SwiftUI
import AppKit

public struct DevCleanerTabView: View {
    @ObservedObject private var manager = CleanerManager.shared
    @State private var isOrphanCollapsed: Bool = false
    @State private var isPipCollapsed: Bool = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Stats Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("开发环境缓存占用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(manager.formattedTotalDevCacheSize)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        manager.refreshDevCaches()
                        manager.refreshOrphanedWorkspaces()
                    } label: {
                        HStack(spacing: 4) {
                            if manager.isScanningDev || manager.isScanningWorkspaces {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("刷新扫描")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Section 1: Orphaned Workspaces
                    if !manager.orphanedWorkspaces.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "macwindow.badge.plus")
                                    .foregroundStyle(.orange)
                                Text("IDE 孤立工作区缓存 (项目源码已被删除)")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text(manager.formattedTotalOrphanedSize)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.orange)

                                Button("一键清理全部") {
                                    manager.cleanAllOrphanedWorkspaces()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.mini)
                            }

                            Divider()

                            VStack(spacing: 2) {
                                ForEach(manager.orphanedWorkspaces) { ws in
                                    OrphanedWorkspaceView(item: ws) {
                                        manager.cleanOrphanedWorkspace(ws)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // MARK: - Section 2: Developer Environment Caches
                    ForEach(manager.devCategories) { category in
                        let items = manager.devPathItems.filter { $0.envName == category.name }
                        if !items.isEmpty {
                            let totalCategorySize = items.reduce(0) { $0 + $1.sizeBytes }
                            let formattedCatSize = ByteCountFormatter.string(fromByteCount: totalCategorySize, countStyle: .file)

                            DisclosureGroup {
                                VStack(spacing: 2) {
                                    ForEach(items) { item in
                                        DevPathRowView(
                                            item: item,
                                            onClearContents: { manager.clearDevPathContents(item) },
                                            onTrashFolder: { manager.trashDevPath(item) }
                                        )
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack {
                                    Image(systemName: category.iconName)
                                        .foregroundStyle(.purple)
                                        .frame(width: 18)
                                    Text(category.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("(\(items.count) 项)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formattedCatSize)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // MARK: - Section 3: Pip Packages
                    DisclosureGroup(isExpanded: $isPipCollapsed) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Python: \(manager.pythonPath)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("扫描包") {
                                    manager.refreshPipPackages()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            if manager.isScanningPip {
                                ProgressView("正在扫描 Pip 全局包...")
                                    .controlSize(.small)
                            } else if manager.pipPackages.isEmpty {
                                Text("暂未扫描或未安装第三方包")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(manager.pipPackages) { pkg in
                                    HStack {
                                        Text(pkg.name)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        Text("v\(pkg.version)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("卸载") {
                                            Task {
                                                _ = await manager.uninstallPipPackage(pkg)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(.blue)
                            Text("Pip Python 全局包管理")
                                .font(.system(size: 13, weight: .semibold))
                            if !manager.pipPackages.isEmpty {
                                Text("(\(manager.pipPackages.count) 个包)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(14)
            }
        }
    }
}
