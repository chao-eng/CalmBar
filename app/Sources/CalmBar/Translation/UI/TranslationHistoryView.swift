import SwiftUI
import AppKit
import CalmBarKit

@MainActor
public final class TranslationHistoryWindowController {
    public static let shared = TranslationHistoryWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "AI 翻译历史记录"
        newWindow.center()
        newWindow.setFrameAutosaveName("TranslationHistoryWindow")
        newWindow.contentViewController = NSHostingController(rootView: TranslationHistoryView())
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public struct TranslationHistoryView: View {
    @ObservedObject private var historyManager = TranslationHistoryManager.shared
    @State private var searchText = ""
    @State private var copiedID: UUID?

    public init() {}

    private var filteredItems: [TranslationItem] {
        if searchText.isEmpty {
            return historyManager.history
        }
        return historyManager.history.filter {
            $0.originalText.localizedCaseInsensitiveContains(searchText) ||
            $0.translatedText.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar & Actions
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索原文或译文...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("清空历史") {
                    historyManager.clearAll()
                }
                .disabled(historyManager.history.isEmpty)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "character.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(historyManager.history.isEmpty ? "暂无翻译历史记录" : "无匹配结果")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        historyRow(for: item)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 500, minHeight: 350)
    }

    private func historyRow(for item: TranslationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                let targetLang = TranslationLanguage.find(byCode: item.targetLanguage)
                Text("目标语言: \(targetLang.displayName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)

                Text(item.model)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                if let ms = item.latencyMs {
                    Text("· \(ms)ms")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Button(action: {
                    copyToClipboard(item.translatedText, id: item.id)
                }) {
                    Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(copiedID == item.id ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("复制译文")

                Button(action: {
                    historyManager.delete(id: item.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除此条记录")
            }

            Text(item.originalText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(item.translatedText)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }

    private func copyToClipboard(_ text: String, id: UUID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedID == id {
                copiedID = nil
            }
        }
    }
}
