//
//  CommandPaletteNavigationTests.swift
//  CommandPaletteKit
//
//  Covers the viewport-sized Page Up/Down step. The key interception itself is exercised
//  on a device; here we lock down the page-size math derived from the surface height.
//

import SwiftUI
import Testing

@testable import CommandPaletteKit

@MainActor
@Suite("Page navigation step")
struct CommandPaletteNavigationTests {
    private func palette(height: CGFloat) -> CommandPaletteView<PaletteRow> {
        CommandPaletteView(height: height) { [] }
    }

    @Test("A taller surface pages by more rows")
    func tallerPagesFurther() {
        #expect(palette(height: 800).pageStep > palette(height: 300).pageStep)
    }

    @Test("The page step is always at least one row")
    func neverLessThanOne() {
        #expect(palette(height: 1).pageStep >= 1)
        #expect(palette(height: 0).pageStep >= 1)
    }

    @Test("A default-height surface pages by several rows")
    func defaultHeightPagesAPage() {
        // The default 460pt surface should jump well more than a single row but stay within
        // a sane bound, so Page Up/Down feels like a page rather than a nudge or a full jump.
        let step = palette(height: 460).pageStep
        #expect(step >= 5)
        #expect(step <= 20)
    }

    @Test("Custom row heights change the viewport-sized step")
    func customRowHeights() {
        let compactRows = pageNavigationStep(for: 460, rowHeight: 18)
        let defaultRows = pageNavigationStep(for: 460, rowHeight: 36)
        let tallRows = pageNavigationStep(for: 460, rowHeight: 96)

        #expect(compactRows > defaultRows)
        #expect(defaultRows > tallRows)
        #expect(tallRows >= 1)
    }

    @Test("Realized row measurements use their average height")
    func representativeHeight() {
        #expect(representativePaletteRowHeight([20, 40, 60]) == 40)
        #expect(representativePaletteRowHeight([.nan, 0, -1]) == 36)
        #expect(representativePaletteRowHeight([20, .infinity, 40]) == 30)
    }

    @Test("Invalid and oversized heights never trap during page-step calculation")
    func pathologicalHeightsAreSafe() {
        for height in [CGFloat.nan, .infinity, -.infinity, -1, 0] {
            #expect(pageNavigationStep(for: height) == 1)
        }
        #expect(pageNavigationStep(for: .greatestFiniteMagnitude) == Int.max)
    }

    @Test("Extreme page deltas clamp without overflowing selection arithmetic")
    func extremeDeltasClamp() {
        #expect(clampedSelectionIndex(current: 5, delta: Int.max, count: 10) == 9)
        #expect(clampedSelectionIndex(current: 5, delta: Int.min, count: 10) == 0)
        #expect(clampedSelectionIndex(current: 5, delta: 2, count: 10) == 7)
        #expect(clampedSelectionIndex(current: 5, delta: -2, count: 10) == 3)
    }
}
