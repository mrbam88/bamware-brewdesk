import SwiftUI
import VenueKit

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
    @Binding var detent: ShelfDetent
    let selectedID: String?
    /// Card height at `.full`, chosen by the map screen from its own geometry.
    let fullHeight: CGFloat
    /// UI3 (brewdesk#118): true while the map's search field has focus. The
    /// shelf promotes to a vertical result list at `fullHeight` regardless of
    /// `detent` — the old horizontal rail hid six of seven matches. Read-only
    /// here; the search header (not the shelf) owns focus and its Cancel
    /// control clears it.
    var isSearchFocused = false
    let onVenueTap: (Venue) -> Void

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
        guard !isSearchFocused else { return fullHeight }
        if let dragHeight { return dragHeight }
        if isSettling { return baseHeight(of: detent) }
        return detent == .full ? fullHeight : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            grabber
            if isSearchFocused || detent != .peek {
                venueContent
                    .transition(.opacity)
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            guard detent == .medium, dragHeight == nil, !isSettling, !isSearchFocused else { return }
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
        if model.venues.isEmpty {
            // Only a *loaded* empty result is an empty state; while loading
            // or failed the overlay owns the message and the shelf stays quiet.
            if model.phase == .loaded {
                ContentUnavailableView {
                    Label("No spots in this view", systemImage: "cup.and.saucer")
                } description: {
                    Text("Clear a filter or try another search.")
                } actions: {
                    Button("Browse NYC") { model.browseCoverageCenter() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("map-browse-nyc")
                }
                .frame(height: 170)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("map-state-empty")
            }
        } else if isSearchFocused || detent == .full {
            fullList
                .transition(.opacity)
        } else {
            horizontalRail
                .transition(.opacity)
        }
    }

    private var horizontalRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(model.venues.prefix(12)) { venue in
                    venueButton(venue, fillsWidth: false)
                }
            }
            .padding(.horizontal, 16)
        }
        // No fixed shelf height: cards reflow vertically at
        // accessibility sizes instead of clipping (finding 7).
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `.full` earns its height: the rail becomes a scrolling vertical list
    /// of every venue in view, not twelve cards over dead space.
    private var fullList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.venues) { venue in
                    venueButton(venue, fillsWidth: true)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func venueButton(_ venue: Venue, fillsWidth: Bool) -> some View {
        Button {
            onVenueTap(venue)
        } label: {
            venueCard(venue, fillsWidth: fillsWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood)"
        )
    }

    /// Shelf card. No fixed frames on the score tile and no hard-coded 8pt
    /// label: at accessibility sizes the old 72×82 tile clipped to "7 WOR"
    /// (ui-review-2026-08-21 finding 7). The tile now scales with the score's
    /// text style and the caption rides Dynamic Type via `.caption2`.
    private func venueCard(_ venue: Venue, fillsWidth: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Text("\(venue.workScore)")
                    .font(.title2.monospacedDigit().bold())
                Text("WORK FIT")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(venue.scoreTier.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(minWidth: scoreTileMinWidth, minHeight: scoreTileMinHeight)
            .background(venue.scoreTier.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(venue.neighborhood)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(localizedAttributeValue(venue.attributes.wifi.value), systemImage: "wifi")
                    Label(localizedAttributeValue(venue.attributes.outlets.value), systemImage: "powerplug")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
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
