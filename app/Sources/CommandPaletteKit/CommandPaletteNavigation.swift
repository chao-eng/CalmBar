//
//  CommandPaletteNavigation.swift
//  CommandPaletteKit
//
//  Opt-in extra keyboard navigation for the palette. Off by default so the palette never
//  intercepts keys a host might want; enable it per view with
//  ``SwiftUICore/View/commandPaletteExtendedKeyboardNavigation(_:)``.
//

import SwiftUI

private struct ExtendedKeyNavigationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the palette honours the extra power-user navigation keys (`Ctrl-N`/`Ctrl-P`
    /// to move down/up and Page Up/Down to jump a viewport). Read by ``CommandPaletteView``.
    /// Defaults to `false`.
    public var commandPaletteExtendedKeyboardNavigation: Bool {
        get { self[ExtendedKeyNavigationKey.self] }
        set { self[ExtendedKeyNavigationKey.self] = newValue }
    }
}

extension View {
    /// Enables (or disables) the palette's extra keyboard navigation for this view and its
    /// descendants: Emacs-style `Ctrl-N`/`Ctrl-P` to move down/up, and Page Up/Down to move
    /// by a viewport-sized step. Off by default to avoid surprising key interception.
    public func commandPaletteExtendedKeyboardNavigation(_ enabled: Bool = true) -> some View {
        environment(\.commandPaletteExtendedKeyboardNavigation, enabled)
    }
}

func pageNavigationStep(for height: CGFloat, rowHeight: CGFloat = 36) -> Int {
    let searchFieldHeight: CGFloat = 56
    let rowSpacing: CGFloat = 2
    guard height.isFinite, height > 0 else { return 1 }

    let rowHeight = rowHeight.isFinite && rowHeight > 0 ? rowHeight : 36
    let effectiveRowHeight = rowHeight + rowSpacing
    let listHeight = max(height - searchFieldHeight, effectiveRowHeight)
    let rowsPerPage = (listHeight / effectiveRowHeight).rounded(.down)
    guard rowsPerPage < CGFloat(Int.max) else { return Int.max }

    return max(Int(rowsPerPage) - 1, 1)
}

func clampedSelectionIndex(current: Int, delta: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }

    let upperBound = count - 1
    let current = min(max(current, 0), upperBound)
    if delta > 0 {
        let remaining = upperBound - current
        return delta >= remaining ? upperBound : current + delta
    }
    return delta <= -current ? 0 : current + delta
}
