//
//  CommandPaletteView.swift
//  CommandPaletteKit
//
//  A dependency-free, Combine-free "jump to anything" palette (⌘K): type to fuzzy-search
//  a caller-supplied list of ``PaletteResult`` and activate one by keyboard or click.
//  Present it however you like - typically as a sheet over your main window.
//
//  Everything that was hardcoded in the original app extraction is a parameter here, with
//  a default that reproduces the shipped look and feel, so the zero-configuration call
//  site stays short.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

let maximumPaletteDimension: CGFloat = 10_000

/// Returns geometry that is safe to pass to SwiftUI's fixed-size frame API.
func normalizedPaletteDimension(_ dimension: CGFloat, fallback: CGFloat) -> CGFloat {
    guard dimension.isFinite, dimension > 0 else { return fallback }

    return min(dimension, maximumPaletteDimension)
}

/// Keeps result identity unambiguous for SwiftUI rows and scroll targets.
///
/// The first candidate supplied for an ID wins. Doing this before filtering and scoring
/// makes the result deterministic across queries and prevents a duplicate from silently
/// replacing the action associated with an existing row.
func deduplicatedPaletteResults(_ results: [PaletteResult]) -> [PaletteResult] {
    var seenIDs = Set<String>()
    return results.filter { seenIDs.insert($0.id).inserted }
}

/// The command palette surface: a search field above a scrolling, keyboard-navigable
/// result list. Owns the query and the selection; the candidate list is built on appear
/// from the supplied provider and re-scored on every keystroke.
public struct CommandPaletteView<RowContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.commandPaletteExtendedKeyboardNavigation) private var extendedNavigation

    @State var query = ""
    @State var candidates: [PaletteResult] = []
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State var candidateLoadGeneration = CandidateLoadGeneration()
    @State private var measuredRowHeights: [String: CGFloat] = [:]
    @State var resultSnapshot = PaletteResultSnapshot()
    @FocusState private var queryFocused: Bool
    // Keeps a scroll-induced hover from stealing the selection back from the keyboard.
    // `@State`, not a local: the hover handler and `move(by:)` are different callbacks and
    // must share one gate.
    @State private var hoverGate = HoverSelectionGate()
    // A snapshot of `extendedNavigation`, refreshed from `body` (below) whenever the
    // environment value changes. `@Environment` is only meaningful while the view is
    // installed, so the escaping key-monitor closure - which runs long after body
    // evaluation - reads this instead; reading the environment property there yields the
    // default (`false`) and quietly disables the opt-in keys altogether.
    @State var extendedNavigationEnabled = false
    #if os(macOS)
        // Local key-event monitor for the up/down arrows. The search field is focused so
        // the user can type, but AppKit's field editor then swallows the arrow keys for
        // caret movement before SwiftUI's `.onKeyPress` ever sees them - so we watch for
        // them at the event level and drive the selection ourselves.
        // Internal, not private: the monitor itself lives in
        // CommandPaletteView+KeyMonitor.swift, and `private` is file-scoped.
        @State var arrowKeyMonitor: Any?
        // The window the palette is presented in, so the monitor can tell the palette's own
        // key events from those of every other window in the application.
        @State var paletteWindow: NSWindow?
    #endif

    // Where the candidate list comes from: built synchronously on appear, or awaited from
    // an async provider (showing a loading affordance until it resolves). Internal so the
    // public initializers in CommandPaletteView+Initializers.swift can construct it.
    enum CandidateSource {
        case sync(@MainActor () -> [PaletteResult])
        case async(@MainActor () async -> [PaletteResult])
    }

    private let source: CandidateSource
    private let placeholder: LocalizedStringKey
    private let emptyMessage: LocalizedStringKey
    private let noMatchesMessage: LocalizedStringKey
    private let loadingMessage: LocalizedStringKey
    let resultLimit: Int
    let scorer: PaletteScorer
    private let width: CGFloat
    private let height: CGFloat
    private let onActivate: (@MainActor (PaletteResult) -> Void)?
    private let row: (PaletteResult, Bool) -> RowContent

    // The fully-specified initializer all public initializers funnel into. Kept internal
    // (not private) so the public initializers in CommandPaletteView+Initializers.swift can
    // reach it; the public surface is the initializers in that file.
    init(
        source: CandidateSource,
        placeholder: LocalizedStringKey,
        emptyMessage: LocalizedStringKey,
        noMatchesMessage: LocalizedStringKey,
        loadingMessage: LocalizedStringKey,
        resultLimit: Int,
        scorer: @escaping PaletteScorer,
        width: CGFloat,
        height: CGFloat,
        onActivate: (@MainActor (PaletteResult) -> Void)?,
        row: @escaping (PaletteResult, Bool) -> RowContent
    ) {
        self.source = source
        self.placeholder = placeholder
        self.emptyMessage = emptyMessage
        self.noMatchesMessage = noMatchesMessage
        self.loadingMessage = loadingMessage
        self.resultLimit = normalizedResultLimit(resultLimit)
        self.scorer = scorer
        self.width = normalizedPaletteDimension(width, fallback: 620)
        self.height = normalizedPaletteDimension(height, fallback: 460)
        self.onActivate = onActivate
        self.row = row
    }

    private var results: [PaletteResult] {
        resultSnapshot.results
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: width, height: height)
        // Read the environment value here, during body evaluation, where it is actually
        // installed - and mirror it into `@State` for the escaping monitor closure to use.
        // `initial: true` seeds it on the first evaluation, so the two never disagree.
        .onChange(of: extendedNavigation, initial: true) { _, enabled in
            extendedNavigationEnabled = enabled
        }
        #if os(macOS)
        .background(WindowReader { paletteWindow = $0 })
        #endif
        .onAppear {
            // Build a synchronous list up front so the zero-config case shows instantly
            // with no loading flash. The async source is loaded in `.task` below.
            if case .sync(let provider) = source {
                invalidateCandidateLoads()
                let loadedCandidates = provider()
                candidates = loadedCandidates
                refreshResultSnapshot(candidates: loadedCandidates)
                isLoading = false
            }
            queryFocused = true
            #if os(macOS)
                installArrowKeyMonitor()
            #endif
        }
        .task {
            guard case .async(let provider) = source else { return }

            let generation = beginCandidateLoad()
            isLoading = true
            let loadedCandidates = await provider()
            guard candidateLoadGeneration.accepts(
                generation,
                isCancelled: Task.isCancelled
            ) else { return }

            candidates = loadedCandidates
            refreshResultSnapshot(candidates: loadedCandidates)
            isLoading = false
        }
        .onDisappear {
            invalidateCandidateLoads()
            isLoading = false
            #if os(macOS)
                removeArrowKeyMonitor()
            #endif
        }
        #if os(iOS)
        // iPad hardware-keyboard navigation. The search field is the focused descendant, so
        // these ancestor handlers see its key events first and consume the arrows (returning
        // `.handled`) before the field would move its caret - the macOS equivalent of the
        // NSEvent monitor above. Return is already handled by the field's `onSubmit`.
        .onKeyPress(.upArrow) { move(by: -1); return .handled }
        .onKeyPress(.downArrow) { move(by: 1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        // Opt-in power-user keys. The handlers are always attached but no-op (returning
        // `.ignored`, so the key falls through to the field) unless the host has enabled
        // them, keeping default behaviour unchanged when off. Ctrl-N/Ctrl-P share the "n"/"p"
        // characters with normal typing, so they only act with the Control modifier held.
        .onKeyPress(characters: CharacterSet(charactersIn: "np"), phases: [.down, .repeat]) { keyPress in
            guard extendedNavigation, keyPress.modifiers.contains(.control) else { return .ignored }

            move(by: keyPress.characters == "n" ? 1 : -1)
            return .handled
        }
        .onKeyPress(.pageUp) {
            guard extendedNavigation else { return .ignored }

            move(by: -pageStep)
            return .handled
        }
        .onKeyPress(.pageDown) {
            guard extendedNavigation else { return .ignored }

            move(by: pageStep)
            return .handled
        }
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($queryFocused)
                .onSubmit(activateSelection)
                .onChange(of: query) { _, _ in
                    selectedIndex = 0
                    refreshResultSnapshot()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Escape-to-dismiss is a macOS hardware-key affordance; on iOS the sheet dismisses
        // via its own swipe-down / background tap.
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                resultsContent
                    .padding(8)
            }
            .onChange(of: selectedIndex) { _, new in
                scrollSelection(new, proxy: proxy)
            }
            .onPreferenceChange(PaletteRowHeightPreferenceKey.self) { heights in
                if measuredRowHeights != heights { measuredRowHeights = heights }
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        LazyVStack(spacing: 2) {
            if isLoading && results.isEmpty {
                loadingMessageView
            } else if results.isEmpty {
                emptyResultsMessage
            } else {
                resultRows
            }
        }
    }

    private var loadingMessageView: some View {
        ProgressView {
            Text(loadingMessage)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private var emptyResultsMessage: some View {
        Text(normalizedPaletteQuery(query).isEmpty ? emptyMessage : noMatchesMessage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
    }

    private var resultRows: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
            resultRow(result, index: index)
        }
    }

    private func resultRow(_ result: PaletteResult, index: Int) -> some View {
        row(result, index == selectedIndex)
            // Identify the row by the result's stable id (matching the ForEach identity),
            // not its position: a bare `.id(index)` keeps ids 0,1,2… fixed while a search
            // re-orders the content under them, so the highlight and scroll target drift.
            .id(result.id)
            .contentShape(Rectangle())
            .onTapGesture { activate(result) }
            // Hovering a row makes it the selection, so the mouse and keyboard share one
            // highlight and a click always activates the row under the cursor. The hovered
            // row is by definition visible, so the scroll handler can't lurch the list.
            //
            // The reverse coupling does need guarding: a keyboard move scrolls the list,
            // which slides rows under a stationary cursor, which SwiftUI reports as a hover
            // that would write the selection straight back. ``HoverSelectionGate`` ignores
            // hovers for a moment after a keyboard move so navigation can't be stalled by a
            // mouse that is simply sitting there.
            #if !os(tvOS)
                .onHover { hovering in
                    guard hovering, hoverGate.allowsHoverSelection() else { return }

                    selectedIndex = index
                }
            #endif
            // One combined element per row so VoiceOver reads it as a single button, and
            // the selected one announces (and exposes for tests) the `.isSelected` trait.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: PaletteRowHeightPreferenceKey.self,
                        value: [result.id: geometry.size.height]
                    )
                }
            }
    }

    private func scrollSelection(_ new: Int, proxy: ScrollViewProxy) {
        // Scroll by the selected result's stable id, and only enough to keep it visible
        // (no forced centering, which lurches a short filtered list).
        guard results.indices.contains(new) else { return }

        let id = results[new].id
        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
    }

    // Internal so the macOS key monitor in CommandPaletteView+KeyMonitor.swift can
    // drive it; `private` is file-scoped.
    func move(by delta: Int) {
        let count = results.count
        guard count > 0 else { return }

        let new = clampedSelectionIndex(current: selectedIndex, delta: delta, count: count)
        guard new != selectedIndex else { return }

        // Hold hover off for a beat: this selection change is about to scroll the list, and
        // the rows sliding under the cursor would otherwise hover the selection back.
        hoverGate.keyboardDidMove()
        selectedIndex = new
    }

    // How many rows Page Up/Down jumps: roughly a viewport of the currently realized custom
    // rows, keeping one row of overlap for context. Internal for testing.
    var pageStep: Int {
        pageNavigationStep(
            for: height,
            rowHeight: representativePaletteRowHeight(Array(measuredRowHeights.values))
        )
    }

    private func activateSelection() {
        guard let selectedResult = resultSnapshot.result(at: selectedIndex) else { return }

        activate(selectedResult)
    }

    private func activate(_ result: PaletteResult) {
        dismiss()
        if let onActivate {
            onActivate(result)
        } else {
            result.action()
        }
    }
}
