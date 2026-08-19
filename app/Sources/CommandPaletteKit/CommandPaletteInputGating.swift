//
//  CommandPaletteInputGating.swift
//  CommandPaletteKit
//
//  The two "should this input count?" decisions the palette makes, lifted out of the view
//  as plain values so they can be reasoned about and tested directly. The view keeps only
//  the parts that genuinely need SwiftUI or AppKit: reading its own window, and adapting an
//  `NSEvent` into the handful of fields the decision below actually looks at.
//

import Foundation

/// Suppresses hover-driven selection for a moment after the keyboard moved the selection.
///
/// The two input paths are coupled in a way that is easy to miss. Keyboard navigation
/// changes `selectedIndex`, which scrolls the list, which translates the rows *under a
/// stationary cursor* - and SwiftUI reports that as a hover, because from its point of view
/// a new row did move under the mouse. That hover then writes `selectedIndex` straight back
/// to the row beneath the cursor. A user who holds the down arrow with the mouse resting
/// over the list - the natural position right after opening the palette with a click -
/// otherwise finds the selection yanked back on every scroll and navigation stalls.
///
/// A hover cannot be told apart from a scroll-induced one by inspecting it, so the tie is
/// broken on recency instead: for a short window after a keyboard move, hovers are assumed
/// to be the list moving rather than the mouse, and are ignored. The window is short enough
/// that deliberately moving the mouse after navigating still takes effect promptly, and key
/// auto-repeat is comfortably faster than it, so a held arrow key stays suppressed
/// throughout.
struct HoverSelectionGate: Equatable {
    /// How long after a keyboard move hovers are treated as scroll fallout. Covers the
    /// 0.1s scroll animation plus SwiftUI's delivery of the resulting hover callbacks.
    static let suppressionInterval: TimeInterval = 0.25

    /// The instant hover regains control. `.distantPast` means it never lost it.
    private var suppressedUntil: Date = .distantPast

    /// Records a keyboard-driven move, starting (or extending) the suppression window.
    mutating func keyboardDidMove(at time: Date = Date()) {
        suppressedUntil = time.addingTimeInterval(Self.suppressionInterval)
    }

    /// Whether a hover arriving at `time` should be allowed to take the selection.
    func allowsHoverSelection(at time: Date = Date()) -> Bool {
        time >= suppressedUntil
    }
}

#if os(macOS)

    /// What the palette wants done with a key-down event it has been offered.
    enum PaletteKeyResponse: Equatable {
        /// Not ours: hand the event back untouched so whatever would normally handle it
        /// still does.
        case passThrough
        /// Move the selection by this many rows and consume the event.
        case move(rows: Int)
    }

    /// The fields of an `NSEvent` the palette's decision actually depends on.
    ///
    /// A struct rather than the event itself so the decision is a pure function of values:
    /// `NSEvent` cannot be constructed meaningfully for every case worth covering, and the
    /// window identity that issue #9 turns on is not something a synthesised event carries
    /// convincingly.
    struct PaletteKeyEvent: Equatable {
        /// AppKit virtual key code. 125 is the down arrow, 126 up, 116 Page Up, 121 Page Down.
        var keyCode: UInt16
        var isControlHeld = false
        /// Whether an arrow key carries a text-navigation modifier such as Option or Command.
        var hasArrowNavigationModifiers = false
        var charactersIgnoringModifiers: String?
        /// Whether the event was posted to the window the palette is presented in.
        ///
        /// `addLocalMonitorForEvents` sees every key event posted to the *application*, not
        /// to a particular window. A palette presented as a sheet is window-modal, so other
        /// windows stay interactive and their key events pass through this monitor too;
        /// consuming those would break their key handling while silently driving the hidden
        /// palette's selection.
        var isInPaletteWindow: Bool
    }

    /// Resolves a key-down event against the palette, without touching AppKit or SwiftUI.
    ///
    /// - Parameters:
    ///   - event: the event's relevant fields.
    ///   - extendedNavigation: whether the host opted into the power-user keys. Passed in
    ///     rather than read from the environment. This runs inside an escaping monitor
    ///     closure, long after body evaluation, where SwiftUI documents an `@Environment`
    ///     read as unsupported - it may yield the default (`false`), silently disabling the
    ///     whole feature. In practice it was observed to return a *snapshot* taken when the
    ///     monitor was installed, so a host that enabled the keys later was ignored
    ///     outright. Either way the answer belongs to the caller, which reads it where it
    ///     is actually valid.
    ///   - pageStep: how many rows Page Up/Down jumps.
    func paletteKeyResponse(
        to event: PaletteKeyEvent,
        extendedNavigation: Bool,
        pageStep: Int
    ) -> PaletteKeyResponse {
        // Another window's key event. Leave it entirely alone - including the arrows, which
        // that window's own list or table almost certainly wants.
        guard event.isInPaletteWindow else { return .passThrough }

        // Modified arrows are text-navigation shortcuts owned by the focused field (for
        // example, Option-Left/Right and Command-Up/Down). Only bare arrows belong to the
        // palette; the explicit Ctrl-N/Ctrl-P shortcuts are handled separately below.
        let isArrow = event.keyCode == 125 || event.keyCode == 126
        if isArrow, event.hasArrowNavigationModifiers {
            return .passThrough
        }

        switch event.keyCode {
        case 125: return .move(rows: 1)
        case 126: return .move(rows: -1)
        default: break
        }

        // The opt-in power-user keys. When off, everything falls through untouched so
        // default behaviour is exactly as if this code were not here.
        guard extendedNavigation else { return .passThrough }

        return extendedKeyResponse(to: event, pageStep: pageStep)
    }

    /// The opt-in power-user keys, reached only once the host has enabled them and the event
    /// is known to be the palette's own.
    private func extendedKeyResponse(to event: PaletteKeyEvent, pageStep: Int) -> PaletteKeyResponse {
        // Ctrl-N/Ctrl-P share their characters with ordinary typing, so they only act with
        // Control held. This pre-empts the text field's own line motion on those chords.
        if event.isControlHeld {
            switch event.charactersIgnoringModifiers {
            case "n": return .move(rows: 1)
            case "p": return .move(rows: -1)
            default: break
            }
        }

        switch event.keyCode {
        case 116: return .move(rows: -pageStep)
        case 121: return .move(rows: pageStep)
        default: return .passThrough
        }
    }

#endif
