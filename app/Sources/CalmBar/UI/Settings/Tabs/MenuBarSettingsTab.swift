import SwiftUI
import CalmBarKit

public struct MenuBarSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .menuBar)

                GroupBox(label: Label("自动化与交互", systemImage: "sparkles")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("展开后无操作自动折叠收纳", isOn: $settings.autoCollapseEnabled)

                        if settings.autoCollapseEnabled {
                            HStack {
                                Text("折叠延迟:")
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $settings.autoCollapseDelay, in: 2...20, step: 1)
                                Text("\(Int(settings.autoCollapseDelay)) 秒")
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }

                        Toggle("鼠标指针悬停自动展开", isOn: $settings.hoverToExpand)
                    }
                    .padding(8)
                }

                GroupBox(label: Label("使用指南与快捷键", systemImage: "questionmark.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .font(.system(size: 12, weight: .bold))
                            Text("按住键盘 **Command (⌘)** 键，用鼠标将不常用的菜单栏图标拖动到 **`<` 折叠图标的左侧**。")
                                .font(.system(size: 12))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .font(.system(size: 12, weight: .bold))
                            Text("点击菜单栏的箭头 **`<`** 图标，或按下全局热键 **⌥ + ⌘ + H** 即可一键展开/收起。")
                                .font(.system(size: 12))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .font(.system(size: 12, weight: .bold))
                            Text("软件退出或重启时，所有图标将自动恢复系统原生排列。")
                                .font(.system(size: 12))
                        }
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }
}
