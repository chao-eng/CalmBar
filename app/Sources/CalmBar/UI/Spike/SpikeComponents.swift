import SwiftUI

// MARK: - PRD 常量（§5.1 / §5.6 / §5.8）

enum SpikeMetrics {
    static let panelWidth: CGFloat = 320
    static let panelPadding: CGFloat = 14
    static let contentWidth: CGFloat = panelWidth - panelPadding * 2        // 292
    static let tabBarHeight: CGFloat = 30
    static let tabBarPadding: CGFloat = 3
    static let tabBarInnerWidth: CGFloat = contentWidth - tabBarPadding * 2 // 286
    static let pillHeight: CGFloat = 24
    static let pillSelectedWidth: CGFloat = 84
    static let pillIdleWidth: CGFloat = 40
    static let pillSpacing: CGFloat = 6
    static let pillGroupWidth: CGFloat = pillIdleWidth * 4 + pillSelectedWidth + pillSpacing * 4 // 268
    static let tabBarAnimation: Double = 0.12
}

// MARK: - 分区数据（§5.1）

struct SpikeTab: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: String

    static let all: [SpikeTab] = [
        SpikeTab(id: "thermal", title: "温控", icon: "thermometer.medium"),
        SpikeTab(id: "guardian", title: "守护", icon: "shield.lefthalf.filled"),
        SpikeTab(id: "tools", title: "工具", icon: "square.grid.2x2"),
        SpikeTab(id: "monitor", title: "监控", icon: "waveform.path.ecg"),
        SpikeTab(id: "audio", title: "声音", icon: "speaker.wave.2.fill")
    ]

    static let phaseOne: [SpikeTab] = Array(all.prefix(3))
}

enum SpikeEntryMode: String, CaseIterable, Identifiable {
    case five
    case three

    var id: String { rawValue }
    var tabs: [SpikeTab] { self == .five ? SpikeTab.all : SpikeTab.phaseOne }
    var label: String { self == .five ? "最终 5 入口" : "当前 3 入口" }
}

// MARK: - 面板外壳（复刻现有材质与圆角）

struct SpikePanelShell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: SpikeMetrics.panelWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SpikeMockHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wind")
                .font(.system(size: 15))
            Text("CalmBar")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            Text("● 温度监控中")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(height: 24)
    }
}

// MARK: - 分区栏容器（§5.6：292 宽、3pt 内边距、整组居中）

struct SpikeTabBarContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, SpikeMetrics.tabBarPadding)
            .frame(width: SpikeMetrics.contentWidth, height: SpikeMetrics.tabBarHeight)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
    }
}

// MARK: - 自绘胶囊分区栏（Spike 1 采纳候选）

struct SpikeCustomTabBar: View {
    @Binding var selection: String
    let tabs: [SpikeTab]
    var animationDuration: Double = SpikeMetrics.tabBarAnimation

    var body: some View {
        SpikeTabBarContainer {
            HStack(spacing: SpikeMetrics.pillSpacing) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let isSelected = selection == tab.id
                    Button {
                        withAnimation(animationDuration > 0 ? .easeOut(duration: animationDuration) : nil) {
                            selection = tab.id
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            if isSelected {
                                Text(tab.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .transition(.opacity)
                            }
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(
                            width: isSelected ? SpikeMetrics.pillSelectedWidth : SpikeMetrics.pillIdleWidth,
                            height: SpikeMetrics.pillHeight
                        )
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                        // 命中区向四周扩到 44×30，不改变视觉与布局宽度
                        .background {
                            Color.clear
                                .frame(width: 44, height: 30)
                                .contentShape(Rectangle())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityLabel("\(tab.title)，\(tabs.count) 个分区中第 \(index + 1) 个")
                    .accessibilityValue(isSelected ? "已选中" : "未选中")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}
