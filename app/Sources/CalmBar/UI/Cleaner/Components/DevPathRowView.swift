import SwiftUI
import AppKit

public struct DevPathRowView: View {
    public let item: DevPathItem
    public let onClearContents: () -> Void
    public let onTrashFolder: () -> Void

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(.purple)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(item.expandedPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)

            // Actions
            HStack(spacing: 6) {
                Button("清空内容") {
                    onClearContents()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(item.isEmpty || item.sizeBytes == 0)

                Button("移入废纸篓") {
                    onTrashFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    NSWorkspace.shared.selectFile(item.expandedPath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("在 Finder 中查看")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
