import SwiftUI
import AppKit

public struct LaunchItemRowView: View {
    public let item: LaunchItem
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onToggle: () -> Void
    public let onRefresh: () -> Void
    public let onReload: () -> Void
    public let onDelete: () -> Void

    @State private var showDeleteConfirmation: Bool = false

    public init(
        item: LaunchItem,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onRefresh: @escaping () -> Void = { Task { await LaunchManager.shared.refreshAll() } },
        onReload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onToggle = onToggle
        self.onRefresh = onRefresh
        self.onReload = onReload
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 10) {
            // 1. App 图标 (固定 32x32)
            itemIconView
                .frame(width: 32, height: 32)
                .layoutPriority(1)

            // 2. 中间主要信息区 (自动撑满剩余全部可用宽度)
            VStack(alignment: .leading, spacing: 3) {
                // 首行：应用名 + 状态徽标 (紧贴标题)
                HStack(spacing: 6) {
                    Text(item.appName ?? item.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    statusBadgeView
                }

                // 次行：作用域 / PID / 守护策略
                HStack(spacing: 6) {
                    Text(item.scope.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let pid = item.pid {
                        Text("PID: \(pid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let code = item.lastExitCode, code != 0 {
                        Text("退出码: \(code)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }

                    Text(item.keepAlive.displayDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            // 3. 右侧操作按钮群 (紧凑排列，始终靠右，不抢占左侧空间)
            HStack(spacing: 8) {
                if !item.scope.isReadOnly {
                    // 刷新状态 (无特权只读刷新，不弹密码框)
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("刷新状态")

                    Toggle("状态", isOn: Binding(
                        get: { item.isLoaded },
                        set: { _ in onToggle() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(item.isMutating)
                    .help(item.isLoaded ? "点击关闭自启" : "点击开启自启")

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("删除自启项并移入备份快照")
                } else {
                    Text("系统只读")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .fixedSize()
        }
        .frame(height: 48)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contextMenu {
            Button {
                onRefresh()
            } label: {
                Label("刷新状态", systemImage: "arrow.clockwise")
            }

            if !item.scope.isReadOnly {
                Button {
                    onReload()
                } label: {
                    Label(
                        item.scope.requiresPrivilegeForService ? "重启服务 (需管理员权限)" : "重启服务 (Kickstart)",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除并备份...", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "确认删除该自启项？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认删除并备份", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(item.appName ?? item.label)」吗？\n\n系统会在删除前自动在本地创建备份快照，你可以随时在「快照恢复中心」中一键无损还原。")
        }
    }

    @ViewBuilder
    private var itemIconView: some View {
        if let iconURL = item.appIconURL {
            let iconImage = NSWorkspace.shared.icon(forFile: iconURL.path)
            Image(nsImage: iconImage)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                    )

                Image(systemName: fallbackIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(fallbackIconColor)
            }
        }
    }

    private var fallbackIconName: String {
        switch item.scope {
        case .systemDaemon:
            return "gearshape.2.fill"
        case .systemAgent:
            return "cpu.fill"
        case .userAgent:
            return "terminal.fill"
        case .appleSystem:
            return "apple.logo"
        }
    }

    private var fallbackIconColor: Color {
        switch item.scope {
        case .systemDaemon:
            return .purple
        case .systemAgent:
            return .indigo
        case .userAgent:
            return .blue
        case .appleSystem:
            return .secondary
        }
    }

    @ViewBuilder
    private var statusBadgeView: some View {
        Group {
            if item.isCrashLooping() {
                badgePill(color: .red, text: "反复崩溃")
            } else if item.isRunning {
                badgePill(color: .green, text: "运行中")
            } else if let code = item.lastExitCode, code > 0 {
                badgePill(color: .yellow, text: "异常退出 (\(code))")
            } else if item.lastExitCode == 0 && item.pid == nil {
                badgePill(color: .blue, text: "就绪待命 (退出码0)")
            } else if item.isDisabledByOverride {
                badgePill(color: .orange, text: "系统已禁用")
            } else if item.isLoaded {
                badgePill(color: .orange, text: "已装载·待触发")
            } else {
                badgePill(color: .secondary, text: "已停用")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func badgePill(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color == .secondary ? .secondary : color)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .cornerRadius(4)
    }
}
