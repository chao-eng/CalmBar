import SwiftUI
import CalmBarKit

public struct ScrollSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .scroll)

                GroupBox(label: Label("系统权限状态", systemImage: "lock.shield")) {
                    HStack {
                        Image(systemName: scroll.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(scroll.hasAccessibilityPermission ? .green : .orange)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scroll.hasAccessibilityPermission ? "辅助功能权限已就绪" : "需要授予辅助功能权限")
                                .font(.system(size: 13, weight: .semibold))
                            Text("滚动手势解耦需要通过辅助功能权限拦截并翻转鼠标滚轮事件。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !scroll.hasAccessibilityPermission {
                            Button("去授权...") {
                                AccessibilityHelper.requestAccessibilityPermission()
                                AccessibilityHelper.openSystemSettingsAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("设备独立滚动方向配置", systemImage: "slider.horizontal.2")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("启用滚动手势反转引擎", isOn: $settings.scrollReverserEnabled)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("传统外接鼠标 (Mouse)")
                                .font(.system(size: 12, weight: .semibold))

                            Toggle("反转垂直滚轮 (恢复 Windows/经典滚轮方向)", isOn: $settings.reverseMouseVertical)
                                .disabled(!settings.scrollReverserEnabled)
                            Toggle("反转水平滚轮 (X 轴)", isOn: $settings.reverseMouseHorizontal)
                                .disabled(!settings.scrollReverserEnabled)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("内建触控板 (Trackpad)")
                                .font(.system(size: 12, weight: .semibold))

                            Toggle("反转触控板双指垂直滑动", isOn: $settings.reverseTrackpadVertical)
                                .disabled(!settings.scrollReverserEnabled)
                            Toggle("反转触控板双指水平滑动", isOn: $settings.reverseTrackpadHorizontal)
                                .disabled(!settings.scrollReverserEnabled)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }
}
