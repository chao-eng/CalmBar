import SwiftUI
import AppKit

public struct AssociatedFileRowView: View {
    @Binding public var item: AssociatedFileItem

    public var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Image(systemName: item.category.iconName)
                .font(.system(size: 13))
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text(item.category.titleZH)
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())

                    if item.isPrivileged {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .help("该路径需要管理员权限才能清理")
                    }
                }

                Text(item.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isSelected ? Color.blue.opacity(0.04) : Color.clear)
        )
    }
}
