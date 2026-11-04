import AppKit
import CoreGraphics

// MARK: - 区域录制选框（BR-32：与 OCR 一致的遮罩 + 拖拽选区）

@MainActor
final class RecorderAreaSelector {
    static let shared = RecorderAreaSelector()

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var completion: ((RecorderRegion?) -> Void)?

    private init() {}

    func show(completion: @escaping (RecorderRegion?) -> Void) {
        cancel()
        self.completion = completion

        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
        self.keyMonitor = keyMonitor

        for screen in NSScreen.screens {
            let displayID = Self.displayID(of: screen)
            let window = RecorderAreaWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.sharingType = .none

            let selectionView = RecorderAreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                                          displayID: displayID)
            window.contentView = selectionView
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func complete(_ region: RecorderRegion) {
        finish(region)
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ region: RecorderRegion?) {
        guard completion != nil else { return }
        let handler = completion
        completion = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        handler?(region)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }
}

// MARK: - 可成为 key 的无边框窗口

private final class RecorderAreaWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - 选框视图

private final class RecorderAreaSelectionView: NSView {
    private let displayID: CGDirectDisplayID
    private var anchor: NSPoint?
    private var selection: CGRect = .zero

    init(frame: NSRect, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        guard selection.width > 1, selection.height > 1 else { return }

        let path = NSBezierPath(rect: selection)
        path.lineWidth = 1.5
        NSColor.systemRed.setStroke()
        path.stroke()

        let label = "\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        var origin = NSPoint(x: selection.minX, y: selection.maxY + 6)
        if origin.y + size.height > bounds.maxY {
            origin.y = max(0, selection.minY - size.height - 6)
        }
        if origin.x + size.width > bounds.maxX {
            origin.x = bounds.maxX - size.width
        }
        let background = NSRect(origin: origin, size: size).insetBy(dx: -4, dy: -2)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        label.draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let current = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil }
        guard selection.width >= 16, selection.height >= 16, let window else {
            RecorderAreaSelector.shared.cancel()
            return
        }
        let screenRect = window.convertToScreen(selection)
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screenRect.maxY
        let quartzRect = CGRect(x: screenRect.minX,
                                y: primaryHeight - screenRect.maxY,
                                width: screenRect.width,
                                height: screenRect.height)
        let displayBounds = CGDisplayBounds(displayID)
        let localRect = CGRect(x: quartzRect.minX - displayBounds.minX,
                               y: quartzRect.minY - displayBounds.minY,
                               width: quartzRect.width,
                               height: quartzRect.height)
        RecorderAreaSelector.shared.complete(.area(displayID, localRect))
    }
}
