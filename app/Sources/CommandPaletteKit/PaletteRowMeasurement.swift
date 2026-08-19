//
//  PaletteRowMeasurement.swift
//  CommandPaletteKit
//

import SwiftUI

struct PaletteRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

func representativePaletteRowHeight(_ heights: [CGFloat], fallback: CGFloat = 36) -> CGFloat {
    let validHeights = heights.filter { $0.isFinite && $0 > 0 }
    guard !validHeights.isEmpty else { return fallback }

    return validHeights.reduce(0, +) / CGFloat(validHeights.count)
}
