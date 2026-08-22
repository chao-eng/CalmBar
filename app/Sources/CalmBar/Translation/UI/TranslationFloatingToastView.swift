import AppKit
import SwiftUI
import Combine
import CalmBarKit

@MainActor
public final class TranslationToastWindowController {
    public static let shared = TranslationToastWindowController()

    private var window: NSWindow?
    private var currentItem: TranslationItem?
    private var isPinned: Bool = false

    private init() {}

    public func show(item: TranslationItem) {
        self.currentItem = item

        if let existing = window, existing.isVisible {
            updateContentView(with: item)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .resizable],
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
        panel.minSize = NSSize(width: 360, height: 200)
        panel.maxSize = NSSize(width: 700, height: 600)
        panel.appearance = NSAppearance(named: .darkAqua)

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = panel
        updateContentView(with: item)

        // 智能定位：优先锚定在鼠标光标位置附近，自适应防屏幕边缘越界
        positionNearMouse(panel: panel)

        panel.makeKeyAndOrderFront(nil)
    }

    public func update(item: TranslationItem) {
        self.currentItem = item
        if let window = window, window.isVisible {
            updateContentView(with: item)
        }
    }

    public func close() {
        window?.close()
        window = nil
        isPinned = false
    }

    public func togglePin() {
        isPinned.toggle()
        if let item = currentItem {
            updateContentView(with: item)
        }
    }

    private func updateContentView(with item: TranslationItem) {
        window?.contentViewController = NSHostingController(
            rootView: TranslationFloatingToastView(
                item: item,
                isPinned: isPinned,
                onClose: { [weak self] in
                    self?.close()
                },
                onTogglePin: { [weak self] in
                    self?.togglePin()
                },
                onRetranslate: { targetLang in
                    TranslationManager.shared.translate(text: item.originalText, targetLanguage: targetLang)
                }
            )
            .environment(\.colorScheme, .dark)
        )
    }

    private func positionNearMouse(panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLocation, $0.frame) }) ?? NSScreen.main else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let width = panel.frame.width
        let height = panel.frame.height
        let margin: CGFloat = 16
        let cursorGap: CGFloat = 12

        var originX = mouseLocation.x - width / 2
        var originY = mouseLocation.y - height - cursorGap

        // 如果下方空间不足，则向上弹出
        if originY < visibleFrame.minY + margin {
            originY = mouseLocation.y + cursorGap
        }

        // X 轴约束在可见屏幕区域内
        originX = max(visibleFrame.minX + margin, min(originX, visibleFrame.maxX - width - margin))
        originY = max(visibleFrame.minY + margin, min(originY, visibleFrame.maxY - height - margin))

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

public struct TranslationFloatingToastView: View {
    let item: TranslationItem
    let isPinned: Bool
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onRetranslate: (TranslationLanguage) -> Void

    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTargetLangCode: String
    @State private var isCopied: Bool = false
    @State private var isOriginalExpanded: Bool = false
    @State private var remainingSeconds: Int
    @State private var isHovered: Bool = false

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(
        item: TranslationItem,
        isPinned: Bool,
        onClose: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onRetranslate: @escaping (TranslationLanguage) -> Void
    ) {
        self.item = item
        self.isPinned = isPinned
        self.onClose = onClose
        self.onTogglePin = onTogglePin
        self.onRetranslate = onRetranslate
        self._selectedTargetLangCode = State(initialValue: item.targetLanguage)
        let delay = Int(max(2.0, AppSettings.shared.translationAutoDismissDelay))
        self._remainingSeconds = State(initialValue: delay)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
                .background(Color.white.opacity(0.1))
            bodyScrollView
            Divider()
                .background(Color.white.opacity(0.1))
            footerBar
        }
        .frame(minWidth: 380, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(timer) { _ in
            guard settings.translationAutoDismiss,
                  !isPinned,
                  !isHovered,
                  (item.status == .completed || item.status == .failed) else {
                return
            }
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                onClose()
            }
        }
        .onChange(of: item.status) { _, newStatus in
            if newStatus == .completed || newStatus == .failed {
                remainingSeconds = Int(max(2.0, settings.translationAutoDismissDelay))
            }
        }
        .onChange(of: isPinned) { _, pinned in
            if !pinned {
                remainingSeconds = Int(max(2.0, settings.translationAutoDismissDelay))
            }
        }
    }

    private var bodyScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                originalTextSection
                translatedTextSection
                if let error = item.errorMessage, item.status == .failed {
                    errorBoxView(error: error)
                }
            }
            .padding(14)
        }
    }

    private func errorBoxView(error: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.orange.opacity(0.9))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(6)
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .foregroundColor(.blue)
                .font(.system(size: 13, weight: .semibold))

            Text("AI 翻译")
                .font(.system(size: 12, weight: .semibold))

            // Model Badge
            Text(item.model)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)

            Spacer()

            // Target Language Selector (38 Languages)
            TranslationLanguagePicker(selectedLanguageCode: $selectedTargetLangCode) { lang in
                onRetranslate(lang)
            }

            // Pin Button (去除系统默认焦点选中态)
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundColor(isPinned ? .orange : .secondary)
                    .padding(4)
                    .background(isPinned ? Color.orange.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help(isPinned ? "取消固定浮窗" : "固定浮窗（防自动关闭）")

            // Close Button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("关闭")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Original Text Section
    private var originalTextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOriginalExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isOriginalExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("原文 (\(item.originalText.count) 字)")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()

            if isOriginalExpanded {
                Text(item.originalText)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Translated Text Section
    private var translatedTextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("译文")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                if item.status == .loading || item.status == .streaming {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }

                Spacer()
            }

            if item.translatedText.isEmpty && (item.status == .loading || item.status == .idle) {
                HStack(spacing: 6) {
                    Text("AI 正在思考并翻译中...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                Text(item.translatedText)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(3)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Footer
    private var footerBar: some View {
        HStack {
            if let ms = item.latencyMs {
                Text("\(ms) ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if let tokens = item.usage?.totalTokens {
                Text("· \(tokens) tokens")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 倒计时指示器 (开启自动消失且未置顶时展示在重试按钮左侧)
            if settings.translationAutoDismiss && !isPinned && (item.status == .completed || item.status == .failed) {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text("\(max(1, remainingSeconds))s")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                }
                .foregroundColor(isHovered ? .orange : .secondary.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
                .help(isHovered ? "鼠标悬停中，倒计时已暂停" : "\(remainingSeconds) 秒后自动关闭")
                .transition(.opacity)
            }

            // Retranslate Button
            Button(action: {
                let lang = TranslationLanguage.find(byCode: selectedTargetLangCode)
                onRetranslate(lang)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("重试")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()

            // Copy Button
            Button(action: copyTranslation) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(isCopied ? "已复制" : "复制译文")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isCopied ? .green : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isCopied ? Color.green.opacity(0.2) : Color.blue)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .disabled(item.translatedText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func copyTranslation() {
        guard !item.translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.translatedText, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }
}
