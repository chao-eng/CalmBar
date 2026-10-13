import SwiftUI
import AppKit

public struct LaunchBackupCenterView: View {
    @ObservedObject private var manager = LaunchManager.shared
    @State private var selectedBackup: LaunchBackupItem?
    @State private var isRestoring: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Info Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("快照与还原中心")
                        .font(.system(size: 14, weight: .bold))
                    Text("CalmBar 在修改或删除任何自启项前自动创建快照，可随时无损还原，保留 30 天")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    manager.refreshBackups()
                } label: {
                    Label("刷新快照", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let backupDir = LaunchBackupService.shared.backupDirectory
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupDir.path)
                } label: {
                    Label("打开快照文件夹", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .background(.ultraThinMaterial)

            Divider()

            // List of backups
            if manager.backups.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("暂无历史快照记录")
                        .font(.system(size: 14, weight: .medium))
                    Text("进行修改、禁用或删除操作时，系统将自动生成可还原的备份点")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(manager.backups) { backup in
                    backupRow(backup)
                }
                .listStyle(.inset)
            }
        }
    }

    private func backupRow(_ backup: LaunchBackupItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 20))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 3) {
                Text(backup.label)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 10) {
                    Text("创建时间: \(backup.formattedDate)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("大小: \(backup.formattedSize)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([backup.fileURL])
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("在 Finder 中查看备份文件")

                Button {
                    Task {
                        isRestoring = true
                        // 还原到快照记录的原始作用域，避免系统级备份被错误写入用户目录
                        await manager.restoreBackup(backup, targetScope: backup.originalScope ?? .userAgent)
                        manager.refreshBackups()
                        isRestoring = false
                    }
                } label: {
                    Text("一键还原")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRestoring)
                .help(backup.originalScope.map { "还原到 \($0.displayName)" } ?? "还原到用户自启项目录")

                Button(role: .destructive) {
                    try? LaunchBackupService.shared.deleteBackup(backup.fileURL)
                    manager.refreshBackups()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("删除此快照")
            }
        }
        .padding(.vertical, 4)
    }
}
