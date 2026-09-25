import Observation
import SwiftUI
import UIKit
import VenueKit

/// Session-scoped memory (brewdesk#222) for the filtered shelf's "Might
/// match · details unknown" disclosure — mirrors `ShelfDetentMemory`'s
/// "remember for the session, not persisted to `UserDefaults`" contract. A
/// fresh launch always starts collapsed.
@Observable
final class FilterUnknownSectionMemory {
    static let session = FilterUnknownSectionMemory()

    var isExpanded = false
}

/// The map's bottom card, now an honest sheet (brewdesk#76): the grabber that
/// used to be pure decoration drags through real peek / medium / full detents,
/// and the card reopens at the last detent for the rest of the session.
///
/// Rendered as a bottom-aligned overlay inside the Explore tab — not a
/// `.sheet`, which would cover the tab bar at every detent (see `ShelfDetent`).
/// Height stays intrinsic at `.peek` and `.medium` so Dynamic Type reflows
/// instead of clipping (ui-review-2026-08-21 finding 7); only `.full` takes a
/// fixed height, and its list scrolls.
///
/// The drag RESIZES the card in place (brewdesk#125). The card's bottom edge
/// never leaves the screen bottom — its glass bleeds through the bottom safe
/// area, so the floating tab bar rests on the card's surface exactly like the
/// design spec's mockups. The pre-#125 model translated the whole card with
/// `.offset`, which slid it beneath the tab bar mid-collapse and left a strip
/// of raw map under the card's square-cut bottom at peek.
///
/// Drag state lives HERE, not on the map screen: mid-drag frames mutate only
/// this view's `dragHeight`, so the map's body — and the annotation planner —
/// never re-evaluates per frame (the brewdesk#54 invariant).
struct DiscoveryShelfCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: VenuesModel
    @Bindable var recentSearchStore: RecentSearchStore
    @Binding var detent: ShelfDetent
    let selectedID: String?
    /// Card height at `.full`, chosen by the map screen from its own geometry.
    let fullHeight: CGFloat
    /// UI3 (brewdesk#118): true while the map's search is "active" — the
    /// field has focus, OR (bd#223) there's committed typed text even after
    /// the keyboard dismissed (a results-list scroll dismisses the keyboard
    /// interactively without collapsing back to the horizontal rail — see
    /// `CafeMapScreen`'s own doc comment on `isShelfInSearchState`). The
    /// shelf promotes to a vertical result list at `fullHeight` regardless of
    /// `detent` — the old horizontal rail hid six of seven matches. Read-only
    /// here; the search header (not the shelf) owns focus and its Cancel
    /// control clears it.
    var isSearchActive = false
    let onVenueTap: (Venue) -> Void
    /// bd#223: tapping a "Recent" café row — always the PR #220 selection
    /// behavior (fly to it, commit the field, `.medium` sheet, load
    /// surroundings), resolved by id if the café scrolled out of memory.
    let onRecentCafeTap: (RecentSearchEntry) -> Void
    /// bd#223: tapping a "Recent" query row — puts the text back in the
    /// field and runs the search exactly as if the user had typed and
    /// submitted it.
    let onRecentQueryTap: (String) -> Void

    /// Concrete card height while a resize drag is live; nil at rest. The
    /// finger resizes the card 1:1 (rubber-banded past the end detents), so
    /// the bottom edge never detaches from the screen bottom (brewdesk#125).
    @State private var dragHeight: CGFloat?
    /// Shelf-card score tile scales with Dynamic Type instead of clipping in
    /// a fixed 72×82 frame (ui-review-2026-08-21 finding 7).
    @ScaledMetric(relativeTo: .title2) private var scoreTileMinWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .title2) private var scoreTileMinHeight: CGFloat = 82
    /// Last measured intrinsic height while resting at `.medium`
    /// (brewdesk#88). `.frame(height:)` cannot interpolate between `nil` and
    /// a concrete value, so it used to snap on the very first frame of every
    /// animated transition — the flash. Kept fresh by `onGeometryChange`
    /// below whenever the card is resting at `.medium`, so every settle
    /// animation has a real number to land on.
    @State private var mediumHeight: CGFloat?
    /// True only while a settle animation is in flight. Pins `cardHeight` to
    /// the target detent's concrete height for the duration so the frame can
    /// interpolate from the drag's last concrete height instead of jumping
    /// (brewdesk#88's lesson, generalized to every detent pair by #125).
    @State private var isSettling = false
    /// bd#223 (B2): the live keyboard's screen overlap, tracked so the
    /// search-mode results list (and the Recent list) can reserve a matching
    /// bottom content inset — otherwise the keyboard covers the last rows
    /// with nothing to scroll them clear of it (the reported "can't scroll
    /// the listing" bug's second half; the first half was the competing
    /// resign-focus drag gesture removed from `CafeMapScreen`). Tracked here
    /// rather than read from a SwiftUI safe area: the focused `TextField`
    /// lives in `CafeMapScreen.searchHeader`, a sibling subtree, so this
    /// card's own safe-area insets never reflect the keyboard.
    @State private var keyboardBottomInset: CGFloat = 0

    /// The card's two structural size constants. `peekHeight` must equal the
    /// card's intrinsic height at `.peek` — grabber row + vertical padding —
    /// or the un-pin after a settle animation would visibly snap.
    private static let verticalPadding: CGFloat = 10
    private static let grabberRowHeight: CGFloat = 24
    private var peekHeight: CGFloat { Self.grabberRowHeight + Self.verticalPadding * 2 }

    /// The concrete height a detent settles at. `.medium` prefers the live
    /// measurement; the fallback only matters when the session opens straight
    /// into `.full` and the card has never rested at `.medium` — the un-pin
    /// back to intrinsic self-corrects any estimate drift.
    private func baseHeight(of detent: ShelfDetent) -> CGFloat {
        switch detent {
        case .peek: peekHeight
        case .medium: mediumHeight ?? 240
        case .full: fullHeight
        }
    }

    /// `nil` at rest at peek/medium (intrinsic, Dynamic Type reflows);
    /// concrete while dragging, settling, focused, or at `.full`.
    private var cardHeight: CGFloat? {
        guard !isSearchActive else { return fullHeight }
        if let dragHeight { return dragHeight }
        if isSettling { return baseHeight(of: detent) }
        return detent == .full ? fullHeight : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            grabber
            if isSearchActive || detent != .peek {
                if showCityWideSearchFailureNote {
                    cityWideSearchFailureNote
                        .padding(.horizontal, 16)
                }
                if let reason = recentSearchStore.lastRemovalReason {
                    recentRemovalNote(reason)
                        .padding(.horizontal, 16)
                }
                venueContent
                    .transition(.opacity)
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            guard detent == .medium, dragHeight == nil, !isSettling, !isSearchActive else { return }
            mediumHeight = newHeight
        }
        .frame(height: cardHeight, alignment: .top)
        // Clip BEFORE the glass: mid-animation the rail/list crossfade must
        // not paint outside the card (the brewdesk#125 flash), but the glass
        // below still bleeds past these bounds.
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        // The sheet's surface runs to the SCREEN bottom, not the safe-area
        // line: the glass ignores the bottom inset so the floating tab bar
        // rests on card surface instead of a strip of raw map (brewdesk#125,
        // design-spec mockup 01).
        .background {
            Color.clear
                .brewDeskGlass(in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
                .ignoresSafeArea(.container, edges: .bottom)
                // Purely visual: the bleed reaches under the floating tab
                // bar, and a hit-testable glass there swallows tab taps.
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.15), radius: 14, y: -3)
        .contentShape(Rectangle())
        .gesture(resizeDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-discovery-shelf")
        .onAppear { detent = ShelfDetentMemory.session.last }
        .onChange(of: detent) { ShelfDetentMemory.session.last = detent }
        // A light tick when the shelf settles into a detent (brewdesk#75) —
        // filter feedback now lives on `WorkFitFilterButton`, the filters'
        // only remaining control surface. `.sensoryFeedback` already no-ops
        // under Reduce Motion.
        .sensoryFeedback(.selection, trigger: detent)
        // bd#223 (B2): tracks the keyboard's real screen overlap so the
        // search-mode list can reserve a matching bottom inset — see
        // `keyboardBottomInset`'s own doc comment.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
                return
            }
            let screenHeight = UIScreen.main.bounds.height
            keyboardBottomInset = max(0, screenHeight - frame.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardBottomInset = 0
        }
    }

    // MARK: - Resize

    /// The whole card resizes on a vertical drag (the inner rails claim
    /// horizontal drags and taps for themselves); the grabber is the visual
    /// promise plus the assistive-tech handle.
    private var grabber: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity, minHeight: Self.grabberRowHeight)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityIdentifier("map-shelf-grabber")
            .accessibilityLabel("Venue shelf")
            .accessibilityValue(detent.accessibilityValue)
            .accessibilityHint("Adjust to resize the shelf")
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if let up = detent.expanded { setDetent(up) }
                case .decrement: if let down = detent.collapsed { setDetent(down) }
                @unknown default: break
                }
            }
    }

    private var resizeDrag: some Gesture {
        // minimumDistance 8: venue-card and chip taps stay taps.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                dragHeight = rubberBanded(baseHeight(of: detent) - value.translation.height)
            }
            .onEnded { value in
                let target = ShelfDetent.resolve(
                    from: detent,
                    projectedTranslation: value.predictedEndTranslation.height
                )
                setDetent(target)
            }
    }

    /// The finger resizes the card 1:1 between the end detents; past either
    /// end the excess compresses, matching sheet rubber-banding.
    private func rubberBanded(_ proposed: CGFloat) -> CGFloat {
        if proposed > fullHeight { return fullHeight + (proposed - fullHeight) * 0.15 }
        if proposed < peekHeight { return peekHeight - (peekHeight - proposed) * 0.15 }
        return proposed
    }

    /// Settles the shelf on `target`, used by both the drag gesture's release
    /// and the grabber's accessibility adjustable action.
    ///
    /// Every animated settle interpolates between two CONCRETE heights
    /// (brewdesk#88's lesson): `isSettling` pins `cardHeight` to the target's
    /// height for the animation, and un-pins in the completion — by which
    /// point the pinned value equals the intrinsic height it hands back to,
    /// so nothing moves on un-pin.
    private func setDetent(_ target: ShelfDetent) {
        guard !reduceMotion else {
            dragHeight = nil
            isSettling = false
            detent = target
            return
        }
        if dragHeight != nil {
            // Released from a live drag: the transaction's "old" height is
            // the drag's concrete value, so it can animate directly.
            isSettling = true
            withAnimation(.snappy, completionCriteria: .logicallyComplete) {
                dragHeight = nil
                detent = target
            } completion: {
                isSettling = false
            }
            return
        }
        // No drag in flight (accessibility adjustable action): the old
        // height may be intrinsic (`nil`), which `.frame(height:)` cannot
        // animate from. Committing `isSettling` on its own pass first makes
        // the old height concrete; one run-loop tick (~16ms) of latency,
        // well under perceptible. (The pre-animation pin reads the CURRENT
        // detent's height, so the pinned frame matches what's on screen.)
        isSettling = true
        DispatchQueue.main.async {
            withAnimation(.snappy, completionCriteria: .logicallyComplete) {
                self.detent = target
            } completion: {
                self.isSettling = false
            }
        }
    }

    // MARK: - Content

    /// The rail/list swap lives in a top-aligned ZStack: during the settle
    /// crossfade both exist at once, and in a VStack the outgoing one would
    /// be laid out BELOW the incoming one — pushed straight out of the clip,
    /// which read as the card going blank for the animation (brewdesk#125).
    private var venueContent: some View {
        ZStack(alignment: .top) {
            venueContentSwitch
        }
    }

    @ViewBuilder
    private var venueContentSwitch: some View {
        // bd#223: focused + empty text shows "Recent" instead of the normal
        // list — but ONLY when there's something to show; an empty store
        // keeps today's behavior (falls through to the plain venue list
        // below, exactly as before this ticket).
        if isSearchActive, trimmedSearchQuery.isEmpty, !recentSearchStore.entries.isEmpty {
            recentSearchSection
                .transition(.opacity)
        } else if model.venues.isEmpty {
            emptyContent
        } else if isSearchActive || detent == .full {
            if model.hasActiveFilter {
                filteredSections
                    .transition(.opacity)
            } else {
                fullList
                    .transition(.opacity)
            }
        } else {
            horizontalRail
                .transition(.opacity)
        }
    }

    private var trimmedSearchQuery: String {
        model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// brewdesk#157: every phase gets an intentional shelf body when there's
    /// nothing to list — a bare `EmptyView()` here collapsed the card to the
    /// grabber alone, reading as a broken shelf even while the map overlay
    /// (`CafeMapScreen.loadStatus`) correctly showed its own loading/error
    /// state above it. Identifiers here are distinct from the overlay's
    /// `map-state-loading` / `map-state-error` — both can be on screen at
    /// once, and `DegradedStateTests` keys off the overlay's.
    ///
    /// bd#223 (B1): every branch here is wrapped by `centeredState(_:)` —
    /// root cause of the "jammed against the left edge" bug was that NONE of
    /// these had any horizontal centering of their own; they simply inherited
    /// the parent `VStack`'s `alignment: .leading` and hugged x=0. `.frame(
    /// minHeight:)`, not a fixed `height:`, so a two-line wrap at large
    /// Dynamic Type grows the state instead of clipping it.
    @ViewBuilder
    private var emptyContent: some View {
        switch model.phase {
        case .loaded:
            if model.isCityWideSearchPending {
                // bd#200: the local list has nothing yet and the citywide
                // server search is still in flight — a real request takes
                // longer than the instant local filter, so this replaces
                // the generic empty state for that window instead of
                // flashing "no cafés" and then correcting itself a moment
                // later.
                centeredState {
                    ProgressView("Searching all of NYC…")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("shelf-state-citywide-searching")
            } else if !model.settledSearchText.isEmpty {
                // bd#200: the citywide search settled and found nothing
                // anywhere, not just in this viewport — distinct copy from
                // the generic "No cafés here yet" below, naming the actual
                // search so it reads as "we looked everywhere", not "try
                // panning".
                centeredState {
                    ContentUnavailableView {
                        Label("No cafés named “\(model.searchQuery)” in NYC yet", systemImage: "cup.and.saucer")
                    } description: {
                        Text("Check the spelling, or clear the search to browse the area.")
                    } actions: {
                        Button("Browse NYC") { model.browseCoverageCenter() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("map-browse-nyc")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map-state-empty")
            } else {
                // bd#192: "No cafés here yet" — distinct from the old generic
                // "No spots in this view" now that a zero-result viewport can
                // come from a real "Search this area" fetch, not just a filter.
                centeredState {
                    ContentUnavailableView {
                        Label("No cafés here yet", systemImage: "cup.and.saucer")
                    } description: {
                        Text("Clear a filter, search a different spot, or try another area.")
                    } actions: {
                        Button("Browse NYC") { model.browseCoverageCenter() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("map-browse-nyc")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map-state-empty")
            }
        case .idle, .loading:
            centeredState {
                ProgressView("Finding work spots…")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("shelf-state-loading")
        case .failed:
            centeredState {
                ContentUnavailableView {
                    Label("Spot service unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("shelf-state-error")
        }
    }

    /// bd#223 (B1): centers a search-state view as one group (spinner/icon
    /// beside or above its text, never pinned to the leading edge), 24pt side
    /// padding, and lets it grow past the old fixed 170pt so a two-line wrap
    /// at large Dynamic Type never clips.
    private func centeredState(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 170)
            .padding(.horizontal, 24)
    }

    /// bd#200: the citywide server search failed (network/HTTP) but local
    /// results — if any — are still showing; a quiet inline note, never an
    /// alert, per the ticket ("keep local results ... no alert").
    private var showCityWideSearchFailureNote: Bool {
        model.serverSearchFailed && !model.settledSearchText.isEmpty
    }

    /// bd#223 (B1): the "quiet failure line" — centered with the same 24pt
    /// side padding as the other search states, wrapping instead of clipping.
    private var cityWideSearchFailureNote: some View {
        Text("Couldn't search beyond this area")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("shelf-citywide-search-failed")
    }

    /// bd#223: the Recent tap's detail fetch reported "gone" — same
    /// centered/wrapping treatment as the other inline shelf notes.
    private func recentRemovalNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("search-recents-unavailable")
            .task(id: text) {
                try? await Task.sleep(for: .seconds(3))
                recentSearchStore.clearRemovalReason()
            }
    }

    private var horizontalRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(railVenues.prefix(12)) { venue in
                    venueButton(venue, fillsWidth: false)
                }
            }
            .padding(.horizontal, 16)
        }
        // No fixed shelf height: cards reflow vertically at
        // accessibility sizes instead of clipping (finding 7).
        .fixedSize(horizontal: false, vertical: true)
    }

    /// bd#222: the compact rail has no room for section headers, so while a
    /// filter is active it shows CONFIRMED matches only — never an unknown
    /// venue (the WeWork complaint: unknown Wi-Fi must sit only under
    /// "Might match", not lead the shelf). An honestly empty rail (nothing
    /// confirmed yet) is expected here; `.full` is where the unknown
    /// section and its own empty-state copy live. A no-op (`model.venues`
    /// itself) while no filter is active.
    private var railVenues: [Venue] {
        model.hasActiveFilter ? model.confirmedVenues : model.venues
    }

    /// `.full` earns its height: the rail becomes a scrolling vertical list
    /// of every venue in view, not twelve cards over dead space.
    ///
    /// bd#223 (B2 — "I can't scroll the listing!! When typing!?"): root
    /// cause was TWO stacked bugs, both fixed here rather than in this
    /// `ScrollView` alone:
    /// 1. `CafeMapScreen` used to attach a `simultaneousGesture(DragGesture(
    ///    minimumDistance: 8))` over the WHOLE shelf overlay that set
    ///    `searchFocused = false` on the first 8pt of ANY drag, including one
    ///    starting inside this list. That flipped `isSearchActive` false
    ///    mid-touch, swapping this list back out for the horizontal rail
    ///    before the `ScrollView` below ever got to recognize the drag as a
    ///    scroll — removed there; `.scrollDismissesKeyboard(.interactively)`
    ///    here is now the ONLY thing that resigns focus on a list drag, and
    ///    it ties into `@FocusState` natively without competing for the
    ///    touch. `isSearchActive` also no longer collapses back to the rail
    ///    just because focus resigned this way — see its own doc comment.
    /// 2. This card's fixed `fullHeight` never reserved room for the
    ///    keyboard (a sibling subtree owns the focused field, so no SwiftUI
    ///    safe area ever reflected it here) — the last rows sat UNDER the
    ///    keyboard with nothing to scroll them clear of it.
    ///    `keyboardBottomInset` (tracked via `UIResponder.keyboardWill…`
    ///    notifications) fixes that as a real content margin.
    private var fullList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !trimmedSearchQuery.isEmpty {
                    let suggestions = recentSearchStore.matching(
                        prefix: trimmedSearchQuery,
                        excludingCafeIDs: Set(model.venues.map(\.id))
                    )
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, entry in
                        recentSuggestionRow(entry, index: index)
                    }
                }
                ForEach(model.venues) { venue in
                    venueButton(venue, fillsWidth: true)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, keyboardBottomInset, for: .scrollContent)
    }

    // MARK: - Honest filter sections (bd#222)

    /// Replaces `fullList` while a filter is active (brewdesk#222):
    /// confirmed matches under their own accessible header/count, then a
    /// collapsed-by-default "might match" section for filter-unknown
    /// venues. Excluded venues never reach either — `model.confirmedVenues`/
    /// `model.unknownVenues` are both already-filtered slices of
    /// `model.venues` (which itself already drops anything
    /// `VenueFilter.matches` rejects).
    private var filteredSections: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                confirmedSection
                unknownSection
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, keyboardBottomInset, for: .scrollContent)
    }

    @ViewBuilder
    private var confirmedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.confirmedVenues.isEmpty {
                confirmedEmptyState
            } else {
                Text("Matches your filters (\(model.confirmedVenues.count))")
                    .font(.subheadline.bold())
                    .foregroundStyle(BrewDeskPalette.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.confirmedVenues) { venue in
                    venueButton(venue, fillsWidth: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filter-confirmed-section")
    }

    /// "No café here is confirmed for these filters yet" (brewdesk#222):
    /// distinct from `emptyContent`'s "No cafés here yet" — this fires only
    /// when the confirmed HALF is empty while unknowns still exist (venues
    /// nothing is known to fail, just not yet proven). The "Been here? Rate
    /// it." nudge points at the same fix a real gap here needs: a rating
    /// turns an unknown into a confirmed match or a known exclusion, either
    /// way honest. Lives inside `confirmedSection`'s own
    /// `filter-confirmed-section` container rather than carrying a second
    /// identifier of its own — SwiftUI flattens an intermediate
    /// `.accessibilityElement(children: .contain)` that has no traits/label
    /// of its own and is its container's only child, so a second identifier
    /// here never showed up as its own queryable node.
    private var confirmedEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No café here is confirmed for these filters yet")
                .font(.subheadline.weight(.semibold))
            Text("Been here? Rate it.")
                .font(.caption)
                .foregroundStyle(BrewDeskPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var unknownSection: some View {
        if !model.unknownVenues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    // bd#222 (supervisor follow-up, PR #226 dark-mode
                    // review): a no-op tap when there's nothing to collapse
                    // TO, rather than `.disabled(...)` — SwiftUI applies an
                    // automatic reduced-opacity treatment to a disabled
                    // control regardless of `.buttonStyle(.plain)` or an
                    // explicit `.foregroundStyle`, which read as the whole
                    // row being dimmed (caught by
                    // `.performAccessibilityAudit(for: .contrast)`, added
                    // alongside this fix). The row stays fully interactive
                    // and fully legible; it just has nothing to do while
                    // the confirmed section is empty.
                    guard !model.confirmedVenues.isEmpty else { return }
                    FilterUnknownSectionMemory.session.isExpanded.toggle()
                } label: {
                    HStack {
                        Text("Might match · details unknown (\(model.unknownVenues.count))")
                            .font(.subheadline.bold())
                            .foregroundStyle(BrewDeskPalette.secondaryText)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(BrewDeskPalette.secondaryText)
                            .rotationEffect(.degrees(isUnknownSectionExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("filter-unknown-toggle")
                .accessibilityValue(isUnknownSectionExpanded ? "Expanded" : "Collapsed")

                if isUnknownSectionExpanded {
                    ForEach(model.unknownVenues) { venue in
                        venueButton(venue, fillsWidth: true)
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: isUnknownSectionExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("filter-unknown-section")
        }
    }

    /// Collapsed by default, remembered for the session
    /// (`FilterUnknownSectionMemory`) — but forced open whenever the
    /// confirmed section is empty (brewdesk#222 spec): with nothing
    /// confirmed to show, hiding the only venues actually on screen behind
    /// an extra tap would be strictly worse than just showing them. The
    /// toggle itself is disabled in that state (there's nothing to collapse
    /// TO), and re-enables once a confirmed match exists again.
    private var isUnknownSectionExpanded: Bool {
        model.confirmedVenues.isEmpty || FilterUnknownSectionMemory.session.isExpanded
    }

    // MARK: - Recent searches (bd#223)

    private var recentSearchSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                recentSearchHeader
                LazyVStack(spacing: 10) {
                    ForEach(Array(recentSearchStore.entries.enumerated()), id: \.element.id) { index, entry in
                        recentSearchRow(entry, index: index)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, keyboardBottomInset, for: .scrollContent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-recents")
    }

    private var recentSearchHeader: some View {
        HStack {
            Text("Recent")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { recentSearchStore.clear() }
                .font(.subheadline.bold())
                .accessibilityIdentifier("search-recents-clear")
        }
    }

    /// A row in the full "Recent" section — swipe-to-delete, tap to re-run.
    private func recentSearchRow(_ entry: RecentSearchEntry, index: Int) -> some View {
        SwipeToDeleteRow {
            recentSearchStore.remove(at: index)
        } content: {
            recentRowButton(entry)
        }
        .accessibilityIdentifier("search-recent-row-\(index)")
    }

    /// A recent surfaced ABOVE the live results while typing — visually
    /// distinct (tinted background, no swipe) and de-duplicated against
    /// `model.venues` by the caller (`fullList`).
    private func recentSuggestionRow(_ entry: RecentSearchEntry, index: Int) -> some View {
        recentRowButton(entry)
            .background(BrewDeskPalette.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("search-recent-suggestion-\(index)")
    }

    private func recentRowButton(_ entry: RecentSearchEntry) -> some View {
        Button {
            switch entry {
            case .cafe:
                onRecentCafeTap(entry)
            case .query(let text):
                onRecentQueryTap(text)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let neighborhood = entry.neighborhood {
                        Text(neighborhood)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.left")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent search: \(entry.title)")
    }

    private func venueButton(_ venue: Venue, fillsWidth: Bool) -> some View {
        Button {
            onVenueTap(venue)
        } label: {
            venueCard(venue, fillsWidth: fillsWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(venue.name), \(venue.displayScore.map { "Work Fit \($0)" } ?? "not rated yet"), \(venue.neighborhood)"
            + accessibilityTypeSuffix(venue.typeBadge)
        )
    }

    /// Shelf card. No fixed frames on the score tile and no hard-coded 8pt
    /// label: at accessibility sizes the old 72×82 tile clipped to "7 WOR"
    /// (ui-review-2026-08-21 finding 7). The tile now scales with the score's
    /// text style and the caption rides Dynamic Type via `.caption2`.
    ///
    /// bd#209: this used to print the tier color itself as TEXT on a 14%-
    /// opacity tint of that same color — on `great` (roast, a dark green)
    /// that rendered as dark-green-on-dark-green, effectively unreadable,
    /// and doubly bad for a red-green colorblind reader because the only
    /// thing separating the number from its tile was that exact hue-on-hue
    /// mismatch. Same fix as `ScoreBadge`: a neutral, high-contrast tile
    /// (`surfaceSecondary` + `clusterSurfaceText`, verified 4.5:1+ in both
    /// appearances) with the tier communicated by a ring instead of by
    /// making the text itself the tier hue.
    private func venueCard(_ venue: Venue, fillsWidth: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                if let score = venue.displayScore {
                    Text("\(score)")
                        .font(.title2.monospacedDigit().bold())
                    Text("WORK FIT")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    // Not a score — never `workScore`'s flat neutral
                    // fallback (ve#64/bd#159), and never a number at all
                    // (brewdesk#213): an en dash plus a caption, matching
                    // the rated tile's own two-line shape.
                    Text(verbatim: "–")
                        .font(.title2.monospacedDigit().bold())
                        .accessibilityHidden(true)
                    Text("NOT RATED")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(BrewDeskPalette.clusterSurfaceText)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(minWidth: scoreTileMinWidth, minHeight: scoreTileMinHeight)
            .background(BrewDeskPalette.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        venue.displayScore != nil ? venue.scoreTier.color : BrewDeskPalette.unobserved,
                        lineWidth: 2
                    )
            )
            // brewdesk#213: an explicit, single label rather than relying on
            // SwiftUI's automatic multi-Text grouping (which doesn't
            // reliably drop the `.accessibilityHidden` en dash from the
            // merged result) — also lets a UI test scope its "no digit
            // shown" assertion to just this tile, not the whole card (which
            // legitimately carries other digits, e.g. a provenance date).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(venue.displayScore.map { "Work Fit \($0)" } ?? "Not rated yet")
            .accessibilityIdentifier("shelf-score-tile")

            VStack(alignment: .leading, spacing: 5) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                // brewdesk#170: system `.secondary` measured "Contrast
                // nearly passed" against this card's `surface` background —
                // same root cause bd#216 already fixed for the Workability
                // stamp, same fix: the contrast-verified
                // `BrewDeskPalette.secondaryText` token.
                HStack(spacing: 6) {
                    Text(venue.neighborhood)
                        .font(.caption)
                        .foregroundStyle(BrewDeskPalette.secondaryText)
                    // brewdesk#240: the type badge sits right next to the
                    // neighborhood line — renders nothing for a café
                    // (`VenueTypeBadge.showsBadge`).
                    VenueTypeBadgeView(type: venue.typeBadge)
                }
                // brewdesk#170: same `.secondary`-on-`surface` contrast
                // issue as the neighborhood line above ("Unknown"/"Fast"
                // wifi labels both measured "nearly passed") — same fix.
                HStack(spacing: 10) {
                    Label(localizedAttributeValue(venue.attributes.wifi.value), systemImage: "wifi")
                    Label(localizedAttributeValue(venue.attributes.outlets.value), systemImage: "powerplug")
                }
                .font(.caption2)
                .foregroundStyle(BrewDeskPalette.secondaryText)
                // brewdesk#240 item 5: "Not rated yet" gets a reason, room
                // permitting — this card's info column has it, unlike the
                // narrow score tile itself.
                if venue.displayScore == nil, let caption = scoreCoverageCaption(venue.scoreCoverage) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(BrewDeskPalette.secondaryText)
                        .accessibilityIdentifier("shelf-score-coverage-caption")
                }
                ProvenanceStamp(attributes: venue.attributes, tier: venue.tier)
            }

            if fillsWidth {
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(
            width: fillsWidth ? nil : (dynamicTypeSize.isAccessibilitySize ? 330 : 285),
            alignment: .leading
        )
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(BrewDeskPalette.surface, in: RoundedRectangle(cornerRadius: 20))
        .animation(reduceMotion ? nil : .snappy, value: selectedID)
    }
}

/// bd#223: a lightweight swipe-to-delete for the "Recent" list, which lives
/// in a plain `ScrollView`/`LazyVStack` (not a `List`) — the same rail/full
/// list technology every other shelf row already uses — so the native
/// `.swipeActions(_:)` (List-only) isn't available here. A horizontal drag
/// past `revealThreshold` deletes on release; a drag that reads more
/// vertical than horizontal is ignored entirely so it never competes with
/// the enclosing `ScrollView`'s own vertical pan (the exact B2 failure mode
/// this ticket's other fix removes at the `CafeMapScreen` level).
private struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0
    /// Guards against `onDelete` firing more than once for a single swipe —
    /// `.onEnded` composed with `.animation(value:)` on the SAME gesture can
    /// otherwise re-invoke once per settling frame; with `onDelete` calling
    /// `RecentSearchStore.remove(at:)` against a fixed, captured index, a
    /// second stale call after the array already shifted silently deletes
    /// the WRONG (now-different) row.
    @State private var hasDeleted = false
    private let revealThreshold: CGFloat = -64

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.red)
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.white)
                        .padding(.trailing, 22)
                        .accessibilityHidden(true)
                }
            content()
                .background(BrewDeskPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                .offset(x: min(0, offsetX + dragTranslation))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // bd#223: `.highPriorityGesture`, not plain `.gesture` — the row's
        // OWN content is a `Button` (tap to re-run/fly-to); without
        // priority, a fast horizontal drag could ALSO be interpreted as a
        // tap release on that button once the finger lifts, firing BOTH
        // the delete AND the row's own tap action for the same swipe
        // (reproduced: swiping to delete a QUERY recent also re-submitted
        // that exact query, changing `model.searchQuery` out from under the
        // "Recent" section's own empty-query display condition).
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .updating($dragTranslation) { value, state, _ in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = min(0, value.translation.width)
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < revealThreshold, !hasDeleted {
                        hasDeleted = true
                        onDelete()
                    }
                    offsetX = 0
                }
        )
        .animation(.snappy, value: dragTranslation)
        // bd#223: without this, `search-recent-row-<index>` (applied by the
        // caller) is inherited by every descendant accessibility element —
        // the content BUTTON and the decorative trash icon both end up
        // "matching" the same identifier, so an XCUITest query for it finds
        // more than one element. `.combine` merges everything left (the
        // content button; the trash icon is already `.accessibilityHidden`)
        // into that ONE element, which also gives VoiceOver a single swipe
        // stop for the whole row instead of two.
        .accessibilityElement(children: .combine)
    }
}
