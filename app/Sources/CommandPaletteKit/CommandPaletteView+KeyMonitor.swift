//
//  CommandPaletteView+KeyMonitor.swift
//  CommandPaletteKit
//
//  The macOS key-event monitor and the window lookup it depends on. AppKit's field editor
//  swallows the arrow keys for caret movement before SwiftUI's `.onKeyPress` sees them, so
//  the palette watches for them at the event level instead - which means seeing the whole
//  application's key events and being careful to act only on its own.
//

#if os(macOS)

    import AppKit
    import SwiftUI

    extension CommandPaletteView {
        // Watches key-down events while the palette is open and moves the selection on the
        // up/down arrows, consuming them so the focused field doesn't also move its caret.
        // `keyCode` 125 is the down arrow, 126 the up arrow.
        func installArrowKeyMonitor() {
            guard arrowKeyMonitor == nil else { return }

            arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Everything that decides the outcome lives in `paletteKeyResponse`; this
                // closure only adapts the event and applies the answer. `@State` reads are
                // fine here (the property wrapper's storage outlives this view value),
                // unlike the `@Environment` read this replaced.
                let response = paletteKeyResponse(
                    to: PaletteKeyEvent(
                        keyCode: event.keyCode,
                        isControlHeld: event.modifierFlags.contains(.control),
                        hasArrowNavigationModifiers: !event.modifierFlags.isDisjoint(
                            with: [.command, .option, .shift, .control]
                        ),
                        charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                        // A local monitor sees the whole application's key events, so an
                        // event from any other window - a second document window alongside a
                        // window-modal sheet, say - must be handed straight back.
                        isInPaletteWindow: isPaletteWindow(event.window)
                    ),
                    extendedNavigation: extendedNavigationEnabled,
                    pageStep: pageStep
                )
                switch response {
                case .passThrough: return event
                case .move(let delta): move(by: delta); return nil
                }
            }
        }

        // Until the palette's window is known, claim nothing: consuming another window's
        // arrow keys is a far worse failure than briefly not handling our own, and the
        // window is resolved as soon as the backing view lands in the hierarchy.
        private func isPaletteWindow(_ window: NSWindow?) -> Bool {
            guard let paletteWindow, let window else { return false }

            return window === paletteWindow
        }

        func removeArrowKeyMonitor() {
            if let monitor = arrowKeyMonitor {
                NSEvent.removeMonitor(monitor)
                arrowKeyMonitor = nil
            }
        }
    }

    /// Reports the `NSWindow` the palette is presented in, once its backing view lands in
    /// the hierarchy.
    ///
    /// SwiftUI has no way to ask "which window am I in?", and the alternatives are wrong in
    /// exactly the case that matters: `NSApp.keyWindow` is whichever window has focus, which
    /// for a window-modal sheet may well be a *different* window - the one whose keys the
    /// palette must not be eating. A zero-size backing view answers the question honestly.
    struct WindowReader: NSViewRepresentable {
        let onResolve: (NSWindow?) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = WindowReportingView()
            view.onResolve = onResolve
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? WindowReportingView)?.onResolve = onResolve
        }

        final class WindowReportingView: NSView {
            var onResolve: ((NSWindow?) -> Void)?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                // Deferred: `viewDidMoveToWindow` runs inside a view update, and writing
                // SwiftUI state from there warns about modifying state during an update.
                let window = window
                let onResolve = onResolve
                DispatchQueue.main.async { onResolve?(window) }
            }
        }
    }

#endif
