import SwiftUI
import CalmBarKit

public struct ScrollSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scroll = ScrollReverserManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.scroll.icon,
                    iconColors: SettingsTab.scroll.gradientColors,
                    title: "滚动手势解耦引擎",
                    activeSubtitle: "已激活 · 独立反转鼠标/触控板滚轮方向，恢复自然交互体验",
                    inactiveSubtitle: "已停用 · macOS 原生滚动方向，手势解耦引擎未运行",
                    isEnabled: $settings.scrollReverserEnabled
                )

                GroupBox(label: Label("系统权限状态", systemImage: "lock.shield")) {
                    HStack {
                        Image(systemName: scroll.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(scroll.hasAccessibilityPermission ? .green : .orange)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scroll.hasAccessibilityPermission ? "辅助功能权限已就绪" : "需要授予辅助功能权限")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("滚动手势解耦需要通过辅助功能权限拦截并翻转鼠标滚轮事件。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }

                        Spacer()

                        if !scroll.hasAccessibilityPermission {
                            Button("去授权...") {
                                AccessibilityHelper.requestAccessibilityPermission()
                                AccessibilityHelper.openSystemSettingsAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(8)
                }

                GroupBox(label: Label("设备独立滚动方向配置", systemImage: "slider.horizontal.2")) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("传统外接鼠标 (Mouse)")
                                .font(.system(size: 12.5, weight: .semibold))

                            Toggle("反转垂直滚轮 (恢复 Windows/经典滚轮方向)", isOn: $settings.reverseMouseVertical)
                                .font(.system(size: 12.5, weight: .medium))
                            Toggle("反转水平滚轮 (X 轴)", isOn: $settings.reverseMouseHorizontal)
                                .font(.system(size: 12.5, weight: .medium))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("内建触控板 (Trackpad)")
                                .font(.system(size: 12.5, weight: .semibold))

                            Toggle("反转触控板双指垂直滑动", isOn: $settings.reverseTrackpadVertical)
                                .font(.system(size: 12.5, weight: .medium))
                            Toggle("反转触控板双指水平滑动", isOn: $settings.reverseTrackpadHorizontal)
                                .font(.system(size: 12.5, weight: .medium))
                        }
                    }
                    .padding(8)
                }
                .disabled(!settings.scrollReverserEnabled)
                .opacity(settings.scrollReverserEnabled ? 1.0 : 0.6)
            }
            .padding(16)
        }
    }
}
