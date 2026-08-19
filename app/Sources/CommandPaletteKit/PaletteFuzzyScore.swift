//
//  PaletteFuzzyScore.swift
//  CommandPaletteKit
//
//  A self-contained fuzzy scorer - no dependency, no index. Higher is better; `nil`
//  means no match. An empty query matches everything at a neutral score so the full
//  candidate list shows. Exact and prefix matches rank highest, then substring (with a
//  word-boundary bonus), then a fuzzy subsequence match that rewards consecutive runs.
//

import Foundation

/// Scores how well `query` matches `text`. Returns `nil` when there is no match, `0` for
/// an empty query (so an unfiltered list shows), and a positive score otherwise where a
/// larger value is a better match.
///
/// This is the default scorer used by ``CommandPaletteView``; pass your own
/// ``PaletteScorer`` to the view to add weighting, recency, or pinning.
public func paletteFuzzyScore(_ query: String, _ text: String) -> Int? {
    let trimmed = normalizedPaletteQuery(query)
    guard !trimmed.isEmpty else { return 0 }

    let haystack = text.lowercased()
    let needle = trimmed.lowercased()

    if haystack == needle { return 1000 }
    if haystack.hasPrefix(needle) { return 850 }

    if let range = haystack.range(of: needle) {
        let start = range.lowerBound
        let atWordStart = start == haystack.startIndex
            || !haystack[haystack.index(before: start)].isLetter
            && !haystack[haystack.index(before: start)].isNumber
        let offset = haystack.distance(from: haystack.startIndex, to: start)
        return (atWordStart ? 650 : 450) - min(offset, 100)
    }

    // Subsequence match: every character of the needle appears in order. Consecutive
    // matches score progressively higher so "npd" prefers "NewPaD" over scattered hits.
    var score = 0
    var consecutive = 0
    var index = haystack.startIndex
    for character in needle {
        var matched = false
        while index < haystack.endIndex {
            let current = haystack[index]
            index = haystack.index(after: index)
            if current == character {
                matched = true
                consecutive += 1
                score += 8 + consecutive
                break
            }
            consecutive = 0
        }
        if !matched { return nil }
    }
    return score
}

func normalizedPaletteQuery(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A function that scores a `query` against a candidate's search text. Return `nil` to
/// exclude the candidate, or a score where higher ranks closer to the top.
public typealias PaletteScorer = @Sendable (_ query: String, _ text: String) -> Int?
