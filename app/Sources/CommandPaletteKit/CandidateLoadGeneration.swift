//
//  CandidateLoadGeneration.swift
//  CommandPaletteKit
//

/// Identifies the one async candidate request that may update a palette's state.
struct CandidateLoadGeneration {
    private var generation: UInt64 = 0

    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func accepts(_ token: UInt64, isCancelled: Bool = false) -> Bool {
        !isCancelled && token == generation
    }
}
