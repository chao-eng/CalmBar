//
//  CommandPaletteView+Initializers.swift
//  CommandPaletteKit
//
//  The public initializers for ``CommandPaletteView``. Each funnels into the internal
//  designated initializer in CommandPaletteView.swift. There are two axes:
//
//  - Candidate source: synchronous (built on appear) or `async` (awaited, with a loading
//    affordance). The synchronous form keeps the original behaviour and call site.
//  - Row content: a custom `@ViewBuilder row:` for any `RowContent`, or - via the
//    `RowContent == PaletteRow` extension - the built-in cell with no `row:` argument.
//

import SwiftUI

extension CommandPaletteView {
    /// Creates a palette whose candidates are built synchronously on the main actor.
    ///
    /// - Parameters:
    ///   - placeholder: Prompt shown in the empty search field.
    ///   - emptyMessage: Shown when the query is empty and nothing is listed yet.
    ///   - noMatchesMessage: Shown when a non-empty query matches nothing.
    ///   - resultLimit: Maximum rows rendered; the highest-scoring win. Zero or negative
    ///     values render no rows; pass `.max` for no limit.
    ///   - scorer: Match/scoring function. Defaults to ``paletteFuzzyScore(_:_:)``.
    ///   - width: Surface width. Invalid values use the 620-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - height: Surface height. Invalid values use the 460-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - onActivate: Called instead of `result.action` when a row is activated, if
    ///     provided - lets the host route activation itself. When `nil`, the palette
    ///     dismisses and calls `result.action`.
    ///   - candidates: Builds the candidate list. Evaluated on appear (and on the main actor).
    ///   - row: Builds the content for each row from its ``PaletteResult`` and whether it
    ///     is the current selection. Selection, hover, scroll-to, and accessibility wiring
    ///     stay with the container, so a custom row only supplies the cell's appearance.
    ///     Omit it (via the ``PaletteRow`` convenience initializer) for the built-in cell.
    public init(
        placeholder: LocalizedStringKey = "Search…",
        emptyMessage: LocalizedStringKey = "Start typing to search.",
        noMatchesMessage: LocalizedStringKey = "No matches.",
        resultLimit: Int = 40,
        scorer: @escaping PaletteScorer = paletteFuzzyScore,
        width: CGFloat = 620,
        height: CGFloat = 460,
        onActivate: (@MainActor (PaletteResult) -> Void)? = nil,
        candidates: @escaping @MainActor () -> [PaletteResult],
        @ViewBuilder row: @escaping (PaletteResult, Bool) -> RowContent
    ) {
        self.init(
            source: .sync(candidates),
            placeholder: placeholder,
            emptyMessage: emptyMessage,
            noMatchesMessage: noMatchesMessage,
            loadingMessage: "Loading…",
            resultLimit: resultLimit,
            scorer: scorer,
            width: width,
            height: height,
            onActivate: onActivate,
            row: row
        )
    }

    /// Creates a palette whose candidates are produced by an `async` provider, showing a
    /// loading affordance until it resolves. Presentation is never blocked: the palette
    /// appears immediately and fills in once the provider returns.
    ///
    /// - Parameters:
    ///   - placeholder: Prompt shown in the empty search field.
    ///   - emptyMessage: Shown when the query is empty and nothing is listed yet.
    ///   - noMatchesMessage: Shown when a non-empty query matches nothing.
    ///   - loadingMessage: Label shown beside the spinner while the provider resolves.
    ///   - resultLimit: Maximum rows rendered; the highest-scoring win. Zero or negative
    ///     values render no rows; pass `.max` for no limit.
    ///   - scorer: Match/scoring function. Defaults to ``paletteFuzzyScore(_:_:)``.
    ///   - width: Surface width. Invalid values use the 620-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - height: Surface height. Invalid values use the 460-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - onActivate: Called instead of `result.action` when a row is activated, if
    ///     provided - lets the host route activation itself. When `nil`, the palette
    ///     dismisses and calls `result.action`.
    ///   - candidates: Asynchronously builds the candidate list, on the main actor.
    ///   - row: Builds the content for each row from its ``PaletteResult`` and whether it
    ///     is the current selection. Selection, hover, scroll-to, and accessibility wiring
    ///     stay with the container, so a custom row only supplies the cell's appearance.
    ///     Omit it (via the ``PaletteRow`` convenience initializer) for the built-in cell.
    public init(
        placeholder: LocalizedStringKey = "Search…",
        emptyMessage: LocalizedStringKey = "Start typing to search.",
        noMatchesMessage: LocalizedStringKey = "No matches.",
        loadingMessage: LocalizedStringKey = "Loading…",
        resultLimit: Int = 40,
        scorer: @escaping PaletteScorer = paletteFuzzyScore,
        width: CGFloat = 620,
        height: CGFloat = 460,
        onActivate: (@MainActor (PaletteResult) -> Void)? = nil,
        candidates: @escaping @MainActor () async -> [PaletteResult],
        @ViewBuilder row: @escaping (PaletteResult, Bool) -> RowContent
    ) {
        self.init(
            source: .async(candidates),
            placeholder: placeholder,
            emptyMessage: emptyMessage,
            noMatchesMessage: noMatchesMessage,
            loadingMessage: loadingMessage,
            resultLimit: resultLimit,
            scorer: scorer,
            width: width,
            height: height,
            onActivate: onActivate,
            row: row
        )
    }
}

/// A non-positive limit deliberately renders no result rows. Keeping normalization at
/// the designated initializer prevents a negative value reaching `Collection.prefix`,
/// which requires a nonnegative length.
func normalizedResultLimit(_ resultLimit: Int) -> Int {
    max(0, resultLimit)
}

extension CommandPaletteView where RowContent == PaletteRow {
    /// Creates a palette using the built-in ``PaletteRow`` for each cell. This is the
    /// zero-configuration call site; supply a `row` builder on the designated initializer
    /// to replace the cell content.
    ///
    /// - Parameters:
    ///   - placeholder: Prompt shown in the empty search field.
    ///   - emptyMessage: Shown when the query is empty and nothing is listed yet.
    ///   - noMatchesMessage: Shown when a non-empty query matches nothing.
    ///   - resultLimit: Maximum rows rendered; the highest-scoring win. Zero or negative
    ///     values render no rows; pass `.max` for no limit.
    ///   - scorer: Match/scoring function. Defaults to ``paletteFuzzyScore(_:_:)``.
    ///   - width: Surface width. Invalid values use the 620-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - height: Surface height. Invalid values use the 460-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - onActivate: Called instead of `result.action` when a row is activated, if
    ///     provided - lets the host route activation itself. When `nil`, the palette
    ///     dismisses and calls `result.action`.
    ///   - candidates: Builds the candidate list. Evaluated on appear (and on the main actor).
    public init(
        placeholder: LocalizedStringKey = "Search…",
        emptyMessage: LocalizedStringKey = "Start typing to search.",
        noMatchesMessage: LocalizedStringKey = "No matches.",
        resultLimit: Int = 40,
        scorer: @escaping PaletteScorer = paletteFuzzyScore,
        width: CGFloat = 620,
        height: CGFloat = 460,
        onActivate: (@MainActor (PaletteResult) -> Void)? = nil,
        candidates: @escaping @MainActor () -> [PaletteResult]
    ) {
        self.init(
            placeholder: placeholder,
            emptyMessage: emptyMessage,
            noMatchesMessage: noMatchesMessage,
            resultLimit: resultLimit,
            scorer: scorer,
            width: width,
            height: height,
            onActivate: onActivate,
            candidates: candidates,
            row: { result, isSelected in PaletteRow(result: result, isSelected: isSelected) }
        )
    }

    /// Creates a palette using the built-in ``PaletteRow`` for each cell, with candidates
    /// produced by an `async` provider. A loading affordance shows until it resolves.
    ///
    /// - Parameters:
    ///   - placeholder: Prompt shown in the empty search field.
    ///   - emptyMessage: Shown when the query is empty and nothing is listed yet.
    ///   - noMatchesMessage: Shown when a non-empty query matches nothing.
    ///   - loadingMessage: Label shown beside the spinner while the provider resolves.
    ///   - resultLimit: Maximum rows rendered; the highest-scoring win. Zero or negative
    ///     values render no rows; pass `.max` for no limit.
    ///   - scorer: Match/scoring function. Defaults to ``paletteFuzzyScore(_:_:)``.
    ///   - width: Surface width. Invalid values use the 620-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - height: Surface height. Invalid values use the 460-point default; oversized values
    ///     are capped at 10,000 points.
    ///   - onActivate: Called instead of `result.action` when a row is activated, if
    ///     provided - lets the host route activation itself. When `nil`, the palette
    ///     dismisses and calls `result.action`.
    ///   - candidates: Asynchronously builds the candidate list, on the main actor.
    public init(
        placeholder: LocalizedStringKey = "Search…",
        emptyMessage: LocalizedStringKey = "Start typing to search.",
        noMatchesMessage: LocalizedStringKey = "No matches.",
        loadingMessage: LocalizedStringKey = "Loading…",
        resultLimit: Int = 40,
        scorer: @escaping PaletteScorer = paletteFuzzyScore,
        width: CGFloat = 620,
        height: CGFloat = 460,
        onActivate: (@MainActor (PaletteResult) -> Void)? = nil,
        candidates: @escaping @MainActor () async -> [PaletteResult]
    ) {
        self.init(
            placeholder: placeholder,
            emptyMessage: emptyMessage,
            noMatchesMessage: noMatchesMessage,
            loadingMessage: loadingMessage,
            resultLimit: resultLimit,
            scorer: scorer,
            width: width,
            height: height,
            onActivate: onActivate,
            candidates: candidates,
            row: { result, isSelected in PaletteRow(result: result, isSelected: isSelected) }
        )
    }
}
