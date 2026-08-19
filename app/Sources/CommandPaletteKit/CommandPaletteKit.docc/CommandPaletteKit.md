# ``CommandPaletteKit``

A dependency-free, Combine-free SwiftUI command palette (⌘K) for macOS and iPad - the
"jump to anything" overlay you get in VS Code, Raycast, or GitHub's `cmd-k`.

## Overview

`CommandPaletteKit` is an *action* palette, not just a search box: each result carries a
`@MainActor` action it runs when activated - navigate, run a command, switch context.
Present ``CommandPaletteView`` however you like (typically a sheet over your main window),
hand it a closure that builds the candidates, and the palette owns the query, fuzzy
matching, keyboard navigation, and selection for you.

- **No dependencies, no Combine.** Pure SwiftUI plus a small bit of AppKit for one macOS
  keyboard fix. Drops into modern Swift-concurrency projects cleanly.
- **Built-in fuzzy matching.** A self-contained scorer (exact → prefix → word-boundary
  substring → consecutive-run subsequence) with no index to build. Bring your own
  ``PaletteScorer`` to add weighting, recency, or pinning.
- **Customizable with sensible defaults.** Every knob has a default that reproduces the
  shipped look, so the zero-configuration call site stays short.
- **macOS- and iPad-robust.** Handles the papercuts an iOS-first port misses: AppKit's
  field editor swallowing the arrow keys, highlight/scroll drift as results re-sort,
  unified hover-and-keyboard selection, a VoiceOver `.isSelected` trait, and hardware
  keyboard navigation on both platforms.

```swift
import CommandPaletteKit

.sheet(isPresented: $showingPalette) {
    CommandPaletteView {
        [
            PaletteResult(
                id: "command.new",
                title: "New Document",
                subtitle: "Create a document",
                category: "Command",
                systemImage: "plus.square",
                searchText: "New Document create"
            ) { createDocument() }
        ]
    }
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``CommandPaletteView``
- ``PaletteResult``

### Customization

- <doc:Customization>
- ``PaletteRow``
- ``CommandPaletteStyle``
- ``SwiftUICore/View/commandPaletteStyle(_:)``

### Matching

- ``paletteFuzzyScore(_:_:)``
- ``PaletteScorer``

### Keyboard navigation

- <doc:KeyboardNavigation>
- ``SwiftUICore/View/commandPaletteExtendedKeyboardNavigation(_:)``
