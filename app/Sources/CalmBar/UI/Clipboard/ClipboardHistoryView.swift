import AppKit
import SwiftUI

public struct ClipboardHistoryView: View {
    @ObservedObject private var historyManager = ClipboardHistoryManager.shared
    @ObservedObject private var monitor = ClipboardMonitor.shared

    @State private var searchText: String = ""
    @State private var selectedFilter: ClipboardFilterType = .all
    @State private var copiedItemID: UUID?
    @State private var showClearAlert: Bool = false

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm:ss"
        return df
    }()

    public init() {}

    public enum ClipboardFilterType: String, CaseIterable, Identifiable {
        case all = "全部"
        case text = "文本"
        case image = "图片"
        case url = "链接"
        case fileURL = "文件"
        case pinned = "已固定"

        public var id: String { rawValue }
    }

    private var filteredItems: [ClipboardItem] {
        historyManager.items.filter { item in
            // 分类筛选
            let matchesCategory: Bool
            switch selectedFilter {
            case .all:
                matchesCategory = true
            case .text:
                matchesCategory = (item.type == .text || item.type == .richText)
            case .image:
                matchesCategory = (item.type == .image)
            case .url:
                matchesCategory = (item.type == .url)
            case .fileURL:
                matchesCategory = (item.type == .fileURL)
            case .pinned:
                matchesCategory = item.isPinned
            }

            if !matchesCategory { return false }

            // 关键词搜索
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }

            let query = searchText.lowercased()
            let titleMatch = item.title.lowercased().contains(query)
            let textMatch = (item.textValue ?? "").lowercased().contains(query)
            let appMatch = (item.sourceAppBundle ?? "").lowercased().contains(query)

            return titleMatch || textMatch || appMatch
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            filterBar
            Divider()

            if historyManager.items.isEmpty {
                emptyHistoryView
            } else if filteredItems.isEmpty {
                noMatchView
            } else {
                itemsListView
            }

            Divider()
            bottomStatusBar
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("清空剪贴板历史", isPresented: $showClearAlert) {
            Button("清空未固定记录", role: .destructive) {
                historyManager.clearAll(keepPinned: true)
            }
            Button("清空全部 (包括已固定)", role: .destructive) {
                historyManager.clearAll(keepPinned: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("您希望如何清理剪贴板历史记录？固定项（Pin）可以为您长期保留重要文本或代码。")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)

            Text("剪贴板历史记录")
                .font(.system(size: 14, weight: .bold))

            Spacer()

            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("搜索剪贴板内容、应用或图片文字...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .frame(width: 240)

            // 清空按钮
            Button(action: { showClearAlert = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("清空历史记录")
            .disabled(historyManager.items.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Picker("", selection: $selectedFilter) {
                ForEach(ClipboardFilterType.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer()

            Text("共 \(filteredItems.count) 条")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Items List View

    private var itemsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredItems) { item in
                    clipboardItemCard(for: item)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Card View

    private func clipboardItemCard(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 卡片顶栏：图标 + 类型 + 来源 App + 时间 + Pin 按钮
            HStack(spacing: 6) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)

                Text(item.type.titleZH)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                if let appName = item.sourceAppName {
                    Text("·  \(appName)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if item.copyCount > 1 {
                    Text("(\(item.copyCount)次复制)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }

                Spacer()

                Text(Self.dateFormatter.string(from: item.copiedAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                // Pin 置顶按钮
                Button(action: {
                    historyManager.togglePin(id: item.id)
                }) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(item.isPinned ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "取消固定" : "固定置顶")
            }

            // 卡片内容展示区
            contentPreviewView(for: item)

            // 卡片底栏：统计徽章 + 复制 / 纯文本复制 / 删除
            HStack(spacing: 8) {
                if item.characterCount > 0 {
                    Text("\(item.characterCount) 字符 · \(item.lineCount) 行")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if copiedItemID == item.id {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("已复制到剪贴板")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .transition(.opacity.combined(with: .scale))
                }

                // 复制按钮
                Button(action: {
                    copyItemToPasteboard(item: item, plainTextOnly: false)
                }) {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.accentColor)

                // 纯文本复制（富文本时提供）
                if item.type == .richText {
                    Button(action: {
                        copyItemToPasteboard(item: item, plainTextOnly: true)
                    }) {
                        Text("纯文本")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("剥离样式以纯文本写入剪贴板")
                }

                // 删除按钮
                Button(action: {
                    historyManager.remove(id: item.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("删除此条记录")
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.isPinned ? Color.orange.opacity(0.4) : Color.secondary.opacity(0.12), lineWidth: item.isPinned ? 1.5 : 1)
        )
    }

    // MARK: - Content Preview

    @ViewBuilder
    private func contentPreviewView(for item: ClipboardItem) -> some View {
        switch item.type {
        case .text, .richText:
            if let text = item.textValue {
                Text(text)
                    .font(.system(size: 12, design: text.contains("\n") ? .monospaced : .default))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
            }
        case .image:
            if let nsImage = imageFor(item: item) {
                HStack(spacing: 10) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                        .cornerRadius(4)
                        .shadow(radius: 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        if let ocrText = item.textValue, !ocrText.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(ocrText.components(separatedBy: .newlines).prefix(3), id: \.self) { line in
                                    if line.hasPrefix("[二维码:") {
                                        HStack(spacing: 4) {
                                            Image(systemName: "qrcode")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 10))
                                            Text(line)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.blue)
                                                .lineLimit(1)
                                        }
                                    } else {
                                        Text(line)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(6)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(4)
            }
        case .url:
            if let urlStr = item.textValue {
                HStack(spacing: 6) {
                    Image(systemName: "safari.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 13))
                    Text(urlStr)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(6)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(4)
            }
        case .fileURL:
            if let files = item.fileURLs {
                if files.count == 1, let firstPath = files.first,
                   ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains(URL(fileURLWithPath: firstPath).pathExtension.lowercased()),
                   let nsImage = NSImage(contentsOfFile: firstPath) {
                    HStack(spacing: 10) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .cornerRadius(4)
                            .shadow(radius: 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: firstPath).lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Text(firstPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files.prefix(3), id: \.self) { path in
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 11))
                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                        if files.count > 3 {
                            Text("... 等共 \(files.count) 个文件")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
            }
        case .color:
            if let colorHex = item.textValue {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    Text(colorHex)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))

                    Spacer()
                }
                .padding(6)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(4)
            }
        }
    }

    // MARK: - Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(monitor.isMonitoring ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(monitor.isMonitoring ? "剪贴板监听运行中" : "监听已暂停")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("本地存储占用: \(historyManager.storageSizeFormatted)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Empty Views

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text("暂无剪贴板历史记录")
                .font(.system(size: 14, weight: .medium))
            Text("在任意应用中按下 ⌘+C 复制文本、图片或文件，CalmBar 将自动在此为您安全归档。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var noMatchView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            Text("未找到与「\(searchText)」匹配的内容")
                .font(.system(size: 13, weight: .medium))
            Text("尝试更换搜索关键词或切换上方的格式分类筛选。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Actions

    private func imageFor(item: ClipboardItem) -> NSImage? {
        if let imgName = item.imageFileName {
            let imgURL = historyManager.imagesDirectoryURL.appendingPathComponent(imgName)
            if let img = NSImage(contentsOf: imgURL) {
                return img
            }
        }
        if let firstPath = item.fileURLs?.first {
            if let img = NSImage(contentsOfFile: firstPath) {
                return img
            }
        }
        return nil
    }

    private func copyItemToPasteboard(item: ClipboardItem, plainTextOnly: Bool) {
        historyManager.copyToPasteboard(item: item, plainTextOnly: plainTextOnly)
        withAnimation(.easeInOut(duration: 0.2)) {
            self.copiedItemID = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.copiedItemID == item.id {
                withAnimation {
                    self.copiedItemID = nil
                }
            }
        }
    }
}

// MARK: - Color Hex Helper Extension

private extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        let r, g, b, a: Double
        if length == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
