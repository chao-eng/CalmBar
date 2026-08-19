# Customization

Override only what you need - every knob has a default that reproduces the shipped look.

## Overview

The zero-config call site stays short because everything below has a default. Reach for a
knob only when you want to change it.

| Knob | Where | Default |
|---|---|---|
| Candidate list | `candidates:` closure (sync **or** `async`) | required |
| Trailing category tag | ``PaletteResult/category`` | `nil` (hidden) |
| Icon | ``PaletteResult/icon`` (any `Image`) or `systemImage:` | required |
| Hide until searching | ``PaletteResult/showsOnlyWhenSearching`` | `false` |
| Match/scoring | `scorer:` | ``paletteFuzzyScore(_:_:)`` |
| Result cap | `resultLimit:` | `40` |
| Placeholder / empty / no-match copy | `placeholder:` / `emptyMessage:` / `noMatchesMessage:` | English defaults |
| Surface size | `width:` / `height:` | `620 × 460` |
| Activation routing | `onActivate:` | runs `result.action` |
| Row cell | `row:` `@ViewBuilder` | built-in ``PaletteRow`` |
| Colours & metrics | ``SwiftUICore/View/commandPaletteStyle(_:)`` | accent fill, white-on-accent |

```swift
CommandPaletteView(
    placeholder: "Jump to…",
    resultLimit: 20,
    scorer: myWeightedScorer
) { buildCandidates() }
.commandPaletteStyle(
    CommandPaletteStyle(selectionColor: .blue, rowCornerRadius: 10)
)
```

## Styling

Apply ``CommandPaletteStyle`` with ``SwiftUICore/View/commandPaletteStyle(_:)`` to change the
colours and metrics of the surface and its rows. Unset values fall back to the defaults.

```swift
CommandPaletteView { buildCandidates() }
    .commandPaletteStyle(
        CommandPaletteStyle(
            selectionColor: .blue,
            selectedForeground: .white,
            rowCornerRadius: 10
        )
    )
```

## Custom rows

Pass a `row` builder to replace the cell entirely. It receives the ``PaletteResult`` and
whether it is the current selection; the container keeps owning selection, hover,
scroll-to, and accessibility, so you only describe the cell's appearance:

```swift
CommandPaletteView(candidates: { buildCandidates() }) { result, isSelected in
    HStack {
        result.icon
        Text(result.title).bold(isSelected)
        Spacer()
    }
    .padding(.vertical, 6)
}
```

The built-in ``PaletteRow`` is public, so a custom builder can also wrap or decorate it
rather than start from scratch.

## Async candidates

When the candidate list comes from disk, a database, or the network, pass an `async`
provider instead. The palette presents immediately and shows a loading affordance until the
provider resolves; the synchronous form is unchanged:

```swift
CommandPaletteView(loadingMessage: "Indexing…") {
    await loadCandidatesFromDisk()   // @MainActor () async -> [PaletteResult]
}
```

## Custom scoring

The default ``paletteFuzzyScore(_:_:)`` ranks exact matches highest, then prefix, then
word-boundary substrings, then consecutive-run subsequences. Supply your own
``PaletteScorer`` to add weighting, recency, or pinning - return `nil` to exclude a
candidate, or a higher score to rank it closer to the top.

```swift
let recencyBoosted: PaletteScorer = { query, text in
    guard let base = paletteFuzzyScore(query, text) else { return nil }
    return base + boost(for: text)
}

CommandPaletteView(scorer: recencyBoosted) { buildCandidates() }
```
