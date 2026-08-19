//
//  CommandPaletteView+CandidateLoading.swift
//  CommandPaletteKit
//

import SwiftUI

extension CommandPaletteView {
    func beginCandidateLoad() -> UInt64 {
        var generation = candidateLoadGeneration
        let token = generation.begin()
        candidateLoadGeneration = generation
        return token
    }

    func invalidateCandidateLoads() {
        var generation = candidateLoadGeneration
        generation.invalidate()
        candidateLoadGeneration = generation
    }
}
