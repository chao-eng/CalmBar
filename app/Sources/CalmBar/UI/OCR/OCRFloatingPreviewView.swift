import AppKit
import SwiftUI
import Combine
import CalmBarKit

@MainActor
public final class OCRFloatingPreviewController {
    public static let shared = OCRFloatingPreviewController()

    private var window: NSWindow?

    private init() {}

    public func show(item: OCRItem) {
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
    }

    public func close() {
        window?.close()
        window = nil
    }
}

public struct OCRFloatingPreviewView: View {
    let item: OCRItem
    let onClose: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    @State private var copied: Bool = false
    @State private var editedText: String
    @State private var remainingSeconds: Int
    @State private var isHovered: Bool = false

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(item: OCRItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        self._editedText = State(initialValue: item.text)
        let delay = Int(max(2.0, AppSettings.shared.ocrAutoDismissDelay))
        self._remainingSeconds = State(initialValue: delay)
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
                .focusable(false)
                .focusEffectDisabled()
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
                    .focusable(false)
                    .focusEffectDisabled()
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
                .focusable(false)
                .focusEffectDisabled()
                .help("从本地历史记录中删除此条并关闭浮窗")

                // 一键 AI 翻译
                Button(action: {
                    let textToTranslate = editedText.isEmpty ? item.text : editedText
                    TranslationManager.shared.translate(text: textToTranslate)
                }) {
                    Label("AI 翻译", systemImage: "character.bubble.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
                .focusEffectDisabled()
                .help("使用 AI 翻译当前识别出的文字")

                Spacer()

                // 倒计时指示器 (开启自动消失时展示)
                if settings.ocrAutoDismiss {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("\(max(1, remainingSeconds))s")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(isHovered ? .orange : .white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    .help(isHovered ? "鼠标悬停中，倒计时已暂停" : "\(remainingSeconds) 秒后自动关闭")
                    .transition(.opacity)
                }

                Button(action: copyToClipboard) {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(copied ? .green : .accentColor)
                .focusable(false)
                .focusEffectDisabled()
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
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(timer) { _ in
            guard settings.ocrAutoDismiss, !isHovered else { return }
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                onClose()
            }
        }
        .onChange(of: item.id) { _, _ in
            editedText = item.text
            remainingSeconds = Int(max(2.0, settings.ocrAutoDismissDelay))
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
