import AppKit
import SwiftUI

@MainActor
public final class OCRHistoryWindowController {
    public static let shared = OCRHistoryWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar 识别历史记录"
        win.minSize = NSSize(width: 420, height: 400)
        win.center()
        win.contentViewController = NSHostingController(rootView: OCRHistoryView())
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    public func close() {
        window?.close()
        window = nil
    }
}

public struct OCRHistoryView: View {
    @ObservedObject private var historyManager = OCRHistoryManager.shared
    @ObservedObject private var ocrManager = OCRManager.shared

    @State private var searchText: String = ""
    @State private var filterType: String = "all"
    @State private var copiedItemID: UUID?
    @State private var showClearAlert: Bool = false

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm:ss"
        return df
    }()

    public init() {}

    private var filteredItems: [OCRItem] {
        historyManager.items.filter { item in
            let matchesSearch = searchText.isEmpty || item.text.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filterType {
            case "text":
                matchesFilter = item.type == .text
            case "barcode":
                matchesFilter = item.type == .barcode
            default:
                matchesFilter = true
            }
            return matchesSearch && matchesFilter
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Top Toolbar & Search
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索历史识别内容...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Picker("", selection: $filterType) {
                    Text("全部").tag("all")
                    Text("文本").tag("text")
                    Text("二维码/条码").tag("barcode")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Items List
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(historyManager.items.isEmpty ? "暂无历史识别记录" : "未找到匹配结果")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("可通过主面板点击“屏幕选区识别”进行快速截屏识字")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            historyCard(for: item)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Bottom Action Bar
            HStack {
                Text("共 \(historyManager.items.count) 条历史记录")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    ocrManager.startCaptureAndRecognize()
                }) {
                    Label("立即选区识别", systemImage: "text.viewfinder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !historyManager.items.isEmpty {
                    Button(role: .destructive, action: {
                        showClearAlert = true
                    }) {
                        Label("清空历史", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .frame(minWidth: 420, minHeight: 380)
        .alert("确定清空所有识别历史吗？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("该操作将永久删除已保存在本地的历史文本记录，无法恢复。")
        }
    }

    private func historyCard(for item: OCRItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(item.type == .barcode ? "二维码/条码" : "文本")
                        .font(.system(size: 10, weight: .bold))
                } icon: {
                    Image(systemName: item.type == .barcode ? "qrcode" : "text.alignleft")
                        .font(.system(size: 10))
                }
                .foregroundColor(item.type == .barcode ? .purple : .blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (item.type == .barcode ? Color.purple : Color.blue).opacity(0.12)
                )
                .cornerRadius(4)

                Text(Self.dateFormatter.string(from: item.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                if let url = item.detectedURL {
                    Button(action: {
                        NSWorkspace.shared.open(url)
                    }) {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("在浏览器中打开链接")
                }

                Button(action: {
                    copyItem(item)
                }) {
                    Image(systemName: copiedItemID == item.id ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(copiedItemID == item.id ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("复制文本")

                Button(action: {
                    withAnimation {
                        historyManager.remove(id: item.id)
                    }
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("删除此项")
            }

            Text(item.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func copyItem(_ item: OCRItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        withAnimation {
            copiedItemID = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedItemID == item.id {
                withAnimation {
                    copiedItemID = nil
                }
            }
        }
    }
}
