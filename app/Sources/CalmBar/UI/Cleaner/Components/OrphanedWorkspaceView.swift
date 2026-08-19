import SwiftUI
import AppKit

public struct OrphanedWorkspaceView: View {
    public let item: OrphanedWorkspaceItem
    public let onDelete: () -> Void

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.projectFolderName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(item.ideName)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Text("原路径已失效: \(item.projectOriginalFolderPath)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Button("清理") {
                onDelete()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
