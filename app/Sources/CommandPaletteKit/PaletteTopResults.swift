//
//  PaletteTopResults.swift
//  CommandPaletteKit
//

import Foundation

struct ScoredPaletteResult {
    let result: PaletteResult
    let score: Int
    let sourceIndex: Int
}

/// Retains only the best `limit` results while candidates are scored.
///
/// The root is the worst retained entry, so a better candidate replaces it in O(log N).
/// Final sorting touches at most `limit` entries instead of the complete candidate catalog.
struct BoundedPaletteResultHeap {
    let limit: Int
    private(set) var entries: [ScoredPaletteResult] = []

    var retainedCount: Int { entries.count }

    mutating func insert(_ entry: ScoredPaletteResult) {
        guard limit > 0 else { return }

        if entries.count < limit {
            entries.append(entry)
            siftUp(from: entries.count - 1)
        } else if let worst = entries.first, isBetter(entry, than: worst) {
            entries[0] = entry
            siftDown(from: 0)
        }
    }

    func sortedResults() -> [PaletteResult] {
        entries.sorted(by: isBetter).map(\.result)
    }

    private mutating func siftUp(from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard isWorse(entries[child], than: entries[parent]) else { return }

            entries.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < entries.count else { return }

            let right = left + 1
            let worseChild = right < entries.count && isWorse(entries[right], than: entries[left])
                ? right
                : left
            guard isWorse(entries[worseChild], than: entries[parent]) else { return }

            entries.swapAt(parent, worseChild)
            parent = worseChild
        }
    }

    private func isBetter(_ lhs: ScoredPaletteResult, than rhs: ScoredPaletteResult) -> Bool {
        lhs.score != rhs.score ? lhs.score > rhs.score : lhs.sourceIndex < rhs.sourceIndex
    }

    private func isWorse(_ lhs: ScoredPaletteResult, than rhs: ScoredPaletteResult) -> Bool {
        isBetter(rhs, than: lhs)
    }
}

func topPaletteResults(
    candidates: [PaletteResult],
    query: String,
    limit: Int,
    scorer: PaletteScorer
) -> [PaletteResult] {
    guard limit > 0 else { return [] }

    let searching = !normalizedPaletteQuery(query).isEmpty
    var heap = BoundedPaletteResultHeap(limit: limit)
    for (sourceIndex, result) in deduplicatedPaletteResults(candidates).enumerated() {
        guard searching || !result.showsOnlyWhenSearching else { continue }
        guard let score = scorer(query, result.searchText) else { continue }

        heap.insert(ScoredPaletteResult(result: result, score: score, sourceIndex: sourceIndex))
    }
    return heap.sortedResults()
}

/// One materialized ranking shared by rendering, navigation, scrolling, and activation.
struct PaletteResultSnapshot {
    private(set) var results: [PaletteResult] = []

    mutating func refresh(
        candidates: [PaletteResult],
        query: String,
        limit: Int,
        scorer: PaletteScorer
    ) {
        results = topPaletteResults(candidates: candidates, query: query, limit: limit, scorer: scorer)
    }

    func result(at index: Int) -> PaletteResult? {
        results.indices.contains(index) ? results[index] : nil
    }
}
