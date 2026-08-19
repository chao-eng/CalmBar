import SwiftUI

/// Permission Center view presenting a transparent, user-friendly security & permissions hub.
public struct PermissionCenterView: View {
    @StateObject private var permissionManager = PermissionManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header Banner
                GroupBox(label: Label("系统权限与安全性说明", systemImage: "shield.lefthalf.filled")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CalmBar 严格遵循 macOS 最小权限原则，所有功能与深度清理均在本地执行，绝不收集或上传任何个人隐私。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Permission Items List
                VStack(spacing: 10) {
                    ForEach(PermissionType.allCases) { type in
                        permissionCard(for: type)
                    }
                }

                Divider()

                // Footer Actions
                HStack {
                    Text("若在系统设置中更改了授权，请点击刷新以读取最新状态。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        permissionManager.refreshAll()
                    } label: {
                        Label("刷新权限状态", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
        }
        .onAppear {
            permissionManager.refreshAll()
        }
    }

    @ViewBuilder
    private func permissionCard(for type: PermissionType) -> some View {
        let isGranted = permissionManager.isGranted(type)

        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isGranted ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)

                    Image(systemName: type.iconName)
                        .font(.system(size: 15))
                        .foregroundColor(isGranted ? .green : .orange)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(type.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        if type.isRequiredForCore {
                            Text("核心能力")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                        }

                        Spacer()

                        // Status Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isGranted ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(isGranted ? "已授权" : "未授权")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(isGranted ? .green : .orange)
                        }
                    }

                    Text(type.purposeDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Affected Features Tags
                    let affected = permissionManager.affectedFeatures(for: type)
                    if !affected.isEmpty {
                        HStack(spacing: 4) {
                            Text("关联功能:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            ForEach(affected) { featId in
                                Text(featId.displayName)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(3)
                            }
                        }
                        .padding(.top, 1)
                    }

                    // Action button if not granted
                    if !isGranted {
                        HStack {
                            Spacer()
                            Button {
                                permissionManager.requestOrOpenSettings(for: type)
                            } label: {
                                Text(type == .privilegedHelper ? "一键激活特权助手" : "前往系统设置授权")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(type == .privilegedHelper ? .blue : .orange)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(6)
        }
    }
}
