import SwiftUI

// MARK: - M1 隔离场景：分区栏 + 内容区标题 + 三分区骨架

struct M1Scene: View {
    @ObservedObject var driver: M1Driver

    private var route: PopoverTabRoute { PopoverTabRoute.route(for: driver.currentTab) }

    private var tabSelection: Binding<PopoverTab> {
        Binding(
            get: { driver.currentTab },
            set: { _ = driver.selectTab($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: PopoverLayout.headerHeight)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("CalmBar 状态栏")

            Color.clear.frame(height: PopoverLayout.sectionGap)

            PopoverTabBar(
                selection: tabSelection,
                tabs: driver.availableTabs,
                animationDuration: driver.reduceMotion ? 0 : PopoverLayout.tabBarAnimation,
                onMeasure: { width in
                    driver.noteTabBarWidth(width)
                }
            )
            .frame(height: PopoverLayout.tabBarHeight)

            Color.clear.frame(height: PopoverLayout.sectionGap)

            sectionTitle
                .frame(height: PopoverLayout.titleHeight)

            Color.clear.frame(height: PopoverLayout.blockGap)

            content
                .frame(height: route.viewportHeight, alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("内容区")

            footer
                .frame(height: PopoverLayout.footerHeight)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("底栏")
        }
        .padding(PopoverLayout.padding)
        .frame(width: PopoverLayout.panelWidth, height: route.totalHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(driver.increaseContrast ? 0.32 : 0.12),
                    lineWidth: driver.increaseContrast ? 1.0 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
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
    }

    private var sectionTitle: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(route.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("分区标题")
            .accessibilityValue(route.title)

            if route.tab == .audio, !driver.m7Empty {
                Button {
                    driver.noteSectionAction(.audio, "more")
                } label: {
                    HStack(spacing: 2) {
                        Text("更多")
                            .font(.system(size: 9))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开应用混音窗口")
                .accessibilityLabel("更多")
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch route.kind {
        case .thermalCards:
            thermalContent
        case .guardianCards:
            guardianContent
        case .toolTiles:
            toolsContent
        case .monitorCards:
            monitorContent
        case .audioMixer:
            audioContent
        }
    }

    @ViewBuilder
    private var thermalContent: some View {
        VStack(spacing: PopoverLayout.blockGap) {
            if driver.useRealThermal {
                // M2：真实温控视图（仪表 + 风扇/无风扇 + 权限横幅）
                ThermalSectionView(
                    viewportHeight: route.viewportHeight,
                    stressExtraHeight: driver.stressMode ? 600 : 0,
                    allHidden: driver.m6Empty,
                    onMeasure: { height in
                        driver.noteThermalHeight(height)
                    }
                )
            } else {
                M1Card(icon: "thermometer.medium", title: "温度仪表", detail: "CPU 42°C · GPU 38°C", trailing: "读数")
                M1Card(icon: "fanblades", title: "风扇调速", detail: "当前 1800 RPM · 自动", trailing: "自动")
                Spacer(minLength: 0)
            }
        }
        .onAppear { driver.noteAppear(.thermal) }
    }

    @ViewBuilder
    private var guardianContent: some View {
        Group {
            if driver.useRealGuardian {
                // M3：真实守护视图（单列卡片 + 辅助功能横幅）
                GuardianSectionView(
                    viewportHeight: route.viewportHeight,
                    stressExtraHeight: driver.stressMode ? 600 : 0,
                    allHidden: driver.m6Empty,
                    onMeasure: { height in
                        driver.noteGuardianHeight(height)
                    }
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    M1Card(icon: "lock.shield", title: "锁屏守护", detail: "会话保护", trailing: "开")
                        .frame(height: 64)
                    M1Card(icon: "battery.75", title: "充电保护", detail: "上限 80%", trailing: "开")
                        .frame(height: 64)
                    M1Card(icon: "moon.zzz", title: "休眠守卫", detail: "合盖不断连", trailing: "关")
                        .frame(height: 64)
                    M1Card(icon: "arrow.clockwise", title: "自启动", detail: "登录后恢复", trailing: "开")
                        .frame(height: 64)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear { driver.noteAppear(.guardian) }
    }

    @ViewBuilder
    private var toolsContent: some View {
        Group {
            if driver.useRealTools {
                // M4：真实工具网格（4 × 67pt 磁贴，动作仅记录）
                ToolGridSectionView(
                    viewportHeight: route.viewportHeight,
                    allHidden: driver.m6Empty,
                    onAction: { tool in
                        driver.noteToolAction(tool.rawValue)
                    },
                    onContextAction: { tool, action in
                        driver.noteToolAction("\(tool.rawValue):\(action)")
                    },
                    onMeasure: { height, width in
                        driver.noteToolHeight(height, width: width)
                    }
                )
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(67), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    M1Tile(icon: "nosign", title: "应用去隔离")
                    M1Tile(icon: "rectangle.on.rectangle", title: "窗口贴边")
                    M1Tile(icon: "eyedropper", title: "屏幕取色")
                    M1Tile(icon: "doc.on.clipboard", title: "剪贴板历史")
                    M1Tile(icon: "command", title: "快捷指令")
                    M1Tile(icon: "speaker.wave.2", title: "音频路由")
                    M1Tile(icon: "sun.max", title: "保持唤醒")
                    M1Tile(icon: "rectangle.dashed", title: "隐藏桌面")
                }
                .frame(width: PopoverLayout.contentWidth, alignment: .top)
            }
        }
        .onAppear { driver.noteAppear(.tools) }
    }

    @ViewBuilder
    private var monitorContent: some View {
        Group {
            if driver.useRealMonitor {
                // M7：只读监控骨架（三卡 + 趋势占位 + 告警入口，不启动采样）
                MonitorSectionView(
                    onMeasure: { height in
                        driver.noteMonitorHeight(height)
                    },
                    onAction: { action in
                        driver.noteSectionAction(.monitor, action)
                    }
                )
            } else {
                VStack(spacing: 6) {
                    Image(systemName: route.tab.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("监控分区预留")
                        .font(.system(size: 12, weight: .medium))
                    Text("Phase 2 接入")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { driver.noteAppear(.monitor) }
    }

    @ViewBuilder
    private var audioContent: some View {
        Group {
            if driver.useRealAudio {
                // M7：声音分区骨架（最多 4 行应用音量，不接音频引擎）
                AudioSectionView(
                    isEmpty: driver.m7Empty,
                    onMeasure: { height in
                        driver.noteAudioHeight(height)
                    },
                    onAction: { action in
                        driver.noteSectionAction(.audio, action)
                    }
                )
            } else {
                VStack(spacing: 6) {
                    Image(systemName: route.tab.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("声音分区预留")
                        .font(.system(size: 12, weight: .medium))
                    Text("Phase 2 接入")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { driver.noteAppear(.audio) }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(driver.statusReadout)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text("\(driver.skeletonLabel) 骨架 · \(route.title)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 内容占位组件（M2–M4 迁移旧视图时替换）

private struct M1Card: View {
    let icon: String
    let title: String
    let detail: String
    let trailing: String

    var body: some View {
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
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9))
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
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct M1Tile: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)
                }
            Text(title)
                .font(.system(size: 10))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 67, height: 84)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("按钮")
        .accessibilityAddTraits(.isButton)
    }
}
