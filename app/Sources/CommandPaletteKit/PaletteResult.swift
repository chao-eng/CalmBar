//
//  PaletteResult.swift
//  CommandPaletteKit
//
//  One row in the command palette: enough to render it plus a closure that performs its
//  action on the main actor. `id` should be unique across all candidates - namespace it
//  by category if two categories could otherwise produce the same raw id.
//

import SwiftUI

/// A single selectable entry in the palette. When candidates contain duplicate IDs, the
/// first candidate for each ID is rendered and later duplicates are ignored.
public struct PaletteResult: Identifiable {
    /// Stable, unique identity. Used for `ForEach` identity and as the scroll target, so
    /// it must stay constant as the filtered list re-orders under the selection.
    public let id: String

    /// The primary line of the row.
    public let title: String

    /// An optional secondary line shown beneath the title.
    public let subtitle: String?

    /// An optional trailing tag (e.g. "Pad", "Command"). Caller-supplied free text rather
    /// than a fixed enum, so the palette stays domain-agnostic. Pass `nil` to hide it.
    public let category: String?

    /// The leading glyph. Any `Image` - not limited to SF Symbols. Use
    /// ``init(id:title:subtitle:category:systemImage:searchText:showsOnlyWhenSearching:action:)``
    /// for the common SF Symbol case.
    public let icon: Image

    /// The text the query is scored against. Usually the title, sometimes with extra
    /// keywords folded in so a row can be found by a synonym (e.g. "Reload" by "refresh").
    public let searchText: String

    /// When `true`, the row is hidden until the user types a query, so a large category
    /// doesn't flood the empty-query list yet stays reachable by searching.
    public var showsOnlyWhenSearching: Bool

    /// Performed on the main actor when the row is activated.
    public let action: @MainActor () -> Void

    /// Designated initializer taking an arbitrary `Image` for the icon.
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: String? = nil,
        icon: Image,
        searchText: String? = nil,
        showsOnlyWhenSearching: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.icon = icon
        self.searchText = searchText ?? title
        self.showsOnlyWhenSearching = showsOnlyWhenSearching
        self.action = action
    }

    /// Convenience initializer for the common case of an SF Symbol icon.
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: String? = nil,
        systemImage: String,
        searchText: String? = nil,
        showsOnlyWhenSearching: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            icon: Image(systemName: systemImage),
            searchText: searchText,
            showsOnlyWhenSearching: showsOnlyWhenSearching,
            action: action
        )
    }
}
