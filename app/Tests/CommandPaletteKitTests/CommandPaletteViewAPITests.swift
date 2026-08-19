//
//  CommandPaletteViewAPITests.swift
//  CommandPaletteKit
//
//  Compile-time coverage of the public initializers: the sync and async candidate
//  providers, each with the built-in row and a custom row builder, must all resolve
//  unambiguously from a bare call site. Constructing a view does not run its `body`,
//  so these exercise the API surface without needing a host.
//

import SwiftUI
import Testing

@testable import CommandPaletteKit

@MainActor
@Suite("CommandPaletteView initializers")
struct CommandPaletteViewAPITests {
    private static func sampleResults() -> [PaletteResult] {
        [PaletteResult(id: "a", title: "Alpha", systemImage: "a.circle") {}]
    }

    @Test("Synchronous provider with the built-in row resolves")
    func syncDefaultRow() {
        _ = CommandPaletteView { Self.sampleResults() }
    }

    @Test("Asynchronous provider with the built-in row resolves")
    func asyncDefaultRow() {
        _ = CommandPaletteView(candidates: { () async in Self.sampleResults() })
    }

    @Test("Synchronous provider with a custom row resolves")
    func syncCustomRow() {
        _ = CommandPaletteView(
            candidates: { Self.sampleResults() },
            row: { result, isSelected in Text(result.title).bold(isSelected) }
        )
    }

    @Test("Asynchronous provider with a custom row resolves")
    func asyncCustomRow() {
        _ = CommandPaletteView(
            candidates: { () async in Self.sampleResults() },
            row: { result, isSelected in Text(result.title).bold(isSelected) }
        )
    }

    @Test("Result limits are normalized before reaching Collection.prefix")
    func resultLimitNormalization() {
        #expect(normalizedResultLimit(-1) == 0)
        #expect(normalizedResultLimit(Int.min) == 0)
        #expect(normalizedResultLimit(0) == 0)
        #expect(normalizedResultLimit(Int.max) == Int.max)

        let values = [1, 2, 3]
        #expect(Array(values.prefix(normalizedResultLimit(-1))).isEmpty)
        #expect(Array(values.prefix(normalizedResultLimit(Int.max))) == values)
    }

    @Test("Palette geometry is finite, positive, and bounded before layout")
    func paletteGeometryNormalization() {
        let fallback: CGFloat = 620
        for invalid in [CGFloat.nan, .infinity, -.infinity, -1, 0] {
            #expect(normalizedPaletteDimension(invalid, fallback: fallback) == fallback)
        }

        #expect(normalizedPaletteDimension(320, fallback: fallback) == 320)
        #expect(
            normalizedPaletteDimension(.greatestFiniteMagnitude, fallback: fallback)
                == maximumPaletteDimension
        )
    }

    @Test("The first result for a duplicate ID is rendered and activated")
    func duplicateResultIDs() {
        var activatedTitle: String?
        let candidates = [
            PaletteResult(id: "duplicate", title: "First", systemImage: "1.circle") {
                activatedTitle = "First"
            },
            PaletteResult(id: "unique", title: "Unique", systemImage: "u.circle") {},
            PaletteResult(id: "duplicate", title: "Second", systemImage: "2.circle") {
                activatedTitle = "Second"
            }
        ]

        let results = deduplicatedPaletteResults(candidates)
        #expect(results.map(\.id) == ["duplicate", "unique"])
        #expect(results.map(\.title) == ["First", "Unique"])

        results[0].action()
        #expect(activatedTitle == "First")
    }
}
