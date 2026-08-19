import SwiftUI
import Combine

extension Notification.Name {
    static let commandPaletteNext = Notification.Name("CalmBar.CommandPalette.Next")
    static let commandPalettePrevious = Notification.Name("CalmBar.CommandPalette.Previous")
    static let commandPaletteExecute = Notification.Name("CalmBar.CommandPalette.Execute")
}

public struct CommandPaletteView: View {
    @ObservedObject private var center = CommandCenter.shared
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var feedbackMessage: String?
    @State private var isExecuting: Bool = false

    public var onDismiss: () -> Void = {}

    private var filteredCommands: [CommandDescriptor] {
        center.search(query: query)
    }

    public init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search Input Row
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("搜索命令、功能或快捷操作...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onChange(of: query) { _, _ in
                        selectedIndex = 0
                    }
                    .onSubmit {
                        executeCurrentSelection()
                    }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDismiss) {
                    Text("ESC 退出")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Feedback Banner
            if let feedbackMessage {
                HStack {
                    Image(systemName: "info.circle")
                    Text(feedbackMessage)
                    Spacer()
                }
                .font(.system(size: 11))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
            }

            // Results List
            let commands = filteredCommands
            if commands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("未找到相关命令")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(commands.enumerated()), id: \.element.id) { idx, cmd in
                                commandRow(cmd: cmd, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture {
                                        selectedIndex = idx
                                        executeCommand(cmd)
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer hints
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("↑↓")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                    Text("选择")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text("↵")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                    Text("执行")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(commands.count) 个可用命令")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 560, height: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onExitCommand {
            onDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteNext)) { _ in
            let count = filteredCommands.count
            if count > 0 {
                selectedIndex = (selectedIndex + 1) % count
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPalettePrevious)) { _ in
            let count = filteredCommands.count
            if count > 0 {
                selectedIndex = (selectedIndex - 1 + count) % count
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteExecute)) { _ in
            executeCurrentSelection()
        }
    }

    @ViewBuilder
    private func commandRow(cmd: CommandDescriptor, isSelected: Bool) -> some View {
        let hasPermission = cmd.requiredPermissions.allSatisfy { PermissionManager.shared.isGranted($0) }

        HStack(spacing: 12) {
            Image(systemName: cmd.iconName)
                .font(.system(size: 15))
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(cmd.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)

                    if !hasPermission {
                        Text("需授权")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }

                    Spacer()

                    Text(cmd.category.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }

                if let subtitle = cmd.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func executeCurrentSelection() {
        let commands = filteredCommands
        guard selectedIndex >= 0 && selectedIndex < commands.count else { return }
        executeCommand(commands[selectedIndex])
    }

    private func executeCommand(_ cmd: CommandDescriptor) {
        guard !isExecuting else { return }
        isExecuting = true
        Task {
            let result = await center.execute(command: cmd)
            isExecuting = false
            switch result {
            case .success(let msg):
                feedbackMessage = msg ?? "执行完成"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            case .permissionDenied(let perm):
                feedbackMessage = "缺少权限: \(perm.title)，请先前往权限安全中心授权"
            case .failure(let err):
                feedbackMessage = "执行失败: \(err)"
            case .cancelled:
                feedbackMessage = "已取消"
            }
        }
    }
}
