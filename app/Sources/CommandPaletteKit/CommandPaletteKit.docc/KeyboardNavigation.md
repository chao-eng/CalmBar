# Keyboard navigation

Drive the palette entirely from the keyboard on macOS and on iPad with a hardware keyboard.

## Overview

The palette is keyboard-first. Selection logic is platform-agnostic; only the plumbing that
delivers the key events differs between macOS and iOS.

### Default keys

| Key | Action |
|---|---|
| Up / Down arrow | Move the selection |
| Return | Activate the selected row |
| Esc | Dismiss the palette |

- **macOS:** the arrow keys are driven by a local `NSEvent` monitor, because AppKit's field
  editor would otherwise swallow them for caret movement before SwiftUI sees them. Esc is
  handled via `onExitCommand`.
- **iPad (hardware keyboard):** the same arrows, Return, and Esc are driven through
  SwiftUI's `onKeyPress`, attached to an ancestor of the focused search field so the field
  doesn't intercept the arrows for caret movement.

### Power-user keys (opt-in)

Off by default to avoid surprising key interception. Enable Emacs-style `Ctrl-N`/`Ctrl-P`
(move down/up) and Page Up/Down (jump a viewport-sized step) with
``SwiftUICore/View/commandPaletteExtendedKeyboardNavigation(_:)``:

```swift
CommandPaletteView { buildCandidates() }
    .commandPaletteExtendedKeyboardNavigation()
```

When enabled, `Ctrl-N`/`Ctrl-P` act only with the Control modifier held, so typing `n` or
`p` into the search field still works. Page Up/Down move by roughly a page of rows,
estimated from the surface height.
