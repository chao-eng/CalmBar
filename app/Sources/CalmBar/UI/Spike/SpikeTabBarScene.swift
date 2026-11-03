import SwiftUI

private struct SpikeNativeTabBar: View {
    @Binding var selection: String
    let tabs: [SpikeTab]

    var body: some View {
        SpikeTabBarContainer {
            Picker("面板分区", selection: $selection) {
                ForEach(tabs) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct SpikeMockContent: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text("分区内容占位，用于观察分区栏相对位置")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .frame(height: 56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.horizontal, SpikeMetrics.panelPadding)
    }
}

// MARK: - 对比场景

struct SpikeTabBarScene: View {
    @State private var entryMode: SpikeEntryMode = .five
    @State private var nativeSelection: String
    @State private var customSelection: String

    init(initialSelection: String = "thermal") {
        _nativeSelection = State(initialValue: initialSelection)
        _customSelection = State(initialValue: initialSelection)
    }

    private var tabs: [SpikeTab] { entryMode.tabs }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 24) {
                column(
                    title: "候选 A · 原生 Picker(.segmented)",
                    note: "等高分段，无法表达 84 → 40 的变宽与文字淡入。",
                    isCustom: false
                )
                column(
                    title: "候选 B · 自绘胶囊 + 布局动画",
                    note: "40×4 + 84 + 6×4 = 268pt，容器内居中；相邻胶囊同一 transaction 重排。",
                    isCustom: true
                )
            }
            footer
        }
        .padding(20)
        .frame(width: 780, height: 500, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: entryMode) { _, _ in
            if !tabs.contains(where: { $0.id == nativeSelection }) {
                nativeSelection = "thermal"
            }
            if !tabs.contains(where: { $0.id == customSelection }) {
                customSelection = "thermal"
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spike 1 · 分区栏样式双候选")
                    .font(.system(size: 18, weight: .bold))
                Text("面板宽 320pt · 内容宽 292pt · 容器内宽 286pt · 胶囊 24pt 高（选中 84 / 未选中 40）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("入口数", selection: $entryMode) {
                ForEach(SpikeEntryMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
    }

    @ViewBuilder
    private func column(title: String, note: String, isCustom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 30, alignment: .top)

            SpikePanelShell {
                VStack(spacing: 0) {
                    SpikeMockHeader()
                    if isCustom {
                        SpikeCustomTabBar(selection: $customSelection, tabs: tabs)
                    } else {
                        SpikeNativeTabBar(selection: $nativeSelection, tabs: tabs)
                    }
                    SpikeMockContent(title: tabs.first(where: { $0.id == (isCustom ? customSelection : nativeSelection) })?.title ?? "分区")
                    Spacer(minLength: 0)
                }
                .frame(height: 210)
            }
        }
        .frame(width: SpikeMetrics.panelWidth)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("验收关注点：胶囊高度 24pt、选中底 accent 12%、容器底 primary 5%、圆角 9/6、无外框；切换时只做宽度动画与文字淡入，邻居随布局平滑重排，不叠加独立位移动画。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("注：候选 A 若只渲染文字或分段等宽，即验证 §6.5 Spike 1 第 1 条“原生无法满足变宽”的退路成立。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
