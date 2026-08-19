//
//  CommandPaletteView+ResultSnapshot.swift
//  CommandPaletteKit
//

import SwiftUI

extension CommandPaletteView {
    func refreshResultSnapshot(candidates newCandidates: [PaletteResult]? = nil) {
        var snapshot = resultSnapshot
        snapshot.refresh(
            candidates: newCandidates ?? candidates,
            query: query,
            limit: resultLimit,
            scorer: scorer
        )
        resultSnapshot = snapshot
    }
}
