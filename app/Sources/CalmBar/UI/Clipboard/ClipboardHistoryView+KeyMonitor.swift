import AppKit
import SwiftUI

// MARK: - ClipboardHistoryView 键盘监视器（快速复制）

// 参照 CommandPaletteKit 的成熟做法：SwiftUI 的 TextField 一旦成为 first responder，
// AppKit 的 field editor 会在 SwiftUI `.onKeyPress` 之前吞掉方向键（用于移动光标）与回车，
// 所以必须在事件层（local monitor）拦截，并只消费"属于本剪贴板窗口"的裸按键。
extension ClipboardHistoryView {

    /// 安装按键监视器（BR-17：与窗口生命周期成对；BR-18/21：幂等）。
    internal func installClipboardKeyMonitor() {
        guard clipboardKeyMonitor == nil else { return }
        clipboardKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let response = clipboardKeyResponse(
                to: ClipboardKeyEvent(
                    keyCode: event.keyCode,
                    hasTextEditModifiers: !event.modifierFlags.isDisjoint(with: [.command, .option, .shift, .control]),
                    isInClipboardWindow: isClipboardEventWindow(event.window),
                    isQuickCopyEnabled: quickCopyEnabledSnapshot,
                    isFeedbackActive: isFeedbackActive,
                    hasSelectedItem: selectedItemID != nil,
                    hasMarkedText: hasActiveMarkedText
                )
            )
            switch response {
            case .passThrough:
                return event
            case .moveUp:
                moveSelection(by: -1)
                return nil
            case .moveDown:
                moveSelection(by: 1)
                return nil
            case .cycleTab(let direction):
                cycleFilter(direction: direction)
                return nil
            case .quickCopy:
                performQuickCopy()
                return nil
            case .dismiss:
                dismissClipboardWindow()
                return nil
            }
        }
    }

    /// 卸载按键监视器（BR-17，与 install 成对；BR-18 幂等）。
    internal func removeClipboardKeyMonitor() {
        if let monitor = clipboardKeyMonitor {
            NSEvent.removeMonitor(monitor)
            clipboardKeyMonitor = nil
        }
    }

    /// 事件是否属于剪贴板窗口：同 App 其它窗口（设置、面板等）的按键一律放行（BR-10）。
    private func isClipboardEventWindow(_ window: NSWindow?) -> Bool {
        guard let clipboardWindow, let window else { return false }
        return window === clipboardWindow
    }

    /// 当前 first responder 是否有输入法组词（marked text，BR-12b）。
    /// 组词进行中按回车应由输入法上屏候选，快速复制不得消费。
    internal var hasActiveMarkedText: Bool {
        guard let fieldEditor = clipboardWindow?.firstResponder as? NSTextView else { return false }
        return fieldEditor.hasMarkedText()
    }

    internal func refreshQuickCopyEnabledSnapshot() {
        quickCopyEnabledSnapshot = AppSettings.shared.clipboardHistoryEnabled
            && AppSettings.shared.clipboardQuickCopyEnabled
        if !quickCopyEnabledSnapshot {
            selectedItemID = nil
        }
    }
}

/// 报告剪贴板窗口身份。`SwiftUI` 无直接途径查询所在 `NSWindow`；用零尺寸 backing view 上报。
struct ClipboardWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ClipboardWindowReportingView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClipboardWindowReportingView)?.onResolve = onResolve
    }

    final class ClipboardWindowReportingView: NSView {
        var onResolve: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            let onResolve = onResolve
            DispatchQueue.main.async { onResolve?(window) }
        }
    }
}

/// 键盘动作：放行 / 上下移动 / 切 Tab / 快速复制 / Esc 关闭。
enum ClipboardKeyResponse: Equatable {
    case passThrough
    case moveUp
    case moveDown
    case cycleTab(direction: Int)
    case quickCopy
    case dismiss
}

/// 决定结果所依赖的事件字段（纯值，便于单测）。
struct ClipboardKeyEvent: Equatable {
    var keyCode: UInt16
    var hasTextEditModifiers: Bool
    var isInClipboardWindow: Bool
    var isQuickCopyEnabled: Bool
    var isFeedbackActive: Bool
    var hasSelectedItem: Bool
    var hasMarkedText: Bool
}

/// 把一次 keyDown 解析为剪贴板的键盘动作（无 AppKit/SwiftUI 依赖的纯函数，可单测）。
func clipboardKeyResponse(to event: ClipboardKeyEvent) -> ClipboardKeyResponse {
    // 非本窗口事件一律放行（设置窗口等自己的方向键不能被吃）。
    guard event.isInClipboardWindow else { return .passThrough }
    // 快速复制关闭：不消费任何按键（BR-02/16a），方向键/回车回到文本域默认。
    guard event.isQuickCopyEnabled else { return .passThrough }

    // Esc：仅无修饰键时关闭窗口（BR-11a）。
    if event.keyCode == 53 {
        return event.hasTextEditModifiers ? .passThrough : .dismiss
    }
    // 修饰键放行（BR-10）：Option/⌘/Shift 方向键是文本导航（跳词/选区），属于输入框。
    if event.hasTextEditModifiers {
        return .passThrough
    }
    // 中文输入法组词中（BR-12b）：回车由输入法上屏候选，快速复制放行。
    if event.hasMarkedText {
        return .passThrough
    }
    // 反馈进行中（0.5s 内）：忽略除 Esc 外的一切按键（BR-23）。
    if event.isFeedbackActive {
        return .passThrough
    }

    switch event.keyCode {
    case 126: return .moveUp          // ↑
    case 125: return .moveDown        // ↓
    case 123: return .cycleTab(direction: -1)  // ←
    case 124: return .cycleTab(direction: 1)   // →
    case 36, 76:                       // Return / keypad Enter
        return event.hasSelectedItem ? .quickCopy : .passThrough
    default:
        return .passThrough
    }
}
