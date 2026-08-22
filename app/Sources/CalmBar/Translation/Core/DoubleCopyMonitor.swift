import AppKit
import Combine

public struct ClipboardDoubleCopyDetector: Sendable {
    public var interval: TimeInterval
    private var lastText: String?
    private var lastCopyAt: TimeInterval?

    public init(interval: TimeInterval = 0.8) {
        self.interval = interval
        self.lastText = nil
        self.lastCopyAt = nil
    }

    public mutating func registerCopy(of text: String, at timestamp: TimeInterval) -> Bool {
        if let previousText = lastText,
           let previousAt = lastCopyAt,
           previousText == text,
           timestamp - previousAt <= interval {
            reset()
            return true
        }

        lastText = text
        lastCopyAt = timestamp
        return false
    }

    public mutating func reset() {
        lastText = nil
        lastCopyAt = nil
    }
}

@MainActor
public final class DoubleCopyMonitor: ObservableObject {
    public static let shared = DoubleCopyMonitor()

    private var detector = ClipboardDoubleCopyDetector(interval: 0.8)
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var keyMonitor: Any?

    public var onDoubleCopyDetected: ((String) -> Void)?

    private init() {}

    public func start(interval: TimeInterval = 0.8) {
        stop()
        detector.interval = interval
        lastChangeCount = NSPasteboard.general.changeCount

        // 1. 定期检查剪贴板 changeCount（无需特殊按键权限，通用高效）
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboardChange()
            }
        }

        // 2. 结合全局快捷键监视（当具有辅助功能权限时可加速响应）
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 8 else { return } // 8 = 'C'
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) && !flags.contains(.shift) && !flags.contains(.option) && !flags.contains(.control) {
                Task { @MainActor [weak self] in
                    // 稍作延迟等待宿主 App 将选中文本写入剪贴板
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    self?.checkPasteboardChange()
                }
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        detector.reset()
    }

    private func checkPasteboardChange() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if detector.registerCopy(of: text, at: now) {
            onDoubleCopyDetected?(text)
        }
    }
}
