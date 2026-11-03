import SwiftUI

struct SpikeScrollScene: View {
    @ObservedObject var driver: SpikeScrollDriver

    private var tabSelection: Binding<String> {
        Binding(
            get: { driver.currentTab },
            set: { driver.selectTab($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SpikeMockHeader()
                .frame(height: SpikeScrollMetrics.headerHeight)

            Color.clear.frame(height: SpikeScrollMetrics.sectionGap)

            SpikeCustomTabBar(selection: tabSelection, tabs: SpikeTab.phaseOne)
                .frame(height: SpikeScrollMetrics.tabBarHeight)

            Color.clear.frame(height: SpikeScrollMetrics.sectionGap)

            scrollArea
                .frame(height: SpikeScrollMetrics.viewportHeight)

            Color.clear.frame(height: SpikeScrollMetrics.sectionGap)

            footer
                .frame(height: SpikeScrollMetrics.footerHeight)
        }
        .padding(.horizontal, SpikeMetrics.panelPadding)
        .padding(.vertical, SpikeScrollMetrics.verticalPadding)
        .frame(
            width: SpikeScrollMetrics.width,
            height: SpikeScrollMetrics.totalHeight
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // 600pt 内容放进 400pt 视口，用于验证滚轮、惯性与首尾橡皮筋
    private var scrollArea: some View {
        ScrollView(.vertical) {
            VStack(spacing: SpikeScrollMetrics.sectionGap) {
                ForEach(0..<3, id: \.self) { section in
                    sectionBlock(section)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(height: SpikeScrollMetrics.contentHeight)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.automatic)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionBlock(_ section: Int) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(sectionTitle(section))
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("4 项")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 18)

            ForEach(0..<4, id: \.self) { row in
                mockCard(section: section, row: row)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 6)
    }

    private func mockCard(section: Int, row: Int) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: cardIcon(section, row))
                        .font(.system(size: 9))
                        .foregroundStyle(.tint)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("占位卡 \(section + 1)-\(row + 1)")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Text("滚动测试条目 · 无真实动作")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 24, height: 12)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private func sectionTitle(_ section: Int) -> String {
        switch section {
        case 0: return "温控 · 仪表与风扇"
        case 1: return "守护 · 会话与电源"
        default: return "工具 · 快捷入口"
        }
    }

    private func cardIcon(_ section: Int, _ row: Int) -> String {
        let icons = ["thermometer.medium", "fanblades", "shield.lefthalf.filled", "battery.75",
                     "square.grid.2x2", "scissors", "camera", "lock.shield"]
        return icons[(section * 4 + row) % icons.count]
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(driver.offsetReadout)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text("PgUp/Dn")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Button("关闭") { driver.close() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
