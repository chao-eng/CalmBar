//
//  PaletteFuzzyScoreTests.swift
//  CommandPaletteKit
//

import Testing
@testable import CommandPaletteKit

@Suite("paletteFuzzyScore")
struct PaletteFuzzyScoreTests {
    @Test("Empty query matches everything at a neutral score")
    func emptyQueryMatchesAll() {
        #expect(paletteFuzzyScore("", "Anything") == 0)
        #expect(paletteFuzzyScore("   ", "Anything") == 0)
        #expect(paletteFuzzyScore("\r\n", "Anything") == 0)
        #expect(paletteFuzzyScore(" \n\t\r ", "Anything") == 0)
        #expect(normalizedPaletteQuery("\r\n").isEmpty)
        #expect(normalizedPaletteQuery(" \ncommand\r ") == "command")
    }

    @Test("No common subsequence is no match")
    func noMatch() {
        #expect(paletteFuzzyScore("xyz", "New Pad") == nil)
    }

    @Test("Exact match outranks prefix outranks substring")
    func rankingOrder() throws {
        let exact = try #require(paletteFuzzyScore("new pad", "New Pad"))
        let prefix = try #require(paletteFuzzyScore("new", "New Pad"))
        let substring = try #require(paletteFuzzyScore("pad", "New Pad"))
        #expect(exact > prefix)
        #expect(prefix > substring)
    }

    @Test("Word-boundary substring beats a mid-word substring")
    func wordBoundaryBonus() throws {
        let boundary = try #require(paletteFuzzyScore("pad", "New Pad"))
        let midWord = try #require(paletteFuzzyScore("ewp", "Newpad Thing"))
        #expect(boundary > midWord)
    }

    @Test("Consecutive subsequence runs outscore scattered ones")
    func consecutiveRunsWin() throws {
        // "comm" matches four adjacent characters in "command" but is broken up in
        // "chromium", so the consecutive-run bonus should rank "command" higher.
        let consecutive = try #require(paletteFuzzyScore("comm", "command"))
        let scattered = try #require(paletteFuzzyScore("comm", "chromium"))
        #expect(consecutive > scattered)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        #expect(paletteFuzzyScore("NEW", "new pad") != nil)
    }
}
