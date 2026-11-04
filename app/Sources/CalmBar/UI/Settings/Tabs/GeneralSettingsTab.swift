import AppKit
import SwiftUI
import CalmBarKit

public struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var deepLink = PopoverSettingsDeepLink.shared

    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 统一置顶启动主开关
                    FeatureMasterToggleCard(
                        icon: "power",
                        iconColors: SettingsTab.general.gradientColors,
                        title: "登录时自动启动 CalmBar",
                        activeSubtitle: "已激活 · 开机登录系统后自动在后台常驻启动",
                        inactiveSubtitle: "已停用 · 开机不自启，需要时请手动打开 CalmBar",
                        isEnabled: $settings.launchAtLogin
                    )

                    GroupBox(label: Label("外观与菜单栏指示", systemImage: "gearshape")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("界面外观")
                                    .font(.system(size: 12.5, weight: .medium))
                                Spacer()
                                Picker("界面外观", selection: $settings.appAppearance) {
                                    ForEach(AppAppearance.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                                .focusable(false)
                                .focusEffectDisabled()
                            }
                            Text("选择浅色或深色可让面板与设置窗口脱离系统外观独立显示。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)

                            Divider()

                            Toggle("在菜单栏图标旁实时显示 SoC 温度", isOn: Binding(
                                get: { settings.menuBarReadoutItems.contains("temperature") },
                                set: { settings.setMenuBarReadoutItem("temperature", enabled: $0) }
                            ))
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 面板可见项三分组（PRD §7.2）
                    ForEach(PopoverVisibilityGroup.allCases) { group in
                        GroupBox(label: Label(group.settingsTitle, systemImage: group.icon)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.settingsHint)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                    ForEach(group.items) { item in
                                        Toggle(isOn: binding(for: item)) {
                                            Label(item.settingsTitle, systemImage: item.icon)
                                        }
                                        .font(.system(size: 12.5, weight: .medium))
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(group)
                    }

                    // 全局快捷键按键展示
                    GroupBox(label:
                        HStack {
                            Label("全局快捷键速查", systemImage: "keyboard")
                            Spacer()
                            HStack(spacing: 8) {
                                Text(settings.globalHotKeysEnabled ? "已启用全局快捷键" : "已禁用全局快捷键")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(settings.globalHotKeysEnabled ? .secondary : .orange)
                                Toggle("", isOn: $settings.globalHotKeysEnabled)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .labelsHidden()
                                    .focusable(false)
                                    .focusEffectDisabled()
                                    .help(settings.globalHotKeysEnabled ? "点击禁用全局快捷键" : "点击启用全局快捷键")
                            }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            if !settings.globalHotKeysEnabled {
                                HStack(spacing: 6) {
                                    Image(systemName: "slash.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Text("当前已禁用全局快捷键，所有系统热键均已注销释放，不会拦截系统按键。")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.orange)
                                }
                                .padding(.vertical, 2)
                            } else {
                                Text("CalmBar 支持通过以下全局快捷键在任意 App 中即时呼出功能：")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                shortcutRow(title: "呼出命令面板 / 启动器", keys: ["⌥", "⌘", "K"])
                                shortcutRow(title: "AI 快速翻译剪贴板", keys: ["⌥", "⌘", "T"])
                                shortcutRow(title: "屏幕选区识字与扫码 (OCR)", keys: ["⌥", "⌘", "O"])
                                shortcutRow(title: "剪贴板历史记录面板", keys: ["⌥", "⌘", "V"])
                                shortcutRow(title: "展开 / 折叠菜单栏图标", keys: ["⌥", "⌘", "H"])
                                shortcutRow(title: "双击划词就地翻译 (连按)", keys: ["⌘", "C", "×2"])
                            }
                            .opacity(settings.globalHotKeysEnabled ? 1.0 : 0.45)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox(label: Label("关于 CalmBar", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "wind")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CalmBar")
                                        .font(.system(size: 13.5, weight: .bold))
                                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.4.0"
                                    Text("Version \(version) (Native Swift 6 & SwiftUI)")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Divider()
                            Text("整合硬件温控、菜单栏收纳、滚动手势解耦、媒体启动拦截、防休眠与防离开、电池充电上限保护、应用去隔离授权、屏幕文字与二维码识别 (Vision OCR)、AI 划词翻译 (HTTP OpenAI & HY-MT2)、剪贴板历史记录 (Clipboard History) 及应用与开发者环境深度清理 (Developer Cleaner) 的全能 macOS 菜单栏综合增强套件。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)

                            Divider()
                            HStack(spacing: 6) {
                                Text("开源项目与源码：")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)

                                if let url = URL(string: "https://github.com/chao-eng/CalmBar") {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Text("https://github.com/chao-eng/CalmBar")
                                                .font(.system(size: 11.5))
                                            Image(systemName: "arrow.up.forward.square")
                                                .font(.system(size: 10.5))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .onAppear { scrollToPendingGroup(with: proxy) }
            .onChange(of: deepLink.pendingGroup) { _, _ in
                scrollToPendingGroup(with: proxy)
            }
        }
    }

    private func binding(for item: PopoverVisibilityItem) -> Binding<Bool> {
        Binding(
            get: { item.isEnabled(settings) },
            set: { item.setEnabled(settings, $0) }
        )
    }

    /// 深链：滚动到目标分组锚点后清零待处理标记
    private func scrollToPendingGroup(with proxy: ScrollViewProxy) {
        guard let group = deepLink.pendingGroup else { return }
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(group, anchor: .top)
                }
            } else {
                proxy.scrollTo(group, anchor: .top)
            }
            _ = deepLink.consume()
        }
    }

    private func shortcutRow(title: String, keys: [String]) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
}
