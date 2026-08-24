import SwiftUI
import CalmBarKit

public struct CleanerSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.cleaner.icon,
                    iconColors: SettingsTab.cleaner.gradientColors,
                    title: "应用卸载与垃圾清理引擎",
                    activeSubtitle: "已激活 · 深度扫描已安装软件残留、构建缓存与孤立工作区",
                    inactiveSubtitle: "已停用 · 暂停清理模块与残留感知",
                    isEnabled: $settings.cleanerEnabled
                )

                GroupBox(label: Label("软件卸载与清理中心", systemImage: "trash.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("一键分析已安装软件及其散落在系统与用户 Library 中的深层缓存、偏好与残留文件，安全移入废纸篓。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        HStack {
                            Button(action: {
                                CleanerWindowController.shared.show()
                            }) {
                                Label("打开清理中心主窗口", systemImage: "sparkles")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }

                        Divider()

                        HStack {
                            Text("残留探测灵敏度：")
                                .font(.system(size: 12.5, weight: .medium))
                            Picker("", selection: $settings.cleanerSensitivity) {
                                ForEach(SearchSensitivityLevel.allCases) { level in
                                    Text(level.titleZH).tag(level)
                                }
                            }
                            .font(.system(size: 12))
                            .pickerStyle(.segmented)
                            .frame(width: 320)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!settings.cleanerEnabled)
                .opacity(settings.cleanerEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("完全磁盘访问权限 (Full Disk Access)", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("为完整扫描 ~/Library/Containers、Group Containers 及保护目录下的应用残留，建议为 CalmBar 开启完全磁盘访问权限。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("打开系统「完全磁盘访问权限」设置", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12, weight: .medium))
                        .controlSize(.small)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}
