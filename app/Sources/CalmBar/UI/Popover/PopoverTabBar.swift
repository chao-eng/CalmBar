import SwiftUI

// MARK: - 生产版分区栏（Spike 1 采纳的自绘胶囊）

struct PopoverTabBar: View {
    @Binding var selection: PopoverTab
    var tabs: [PopoverTab] = PopoverTab.phaseOne
    var animationDuration: Double = PopoverLayout.tabBarAnimation
    var onMeasure: ((CGFloat) -> Void)?

    var body: some View {
        HStack(spacing: PopoverLayout.pillSpacing) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(animationDuration > 0 ? .easeOut(duration: animationDuration) : nil) {
                        selection = tab
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
                        width: isSelected ? PopoverLayout.pillSelectedWidth : PopoverLayout.pillIdleWidth,
                        height: PopoverLayout.pillHeight
                    )
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                    // 命中区扩到 44×30，不参与布局
                    .background {
                        Color.clear
                            .frame(width: 44, height: 30)
                            .contentShape(Rectangle())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 分区快捷键由窗口层统一处理，胶囊不参与系统焦点环，避免选中态出现蓝色方框
                .focusable(false)
                .focusEffectDisabled()
                .help(tab.title)
                .accessibilityLabel("\(tab.title)，\(tabs.count) 个分区中第 \(index + 1) 个")
                .accessibilityValue(isSelected ? "已选中" : "未选中")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { onMeasure?(proxy.size.width) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, PopoverLayout.tabBarPadding)
        .frame(width: PopoverLayout.contentWidth, height: PopoverLayout.tabBarHeight)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }
}
