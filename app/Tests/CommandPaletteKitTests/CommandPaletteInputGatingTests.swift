//
//  CommandPaletteInputGatingTests.swift
//  CommandPaletteKit
//
//  Covers the two input-gating decisions directly. Both were previously tangled into
//  SwiftUI/AppKit callbacks and reachable only from a running GUI; as plain values they are
//  ordinary to test. What these do *not* cover is the wiring - that the view hands the
//  monitor its own window and routes `move(by:)` through the hover gate - which was checked
//  by driving a real windowed host with synthesised `NSEvent`s.
//

import Foundation
import Testing

@testable import CommandPaletteKit

@Suite("Hover selection gate")
struct HoverSelectionGateTests {
    @Test("Hover selects when the keyboard hasn't been used")
    func idleGateAllowsHover() {
        let gate = HoverSelectionGate()
        #expect(gate.allowsHoverSelection(at: Date()))
    }

    @Test("Hover is ignored immediately after a keyboard move")
    func keyboardMoveSuppressesHover() {
        // The scroll that a keyboard move kicks off slides rows under a stationary cursor,
        // and SwiftUI reports that as a hover. Honouring it would write the selection back
        // to the row under the mouse and stall navigation.
        var gate = HoverSelectionGate()
        let moment = Date()
        gate.keyboardDidMove(at: moment)
        #expect(gate.allowsHoverSelection(at: moment) == false)
        #expect(gate.allowsHoverSelection(at: moment.addingTimeInterval(0.1)) == false)
    }

    @Test("Hover regains control once the scroll has settled")
    func suppressionExpires() {
        // Deliberately moving the mouse after navigating must still select promptly.
        var gate = HoverSelectionGate()
        let moment = Date()
        gate.keyboardDidMove(at: moment)
        let after = moment.addingTimeInterval(HoverSelectionGate.suppressionInterval + 0.01)
        #expect(gate.allowsHoverSelection(at: after))
    }

    @Test("A held arrow key keeps hover suppressed throughout")
    func repeatedMovesExtendSuppression() {
        // Key auto-repeat is faster than the suppression window, so each move pushes the
        // window out and the selection is never yanked back mid-run.
        var gate = HoverSelectionGate()
        var now = Date()
        gate.keyboardDidMove(at: now)
        for _ in 0 ..< 10 {
            now = now.addingTimeInterval(0.05)
            #expect(gate.allowsHoverSelection(at: now) == false)
            gate.keyboardDidMove(at: now)
        }
        #expect(gate.allowsHoverSelection(at: now.addingTimeInterval(0.1)) == false)
    }

    @Test("The suppression window is shorter than a deliberate mouse move")
    func suppressionIsBrief() {
        // Long enough to outlast the 0.1s scroll animation, short enough that the mouse
        // never feels unresponsive.
        #expect(HoverSelectionGate.suppressionInterval > 0.1)
        #expect(HoverSelectionGate.suppressionInterval < 0.5)
    }
}

#if os(macOS)

    @Suite("Palette key response")
    struct PaletteKeyResponseTests {
        private static let pageStep = 12

        private func response(
            _ event: PaletteKeyEvent,
            extendedNavigation: Bool = false
        ) -> PaletteKeyResponse {
            paletteKeyResponse(to: event,
                               extendedNavigation: extendedNavigation,
                               pageStep: Self.pageStep)
        }

        private func arrow(_ keyCode: UInt16, inPaletteWindow: Bool) -> PaletteKeyEvent {
            PaletteKeyEvent(keyCode: keyCode, isInPaletteWindow: inPaletteWindow)
        }

        @Test("The arrows move the selection in the palette's own window")
        func arrowsMoveSelection() {
            #expect(response(arrow(125, inPaletteWindow: true)) == .move(rows: 1))
            #expect(response(arrow(126, inPaletteWindow: true)) == .move(rows: -1))
        }

        @Test("Modified arrows remain available to the focused text field")
        func modifiedArrowsPassThrough() {
            for keyCode: UInt16 in [125, 126] {
                let modifiedArrow = PaletteKeyEvent(
                    keyCode: keyCode,
                    hasArrowNavigationModifiers: true,
                    isInPaletteWindow: true
                )
                #expect(response(modifiedArrow) == .passThrough)
                #expect(response(modifiedArrow, extendedNavigation: true) == .passThrough)
            }
        }

        @Test("Another window's arrows are left entirely alone")
        func arrowsFromAnotherWindowPassThrough() {
            // Issue #9: a local monitor sees the whole application's key events. A palette
            // presented as a window-modal sheet leaves other windows interactive, and
            // consuming their arrows broke their key handling while silently driving the
            // hidden palette's selection.
            #expect(response(arrow(125, inPaletteWindow: false)) == .passThrough)
            #expect(response(arrow(126, inPaletteWindow: false)) == .passThrough)
        }

        @Test("Extended keys do nothing until the host opts in")
        func extendedKeysAreOptIn() {
            let controlN = PaletteKeyEvent(keyCode: 45, isControlHeld: true,
                                           charactersIgnoringModifiers: "n",
                                           isInPaletteWindow: true)
            #expect(response(controlN) == .passThrough)
            #expect(response(PaletteKeyEvent(keyCode: 121, isInPaletteWindow: true)) == .passThrough)
        }

        @Test("Ctrl-N and Ctrl-P move the selection when enabled")
        func controlNavigation() {
            let controlN = PaletteKeyEvent(keyCode: 45, isControlHeld: true,
                                           charactersIgnoringModifiers: "n",
                                           isInPaletteWindow: true)
            let controlP = PaletteKeyEvent(keyCode: 35, isControlHeld: true,
                                           charactersIgnoringModifiers: "p",
                                           isInPaletteWindow: true)
            #expect(response(controlN, extendedNavigation: true) == .move(rows: 1))
            #expect(response(controlP, extendedNavigation: true) == .move(rows: -1))
        }

        @Test("Typing n or p without Control is ordinary text")
        func plainCharactersAreNotIntercepted() {
            let plainN = PaletteKeyEvent(keyCode: 45, isControlHeld: false,
                                         charactersIgnoringModifiers: "n",
                                         isInPaletteWindow: true)
            #expect(response(plainN, extendedNavigation: true) == .passThrough)
        }

        @Test("Page Up and Page Down jump a viewport when enabled")
        func pageNavigation() {
            let pageUp = PaletteKeyEvent(keyCode: 116, isInPaletteWindow: true)
            let pageDown = PaletteKeyEvent(keyCode: 121, isInPaletteWindow: true)
            #expect(response(pageUp, extendedNavigation: true) == .move(rows: -Self.pageStep))
            #expect(response(pageDown, extendedNavigation: true) == .move(rows: Self.pageStep))
        }

        @Test("Another window's extended keys are left alone too")
        func extendedKeysFromAnotherWindowPassThrough() {
            let controlN = PaletteKeyEvent(keyCode: 45, isControlHeld: true,
                                           charactersIgnoringModifiers: "n",
                                           isInPaletteWindow: false)
            let pageDown = PaletteKeyEvent(keyCode: 121, isInPaletteWindow: false)
            #expect(response(controlN, extendedNavigation: true) == .passThrough)
            #expect(response(pageDown, extendedNavigation: true) == .passThrough)
        }

        @Test("Unrelated keys are never consumed")
        func unrelatedKeysPassThrough() {
            // Typing has to reach the search field; the monitor must claim only what it
            // actually handles.
            let letter = PaletteKeyEvent(keyCode: 0, charactersIgnoringModifiers: "a",
                                         isInPaletteWindow: true)
            #expect(response(letter) == .passThrough)
            #expect(response(letter, extendedNavigation: true) == .passThrough)
        }
    }

#endif
