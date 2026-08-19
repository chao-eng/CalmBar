//
//  CandidateLoadGenerationTests.swift
//  CommandPaletteKit
//

import Testing

@testable import CommandPaletteKit

@Suite("Async candidate load generation")
struct CandidateLoadGenerationTests {
    @Test("A newer provider supersedes an older provider")
    func outOfOrderProviders() {
        var generation = CandidateLoadGeneration()

        let older = generation.begin()
        let newer = generation.begin()

        #expect(!generation.accepts(older))
        #expect(generation.accepts(newer))
    }

    @Test("A provider that ignores task cancellation is rejected")
    func ignoredCancellation() {
        var generation = CandidateLoadGeneration()
        let token = generation.begin()

        #expect(!generation.accepts(token, isCancelled: true))
    }

    @Test("Disappearance invalidates the in-flight provider")
    func disappearance() {
        var generation = CandidateLoadGeneration()
        let token = generation.begin()
        generation.invalidate()

        #expect(!generation.accepts(token))
    }
}
