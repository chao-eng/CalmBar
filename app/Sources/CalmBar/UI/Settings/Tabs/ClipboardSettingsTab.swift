import SwiftUI
import CalmBarKit

public struct ClipboardSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryManager.shared
    @ObservedObject private var clipboardMonitor = ClipboardMonitor.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .clipboard)

                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.clipboard.icon,
                    iconColors: SettingsTab.clipboard.gradientColors,
                    title: "剪贴板历史记录服务",
                    activeSubtitle: "已激活 · 实时在后台记录复制内容 (已安全归档 \(clipboardHistory.items.count) 条记录)",
                    inactiveSubtitle: "已停用 · 暂停系统剪贴板监听，不保存新的复制记录",
                    isEnabled: Binding(
                        get: { settings.clipboardHistoryEnabled },
                        set: { enabled in
                            settings.clipboardHistoryEnabled = enabled
                            if enabled {
                                clipboardMonitor.startMonitoring()
                            } else {
                                clipboardMonitor.stopMonitoring()
                            }
                        }
                    )
                )

                // 1. 隐私与图片过滤
                GroupBox(label: Label("隐私保护与内容过滤", systemImage: "shield.lefthalf.filled")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("保存复制的图片与截图", isOn: $settings.clipboardSaveImages)
                        Toggle("自动过滤密码管理器与敏感标记 (1Password / Bitwarden / 瞬态剪贴板)", isOn: $settings.clipboardFilterSensitive)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!settings.clipboardHistoryEnabled)
                .opacity(settings.clipboardHistoryEnabled ? 1.0 : 0.6)

                // 2. 容量上限与归档设置
                GroupBox(label: Label("存储容量与上限", systemImage: "internaldrive")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("历史记录最大保留条数")
                                    .font(.system(size: 12, weight: .medium))
                                Text("当前已存储 \(clipboardHistory.items.count) 条记录（固定项永不自动清除）。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.clipboardMaxCount) {
                                Text("50 条").tag(50)
                                Text("100 条").tag(100)
                                Text("200 条").tag(200)
                                Text("500 条").tag(500)
                                Text("1000 条").tag(1000)
                            }
                            .frame(width: 110)
                        }

                        Divider()

                        HStack {
                            Text("本地存储占用：")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(clipboardHistory.storageSizeFormatted)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Spacer()
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!settings.clipboardHistoryEnabled)
                .opacity(settings.clipboardHistoryEnabled ? 1.0 : 0.6)

                // 3. 独立管理窗口与数据清理
                GroupBox(label: Label("历史管理与快捷操作", systemImage: "clock.arrow.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: {
                                ClipboardHistoryWindowController.shared.show()
                            }) {
                                Label("打开剪贴板历史独立窗口", systemImage: "macwindow.on.rectangle")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Spacer()

                            if !clipboardHistory.items.isEmpty {
                                Button(role: .destructive, action: {
                                    clipboardHistory.clearAll(keepPinned: true)
                                }) {
                                    Label("清空未固定记录", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .controlSize(.small)

                                Button(role: .destructive, action: {
                                    clipboardHistory.clearAll(keepPinned: false)
                                }) {
                                    Label("清空全部", systemImage: "trash.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}
