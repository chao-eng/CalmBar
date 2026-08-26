import SwiftUI
import CalmBarKit

public struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 统一置顶启动主开关
                FeatureMasterToggleCard(
                    icon: "power",
                    iconColors: [Color.blue, Color.cyan],
                    title: "登录时自动启动 CalmBar",
                    activeSubtitle: "已激活 · 开机登录系统后自动在后台常驻启动",
                    inactiveSubtitle: "已停用 · 开机不自启，需要时请手动打开 CalmBar",
                    isEnabled: $settings.launchAtLogin
                )

                GroupBox(label: Label("外观与菜单栏指示", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("在菜单栏图标旁实时显示 SoC 温度", isOn: $settings.showTempInMenuBar)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("任务栏左键面板显示项目", systemImage: "list.bullet.rectangle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自定义左键点击菜单栏图标时在面板中展示的功能模块：")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            Toggle(isOn: $settings.popoverShowGauges) {
                                Label("硬件温度与风扇调控", systemImage: "gauge.with.needle")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowMenuBar) {
                                Label("菜单栏图标收纳", systemImage: "menubar.rectangle")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowScrollReverser) {
                                Label("鼠标自然滚动解耦", systemImage: "computermouse.fill")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowNoTunes) {
                                Label("Apple Music 启动拦截", systemImage: "music.note")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowCaffeine) {
                                Label("系统防休眠 (保持清醒)", systemImage: "cup.and.saucer.fill")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowBattery) {
                                Label("电池充电上限控制", systemImage: "battery.100.bolt")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowGatekeeper) {
                                Label("软件去隔离与签名授权", systemImage: "lock.shield.fill")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowOCR) {
                                Label("屏幕文字与二维码识别", systemImage: "text.viewfinder")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowClipboard) {
                                Label("剪贴板历史快捷入口", systemImage: "doc.on.clipboard")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowCleaner) {
                                Label("卸载与清理快捷入口", systemImage: "trash")
                            }
                            .font(.system(size: 12.5, weight: .medium))

                            Toggle(isOn: $settings.popoverShowTranslation) {
                                Label("AI 划词翻译快捷入口", systemImage: "character.bubble.fill")
                            }
                            .font(.system(size: 12.5, weight: .medium))
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 全局快捷键按键展示
                GroupBox(label: Label("全局快捷键速查", systemImage: "keyboard")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CalmBar 支持通过以下全局快捷键在任意 App 中即时呼出功能：")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            shortcutRow(title: "呼出命令面板 / 启动器", keys: ["⌥", "⌘", "K"])
                            shortcutRow(title: "AI 快速翻译剪贴板", keys: ["⌥", "⌘", "T"])
                            shortcutRow(title: "屏幕选区识字与扫码 (OCR)", keys: ["⌥", "⌘", "O"])
                            shortcutRow(title: "剪贴板历史记录面板", keys: ["⌥", "⌘", "V"])
                            shortcutRow(title: "展开 / 折叠菜单栏图标", keys: ["⌥", "⌘", "H"])
                            shortcutRow(title: "双击划词就地翻译 (连按)", keys: ["⌘", "C", "×2"])
                        }
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
                                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.3.0"
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
