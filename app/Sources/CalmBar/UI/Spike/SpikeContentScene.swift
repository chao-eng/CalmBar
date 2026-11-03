import SwiftUI

struct SpikeContentScene: View {
    @ObservedObject var driver: SpikeContentDriver

    private var tabSelection: Binding<String> {
        Binding(
            get: { driver.currentTab },
            set: { driver.selectTab($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SpikeMockHeader()
                .frame(height: SpikeContentMetrics.headerHeight)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("CalmBar 状态栏")

            Color.clear.frame(height: SpikeContentMetrics.sectionGap)

            SpikeCustomTabBar(
                selection: tabSelection,
                tabs: SpikeTab.phaseOne,
                animationDuration: driver.reduceMotion ? 0 : SpikeMetrics.tabBarAnimation
            )
            .frame(height: SpikeContentMetrics.tabBarHeight)

            Color.clear.frame(height: SpikeContentMetrics.sectionGap)

            contentArea
                .frame(height: SpikeContentMetrics.viewportHeight)
                .accessibilityElement(children: .contain)

            Color.clear.frame(height: SpikeContentMetrics.sectionGap)

            footer
                .frame(height: SpikeContentMetrics.footerHeight)
                .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, SpikeContentMetrics.horizontalPadding)
        .padding(.vertical, SpikeContentMetrics.verticalPadding)
        .frame(width: SpikeContentMetrics.width, height: SpikeContentMetrics.totalHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(driver.increaseContrast ? 0.32 : 0.12),
                    lineWidth: driver.increaseContrast ? 1.0 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // 网格实际宽度回传到驱动，用于校验 292 零余量
        .onPreferenceChange(SpikeGridWidthKey.self) { width in
            if width > 0 {
                driver.noteGridWidth(width)
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch driver.currentTab {
        case "guardian":
            guardianContent
        case "tools":
            toolsContent
        default:
            thermalContent
        }
    }

    // MARK: 温控：2 张纵向卡片

    private var thermalContent: some View {
        VStack(spacing: 8) {
            mockCard(
                icon: "thermometer.medium",
                title: "温度仪表",
                detail: "CPU 42°C · GPU 38°C",
                trailing: "读数"
            )
            mockCard(
                icon: "fanblades",
                title: "风扇调速",
                detail: "当前 1800 RPM · 自动",
                trailing: "自动"
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            driver.noteAppear(driver.currentTab)
        }
    }

    // MARK: 守护：2×2 卡片

    private var guardianContent: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            mockCard(icon: "lock.shield", title: "锁屏守护", detail: "会话保护", trailing: "开")
                .frame(height: 64)
            mockCard(icon: "battery.75", title: "充电保护", detail: "上限 80%", trailing: "开")
                .frame(height: 64)
            mockCard(icon: "moon.zzz", title: "休眠守卫", detail: "合盖不断连", trailing: "关")
                .frame(height: 64)
            mockCard(icon: "arrow.clockwise", title: "自启动", detail: "登录后恢复", trailing: "开")
                .frame(height: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            driver.noteAppear(driver.currentTab)
        }
    }

    // MARK: 工具：4 列 67×84 网格

    private var toolsContent: some View {
        VStack(spacing: 0) {
            SpikeToolGrid(
                english: driver.english,
                fontScale: driver.fontScale,
                increaseContrast: driver.increaseContrast
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            driver.noteAppear(driver.currentTab)
        }
    }

    private func mockCard(icon: String, title: String, detail: String, trailing: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.tint)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11 * driver.fontScale, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9 * driver.fontScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(trailing)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(driver.statusReadout)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if driver.largeText {
                Text("大字")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if driver.english {
                Text("EN")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Button("关闭") { driver.close() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭面板")
        }
    }
}
