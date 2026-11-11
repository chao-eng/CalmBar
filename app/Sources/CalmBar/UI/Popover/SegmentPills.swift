import SwiftUI

// MARK: - 面板内自绘分段控件
//
// 系统 Picker(.segmented) 在 controlSize(.mini) 下沿用系统小字号，面板里会发虚。
// 这里改为自绘：选中胶囊按等分宽度绘制，字号与字重完全可控。

struct SegmentedPillBar: View {
    /// (标识, 文案)
    let items: [(id: String, title: String)]
    let selection: String
    /// 紧凑模式用于图表卡头部的时间粒度
    var compact: Bool = false
    var onSelect: (String) -> Void

    private var barHeight: CGFloat { compact ? 18 : 20 }
    private var inset: CGFloat { 2 }
    private var pillHeight: CGFloat { barHeight - inset * 2 }
    private var fontSize: CGFloat { compact ? 9 : 10 }

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, items.count)
            let pillWidth = (proxy.size.width - inset * 2) / CGFloat(count)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PopoverPalette.surfaceBarTrack)

                if let index = items.firstIndex(where: { $0.id == selection }) {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(PopoverPalette.surfaceSelected)
                        .frame(width: pillWidth, height: pillHeight)
                        .offset(x: inset + CGFloat(index) * pillWidth, y: inset)
                }

                HStack(spacing: 0) {
                    ForEach(items, id: \.id) { item in
                        let isSelected = item.id == selection
                        Button {
                            guard !isSelected else { return }
                            onSelect(item.id)
                        } label: {
                            Text(item.title)
                                .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                                .frame(height: pillHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                        .accessibilityLabel(item.title)
                        .accessibilityValue(isSelected ? "已选中" : "未选中")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, inset)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(PopoverPalette.separatorHairline, lineWidth: 0.5)
            }
        }
        .frame(height: barHeight)
    }
}
