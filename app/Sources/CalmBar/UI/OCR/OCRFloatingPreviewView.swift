import AppKit
import SwiftUI

@MainActor
public final class OCRFloatingPreviewController {
    public static let shared = OCRFloatingPreviewController()

    private var window: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    public func show(item: OCRItem) {
        dismissWorkItem?.cancel()

        if let existing = window, existing.isVisible {
            existing.standardWindowButton(.closeButton)?.isHidden = true
            existing.standardWindowButton(.miniaturizeButton)?.isHidden = true
            existing.standardWindowButton(.zoomButton)?.isHidden = true
            existing.contentViewController = NSHostingController(
                rootView: OCRFloatingPreviewView(item: item, onClose: { [weak self] in
                    self?.close()
                })
                .id(item.id)
                .environment(\.colorScheme, .dark)
            )
            existing.makeKeyAndOrderFront(nil)
            scheduleAutoDismiss()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)

        // 彻底隐藏原生左上角红绿灯按钮，避免重复与无效点击
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentViewController = NSHostingController(
            rootView: OCRFloatingPreviewView(item: item, onClose: { [weak self] in
                self?.close()
            })
            .id(item.id)
            .environment(\.colorScheme, .dark)
        )

        // 定位在屏幕右上方（避开顶部菜单栏）
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 500
            let y = visibleFrame.maxY - 340
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel

        scheduleAutoDismiss()
    }

    public func close() {
        dismissWorkItem?.cancel()
        window?.close()
        window = nil
    }

    private func scheduleAutoDismiss() {
        let settings = AppSettings.shared
        guard settings.ocrAutoDismiss else { return }

        let delay = max(1.0, settings.ocrAutoDismissDelay)
        let work = DispatchWorkItem { [weak self] in
            self?.close()
        }
        self.dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

public struct OCRFloatingPreviewView: View {
    let item: OCRItem
    let onClose: () -> Void

    @State private var copied: Bool = false
    @State private var editedText: String

    public init(item: OCRItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        self._editedText = State(initialValue: item.text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: item.type == .barcode ? "qrcode" : "text.viewfinder")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .bold))

                Text(item.type == .barcode ? "识别结果 (二维码/条码)" : "识别结果 (文字)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // 单一右上角关闭按钮
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("关闭悬浮卡片")
            }

            // Content Text Viewer
            ScrollView {
                Text(editedText.isEmpty ? item.text : editedText)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 140, maxHeight: 260)
            .background(Color.black.opacity(0.45))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            // Bottom Actions
            HStack(spacing: 8) {
                if let url = item.detectedURL {
                    Button(action: {
                        NSWorkspace.shared.open(url)
                    }) {
                        Label("打开链接", systemImage: "safari")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // 从历史中删除此条记录并关闭
                Button(action: {
                    OCRHistoryManager.shared.remove(id: item.id)
                    onClose()
                }) {
                    Label("删除记录", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.8))
                .controlSize(.small)
                .help("从本地历史记录中删除此条并关闭浮窗")

                Spacer()

                Button(action: copyToClipboard) {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(copied ? .green : .accentColor)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onChange(of: item.id) { _, _ in
            editedText = item.text
        }
    }

    private func copyToClipboard() {
        let textToCopy = editedText.isEmpty ? item.text : editedText
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copied = false
            }
        }
    }
}
