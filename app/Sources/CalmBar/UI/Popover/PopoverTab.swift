import SwiftUI

// MARK: - 分区定义（PRD §5.1 / §7.3）

enum PopoverTab: String, CaseIterable, Identifiable, Sendable {
    case thermal
    case guardian
    case tools
    case monitor
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thermal: "温控"
        case .guardian: "守护"
        case .tools: "工具"
        case .monitor: "监控"
        case .audio: "声音"
        }
    }

    var icon: String {
        switch self {
        case .thermal: "thermometer.medium"
        case .guardian: "shield.lefthalf.filled"
        case .tools: "square.grid.2x2"
        case .monitor: "waveform.path.ecg"
        case .audio: "speaker.wave.2.fill"
        }
    }

    /// 阶段一只开放前三个分区
    var isPhaseOne: Bool {
        switch self {
        case .thermal, .guardian, .tools: true
        case .monitor, .audio: false
        }
    }

    /// 分区主题色（Tab 图标与分区内强调色）
    var accent: Color {
        switch self {
        case .thermal: PopoverPalette.thermalAccent
        case .guardian: PopoverPalette.guardianAccent
        case .tools: PopoverPalette.toolsAccent
        case .monitor: PopoverPalette.monitorAccent
        case .audio: PopoverPalette.audioAccent
        }
    }

    static var phaseOne: [PopoverTab] { allCases.filter(\.isPhaseOne) }
}

// MARK: - 路由常量表（PRD §7.3）

enum PopoverContentKind: Sendable {
    case thermalCards
    case guardianCards
    case toolTiles
    case monitorCards
    case audioMixer
}

struct PopoverTabRoute: Identifiable, Sendable {
    let tab: PopoverTab
    let title: String
    let subtitle: String
    let kind: PopoverContentKind
    let viewportHeight: CGFloat

    var id: String { tab.rawValue }
    var totalHeight: CGFloat { PopoverLayout.chromeHeight + viewportHeight }

    static let all: [PopoverTabRoute] = [
        PopoverTabRoute(tab: .thermal, title: "温控", subtitle: "温度与风扇状态", kind: .thermalCards, viewportHeight: 220),
        PopoverTabRoute(tab: .guardian, title: "守护", subtitle: "常驻守护开关", kind: .guardianCards, viewportHeight: 272),
        PopoverTabRoute(tab: .tools, title: "工具", subtitle: "快捷工具入口", kind: .toolTiles, viewportHeight: 200),
        PopoverTabRoute(tab: .monitor, title: "监控", subtitle: "系统负载与告警", kind: .monitorCards, viewportHeight: 326),
        PopoverTabRoute(tab: .audio, title: "声音", subtitle: "按应用调节音量与输出设备", kind: .audioMixer, viewportHeight: 200)
    ]

    static func route(for tab: PopoverTab) -> PopoverTabRoute {
        all.first { $0.tab == tab } ?? all[0]
    }
}

// MARK: - 布局常量（PRD §5.6，M1 统一固定高度）

enum PopoverLayout {
    static let panelWidth: CGFloat = 320
    static let padding: CGFloat = 14
    static let contentWidth: CGFloat = panelWidth - padding * 2            // 292
    static let headerHeight: CGFloat = 24
    static let tabBarHeight: CGFloat = 30
    static let tabBarPadding: CGFloat = 3
    static let tabBarInnerWidth: CGFloat = contentWidth - tabBarPadding * 2 // 286
    static let pillHeight: CGFloat = 24
    static let pillSelectedWidth: CGFloat = 84
    static let pillIdleWidth: CGFloat = 40
    static let pillSpacing: CGFloat = 6
    static let titleHeight: CGFloat = 32
    static let footerHeight: CGFloat = 18
    static let sectionGap: CGFloat = 10
    static let blockGap: CGFloat = 8
    static let toolTileWidth: CGFloat = 67
    static let toolTileHeight: CGFloat = 84
    static let toolGridSpacing: CGFloat = 8
    static let minViewportHeight: CGFloat = 200
    static let maxViewportHeight: CGFloat = 360
    /// 窗口高度恒定值：视口取最大值，Tab 切换只动内部内容高度
    static let maxPanelHeight: CGFloat = chromeHeight + maxViewportHeight
    // BR-03：28 padding + 24 header + 28 gaps + 30 tabbar + 32 title + 18 footer
    static let chromeHeight: CGFloat = padding * 2 + headerHeight + sectionGap * 2 + tabBarHeight + titleHeight + blockGap + footerHeight
    static let tabBarAnimation: Double = 0.12
    static let heightAnimation: Double = 0.16

    static func clampedViewport(_ raw: CGFloat) -> CGFloat {
        min(max(raw, minViewportHeight), maxViewportHeight)
    }
}
