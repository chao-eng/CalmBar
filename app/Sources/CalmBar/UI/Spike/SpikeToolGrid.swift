import AppKit
import SwiftUI

// MARK: - 常量（§5.6 工具网格）

enum SpikeContentMetrics {
    static let width: CGFloat = 320
    static let verticalPadding: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let headerHeight: CGFloat = 24
    static let sectionGap: CGFloat = 8
    static let tabBarHeight: CGFloat = 30
    static let footerHeight: CGFloat = 18
    static let viewportHeight: CGFloat = 300
    static let totalHeight: CGFloat = 420   // 120 chrome + 300 视口

    static let tileWidth: CGFloat = 67
    static let tileHeight: CGFloat = 84
    static let tileSpacing: CGFloat = 8
    static let columns = 4
    static let gridWidth: CGFloat = tileWidth * 4 + tileSpacing * 3   // 292
    static let labelAvailableWidth: CGFloat = tileWidth - 4            // 63（左右各留 2pt）
}

// MARK: - 工具磁贴数据

struct SpikeToolTile: Identifiable, Hashable {
    let id: String
    let titleZH: String
    let titleEN: String
    let icon: String

    static let all: [SpikeToolTile] = [
        SpikeToolTile(id: "quarantine", titleZH: "应用去隔离", titleEN: "Quarantine", icon: "shield.slash"),
        SpikeToolTile(id: "snap", titleZH: "窗口贴边", titleEN: "Snap Window", icon: "rectangle.split.2x1"),
        SpikeToolTile(id: "picker", titleZH: "屏幕取色", titleEN: "Color Picker", icon: "eyedropper"),
        SpikeToolTile(id: "clipboard", titleZH: "剪贴板历史", titleEN: "Clipboard", icon: "doc.on.clipboard"),
        SpikeToolTile(id: "shortcut", titleZH: "快捷指令", titleEN: "Shortcuts", icon: "command"),
        SpikeToolTile(id: "audio", titleZH: "音频路由", titleEN: "Audio Route", icon: "speaker.wave.2"),
        SpikeToolTile(id: "awake", titleZH: "保持唤醒", titleEN: "Keep Awake", icon: "sun.max"),
        SpikeToolTile(id: "desktop", titleZH: "隐藏桌面", titleEN: "Hide Desktop", icon: "rectangle.dashed"),
        SpikeToolTile(id: "shot", titleZH: "截图", titleEN: "Screenshot", icon: "camera"),
        SpikeToolTile(id: "record", titleZH: "录屏", titleEN: "Record", icon: "record.circle"),
        SpikeToolTile(id: "memory", titleZH: "清理内存", titleEN: "Free Memory", icon: "memorychip"),
        SpikeToolTile(id: "more", titleZH: "更多", titleEN: "More", icon: "ellipsis")
    ]
}

// MARK: - 网格宽度回传

struct SpikeGridWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - 4 列工具网格（67×84、间距 8、总宽 292 零余量）

struct SpikeToolGrid: View {
    let english: Bool
    let fontScale: CGFloat
    let increaseContrast: Bool

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(SpikeContentMetrics.tileWidth), spacing: SpikeContentMetrics.tileSpacing),
                count: SpikeContentMetrics.columns
            ),
            spacing: SpikeContentMetrics.tileSpacing
        ) {
            ForEach(SpikeToolTile.all) { tile in
                tileView(tile)
            }
        }
        .frame(width: SpikeContentMetrics.gridWidth)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SpikeGridWidthKey.self, value: proxy.size.width)
            }
        }
    }

    private func tileView(_ tile: SpikeToolTile) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tile.icon)
                .font(.system(size: 12))
                .foregroundStyle(.tint)
                .frame(height: 14)
            Text(english ? tile.titleEN : tile.titleZH)
                .font(.system(size: 10 * fontScale, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
                .foregroundStyle(.primary)
        }
        .frame(width: SpikeContentMetrics.tileWidth, height: SpikeContentMetrics.tileHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(increaseContrast ? 0.28 : 0.08),
                    lineWidth: increaseContrast ? 1.0 : 0.5
                )
        }
        .focusable()
        .help(english ? tile.titleEN : tile.titleZH)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(english ? tile.titleEN : tile.titleZH)
        .accessibilityValue("按钮")
        .accessibilityAddTraits(.isButton)
    }
}
