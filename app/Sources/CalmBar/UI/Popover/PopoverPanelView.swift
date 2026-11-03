import SwiftUI
import CalmBarKit

// MARK: - 生产面板（M8：替换旧单列 PopoverContentView）

struct PopoverPanelView: View {
    @ObservedObject var model: PopoverPanelModel

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var dashboard = DashboardViewModel.shared
    @ObservedObject private var thermal = ThermalMonitor.shared
    @ObservedObject private var helper = HelperClient.shared

    var openSettingsAction: (SettingsTab) -> Void
    var closePanel: () -> Void

    private var route: PopoverTabRoute { model.route }

    private var tabSelection: Binding<PopoverTab> {
        Binding(
            get: { model.currentTab },
            set: { _ = model.select($0) }
        )
    }

    var body: some View {
        panelBody
            .frame(width: PopoverLayout.panelWidth, height: route.totalHeight)
            .background(.regularMaterial, in: panelShape)
            .overlay {
                panelShape
                    .strokeBorder(
                        PopoverPalette.separatorEmphasized,
                        lineWidth: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.0 : 0.5
                    )
            }
            .clipShape(panelShape)
            // 窗口高度恒定：内容贴着顶边向下延长，避免窗口 resize 引起的重建抖动
            .frame(width: PopoverLayout.panelWidth, height: PopoverLayout.maxPanelHeight, alignment: .top)
            .animation(
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? nil
                    : Animation.easeInOut(duration: PopoverLayout.heightAnimation),
                value: route.totalHeight
            )
            // 面板内所有控件统一不绘制系统焦点环，保持黑灰单色观感
            .focusable(false)
            .focusEffectDisabled()
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var panelBody: some View {
        VStack(spacing: 0) {
            header
                .frame(height: PopoverLayout.headerHeight)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("CalmBar 状态栏")

            Color.clear.frame(height: PopoverLayout.sectionGap)

            PopoverTabBar(
                selection: tabSelection,
                tabs: model.availableTabs,
                animationDuration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : PopoverLayout.tabBarAnimation
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
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wind")
                .font(.system(size: 15))
            Text("CalmBar")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            headerStatus

            Button {
                CommandPaletteWindowController.shared.showWindow()
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("打开命令面板 (Command Palette)")
            .accessibilityLabel("命令面板")
        }
    }

    @ViewBuilder
    private var headerStatus: some View {
        if !dashboard.isSMCConnected {
            statusBadge(icon: "exclamationmark.triangle.fill", text: "无 SMC 驱动", tint: PopoverPalette.statusCritical)
        } else if settings.thermalEnabled && dashboard.safetyAction != .none {
            statusBadge(icon: "flame.fill", text: "温控保护中", tint: PopoverPalette.statusWarning)
        } else if !settings.thermalEnabled {
            statusBadge(icon: nil, text: "温控已停用")
        } else if helper.needsHelperUpdate {
            statusBadge(icon: "lock.shield", text: "助手需更新", tint: PopoverPalette.statusWarning)
        } else {
            statusBadge(icon: nil, text: thermal.isFanless ? "温度监控中" : "温控运行中", tint: PopoverPalette.statusSuccess)
        }
    }

    private func statusBadge(icon: String?, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("状态：\(text)")
    }

    // MARK: 分区标题

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

            switch route.tab {
            case .tools:
                titleAction("自定义") {
                    openSettingsAction(.general)
                }
            case .audio:
                titleAction("更多") {
                    // 混音窗口随音频模块上线接入
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 2)
    }

    private func titleAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 9))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch route.kind {
        case .thermalCards:
            ThermalSectionView(viewportHeight: route.viewportHeight)
        case .guardianCards:
            GuardianSectionView(viewportHeight: route.viewportHeight)
        case .toolTiles:
            ToolGridSectionView(
                viewportHeight: route.viewportHeight,
                onAction: { tool in
                    handleTool(tool)
                },
                onContextAction: { tool, action in
                    handleToolContext(tool, action)
                }
            )
        case .monitorCards:
            MonitorSectionView(onAction: { action in
                if action == "alert-settings" {
                    openSettingsAction(.monitor)
                }
            })
        case .audioMixer:
            AudioSectionView(isEmpty: false)
        }
    }

    private func handleTool(_ tool: ToolGridItem) {
        switch tool {
        case .ocr:
            closePanel()
            OCRManager.shared.startCaptureAndRecognize()
        case .translation:
            closePanel()
            TranslationManager.shared.translateFromClipboard()
        case .clipboard:
            closePanel()
            ClipboardHistoryWindowController.shared.show()
        case .cleaner:
            closePanel()
            CleanerWindowController.shared.show()
        case .gatekeeper:
            openSettingsAction(.gatekeeper)
        case .launchManager:
            closePanel()
            let tab: LaunchManagerTab = LaunchManager.shared.crashLoopingItems.isEmpty ? .userAgents : .crashLooping
            LaunchManagerWindowController.shared.show(initialTab: tab)
        }
    }

    private func handleToolContext(_ tool: ToolGridItem, _ action: String) {
        closePanel()
        switch action {
        case "ocrHistory":
            OCRHistoryWindowController.shared.show()
        case "translationHistory":
            TranslationHistoryWindowController.shared.show()
        case "launchManager":
            LaunchManagerWindowController.shared.show()
        case "services":
            LaunchManagerWindowController.shared.show(initialTab: .services)
        default:
            break
        }
    }

    // MARK: 底栏

    private var footer: some View {
        HStack {
            Button {
                openSettingsAction(.thermal)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("偏好设置")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("偏好设置")

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出 CalmBar")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("退出 CalmBar")
        }
    }
}
