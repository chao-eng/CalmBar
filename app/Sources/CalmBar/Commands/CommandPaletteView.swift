import AppKit
import SwiftUI
import CommandPaletteKit

public struct CalmBarPaletteRow: View {
    public let result: PaletteResult
    public let isSelected: Bool

    @Environment(\.commandPaletteStyle) private var style

    public init(result: PaletteResult, isSelected: Bool) {
        self.result = result
        self.isSelected = isSelected
    }

    private var commandDescriptor: CommandDescriptor? {
        CommandCenter.shared.command(id: result.id)
    }

    public var body: some View {
        let cmd = commandDescriptor
        let needsPermission: Bool = {
            guard let cmd else { return false }
            return !cmd.requiredPermissions.allSatisfy { PermissionManager.shared.isGranted($0) }
        }()

        HStack(spacing: 12) {
            result.icon
                .font(.system(size: 15, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(isSelected ? style.selectedForeground : Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? style.selectedForeground : Color.primary)

                    if needsPermission {
                        Text("需授权")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isSelected ? Color.white.opacity(0.25) : Color.orange.opacity(0.2))
                            .foregroundColor(isSelected ? .white : .orange)
                            .cornerRadius(3)
                    }
                }

                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? style.selectedForeground.opacity(0.8) : Color.secondary)
                }
            }

            Spacer(minLength: 8)

            if let category = result.category, !category.isEmpty {
                Text(category)
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                    .foregroundColor(isSelected ? style.selectedForeground : Color.secondary)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, style.rowHorizontalPadding)
        .padding(.vertical, style.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: style.rowCornerRadius, style: .continuous)
                .fill(isSelected ? style.selectionColor : Color.clear)
        )
    }
}

public struct CommandPaletteView: View {
    public var onDismiss: () -> Void = {}

    public init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        CommandPaletteKit.CommandPaletteView(
            placeholder: "搜索命令、功能或快捷操作...",
            emptyMessage: "输入关键词搜索 CalmBar 功能与快捷操作",
            noMatchesMessage: "未找到相关命令",
            resultLimit: 50,
            width: 580,
            height: 400,
            onActivate: { result in
                onDismiss()
                result.action()
            },
            candidates: {
                CommandCenter.shared.paletteResults()
            },
            row: { result, isSelected in
                CalmBarPaletteRow(result: result, isSelected: isSelected)
            }
        )
        .commandPaletteStyle(
            CommandPaletteStyle(
                selectionColor: .accentColor,
                selectedForeground: .white,
                rowCornerRadius: 7,
                rowHorizontalPadding: 10,
                rowVerticalPadding: 7
            )
        )
        .commandPaletteExtendedKeyboardNavigation(true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
    }
}
