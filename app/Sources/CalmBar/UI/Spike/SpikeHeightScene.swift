import SwiftUI

struct SpikeHeightScene: View {
    @ObservedObject var driver: SpikeHeightDriver

    private var tabSelection: Binding<String> {
        Binding(
            get: { driver.currentCase.baseTabID },
            set: { driver.selectTab($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SpikeMockHeader()
                .frame(height: SpikePanelMetrics.headerHeight)

            Color.clear.frame(height: SpikePanelMetrics.sectionGap)

            SpikeCustomTabBar(selection: tabSelection, tabs: SpikeTab.phaseOne)
                .frame(height: SpikePanelMetrics.tabBarHeight)

            Color.clear.frame(height: SpikePanelMetrics.sectionGap)

            contentArea
                .frame(height: driver.currentCase.clampedViewport)

            Color.clear.frame(height: SpikePanelMetrics.sectionGap)

            footer
                .frame(height: SpikePanelMetrics.footerHeight)
        }
        .padding(.horizontal, SpikeMetrics.panelPadding)
        .padding(.vertical, SpikePanelMetrics.verticalPadding)
        .frame(
            width: SpikePanelMetrics.width,
            height: driver.currentCase.totalHeight
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(SpikeHeightCase.allCases) { item in
                    Button(item.hudLabel) {
                        driver.select(item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .font(.system(size: 9.5, weight: .medium))
                    .tint(driver.currentCase == item ? .accentColor : .secondary)
                }
            }

            HStack(spacing: 4) {
                Button("连续 20 次") { driver.stressTest() }
                Button("换屏") { driver.cycleScreen() }
                Button(driver.animationEnabled ? "动画 开" : "动画 关") { driver.toggleAnimation() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .font(.system(size: 9.5))

            Text(driver.frameReadout)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    Text("分区内容占位 · \(driver.currentCase.hudLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Spike 2 · 高度切换与顶边固定")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("关闭") { driver.close() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
