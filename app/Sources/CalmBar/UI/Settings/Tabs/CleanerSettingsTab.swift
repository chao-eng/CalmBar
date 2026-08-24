import SwiftUI
import CalmBarKit

public struct CleanerSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .cleaner)

                GroupBox(label: Label("软件卸载与清理中心", systemImage: "trash.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("一键分析已安装软件及其散落在系统与用户 Library 中的深层缓存、偏好与残留文件，安全移入废纸篓。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack {
                            Button(action: {
                                CleanerWindowController.shared.show()
                            }) {
                                Label("打开清理中心主窗口", systemImage: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }

                        Divider()

                        HStack {
                            Text("残留探测灵敏度：")
                                .font(.system(size: 12))
                            Picker("", selection: $settings.cleanerSensitivity) {
                                ForEach(SearchSensitivityLevel.allCases) { level in
                                    Text(level.titleZH).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 320)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("完全磁盘访问权限 (Full Disk Access)", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("为完整扫描 ~/Library/Containers、Group Containers 及保护目录下的应用残留，建议为 CalmBar 开启完全磁盘访问权限。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("打开系统「完全磁盘访问权限」设置", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)
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
