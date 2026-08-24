import SwiftUI
import CalmBarKit

public struct MenuBarSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 统一总控开关
                FeatureMasterToggleCard(
                    icon: SettingsTab.menuBar.icon,
                    iconColors: SettingsTab.menuBar.gradientColors,
                    title: "菜单栏图标收纳引擎",
                    activeSubtitle: "已激活 · 支持通过按键 ⌥⌘H 或点击 `<` 箭头展开/折叠隐藏图标",
                    inactiveSubtitle: "已停用 · 所有图标恢复 macOS 原生排布，不进行折叠收纳",
                    isEnabled: $settings.menuBarOrganizerEnabled
                )

                GroupBox(label: Label("自动化与交互", systemImage: "sparkles")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("展开后无操作自动折叠收纳", isOn: $settings.autoCollapseEnabled)
                            .font(.system(size: 12.5, weight: .medium))

                        if settings.autoCollapseEnabled {
                            HStack {
                                Text("折叠延迟:")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $settings.autoCollapseDelay, in: 2...20, step: 1)
                                Text("\(Int(settings.autoCollapseDelay)) 秒")
                                    .frame(width: 45, alignment: .trailing)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                        }

                        Toggle("鼠标指针悬停自动展开", isOn: $settings.hoverToExpand)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(8)
                }
                .disabled(!settings.menuBarOrganizerEnabled)
                .opacity(settings.menuBarOrganizerEnabled ? 1.0 : 0.6)

                GroupBox(label: Label("使用指南与快捷键", systemImage: "questionmark.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("按住键盘 **Command (⌘)** 键，用鼠标将不常用的菜单栏图标拖动到 **`<` 折叠图标的左侧**。")
                                .font(.system(size: 11.5))
                                .lineSpacing(2)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("点击菜单栏的箭头 **`<`** 图标，或按下全局热键 **⌥ + ⌘ + H** 即可一键展开/收起。")
                                .font(.system(size: 11.5))
                                .lineSpacing(2)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("软件退出或关闭该功能时，所有图标将自动恢复系统原生排列。")
                                .font(.system(size: 11.5))
                                .lineSpacing(2)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }
}
