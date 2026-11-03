import SwiftUI
import CalmBarKit

// MARK: - M4 工具分区：4 列 × 67pt 磁贴网格

enum ToolGridItem: String, CaseIterable, Identifiable, Sendable {
    case ocr
    case translation
    case clipboard
    case cleaner
    case gatekeeper
    case launchManager

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ocr: "text.viewfinder"
        case .translation: "character.bubble.fill"
        case .clipboard: "doc.on.clipboard"
        case .cleaner: "trash.fill"
        case .gatekeeper: "lock.shield"
        case .launchManager: "gearshape.arrow.triangle.2.circlepath"
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .ocr: "截屏识字"
        case .translation: "AI 翻译"
        case .clipboard: "剪贴板"
        case .cleaner: "清理中心"
        case .gatekeeper: "应用去隔离"
        case .launchManager: LaunchManager.shared.crashLoopingItems.isEmpty ? "自启管理" : "自启异常"
        }
    }

    var help: String {
        switch self {
        case .ocr: "选区截图识字与二维码解析 (右键打开历史)"
        case .translation: "翻译当前剪贴板文本 (双击 ⌘C 或 ⌥⌘T 快速触发，右键打开历史)"
        case .clipboard: "浏览剪贴板历史"
        case .cleaner: "软件残留 · 开发缓存 · 孤立工作区清理"
        case .gatekeeper: "修复未签名或损坏应用提示"
        case .launchManager: "管理后台自启项、常驻守护服务与监听端口"
        }
    }
}

struct ToolGridSectionView: View {
    @ObservedObject private var settings = AppSettings.shared

    var viewportHeight: CGFloat
    var allHidden: Bool = false
    var onAction: (ToolGridItem) -> Void = { _ in }
    var onContextAction: ((ToolGridItem, String) -> Void)?
    var onMeasure: ((CGFloat, CGFloat) -> Void)?

    private var activeTools: [ToolGridItem] {
        guard !allHidden else { return [] }
        return ToolGridItem.allCases.filter { tool in
            PopoverVisibilityItem(rawValue: tool.rawValue)?.isEnabled(settings) ?? false
        }
    }

    var body: some View {
        Group {
            if activeTools.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(PopoverLayout.toolTileWidth), spacing: PopoverLayout.toolGridSpacing),
                        count: 4
                    ),
                    alignment: .leading,
                    spacing: PopoverLayout.toolGridSpacing
                ) {
                    ForEach(activeTools) { tool in
                        ToolGridTile(
                            item: tool,
                            action: { onAction(tool) },
                            help: tool.help
                        )
                        .contextMenu {
                            contextMenu(for: tool)
                        }
                    }
                }
            }
        }
        .frame(width: PopoverLayout.contentWidth, alignment: .topLeading)
        .background(heightReader)
        .frame(width: PopoverLayout.contentWidth, height: viewportHeight, alignment: .topLeading)
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onMeasure?(proxy.size.height, proxy.size.width) }
                .onChange(of: proxy.size.height) { _, height in
                    onMeasure?(height, proxy.size.width)
                }
        }
    }

    private var emptyState: some View {
        PopoverEmptyState(group: .tools)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for tool: ToolGridItem) -> some View {
        switch tool {
        case .ocr:
            Button("打开 OCR 历史记录") {
                onContextAction?(tool, "ocrHistory")
            }
        case .translation:
            Button("打开翻译历史记录") {
                onContextAction?(tool, "translationHistory")
            }
        case .launchManager:
            Button("打开启动项与服务管理") {
                onContextAction?(tool, "launchManager")
            }
            Button("排查服务监听端口") {
                onContextAction?(tool, "services")
            }
        default:
            EmptyView()
        }
    }
}

private struct ToolGridTile: View {
    let item: ToolGridItem
    let action: () -> Void
    let help: String

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)

                Text(item.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: PopoverLayout.toolTileWidth, height: PopoverLayout.toolTileHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .focusable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)，快捷工具")
        .accessibilityValue("按钮")
        .accessibilityAddTraits(.isButton)
    }
}
