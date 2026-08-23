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
/// Drag state lives HERE, not on the map screen: mid-drag frames mutate only
/// this view's `dragOffset`, so the map's body — and the annotation planner —
/// never re-evaluates per frame (the brewdesk#54 invariant).
struct DiscoveryShelfCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: VenuesModel
    @Binding var detent: ShelfDetent
    let selectedID: String?
    /// Card height at `.full`, chosen by the map screen from its own geometry.
    let fullHeight: CGFloat
    let onVenueTap: (Venue) -> Void

    @State private var dragOffset: CGFloat = 0
    /// Shelf-card score tile scales with Dynamic Type instead of clipping in
    /// a fixed 72×82 frame (ui-review-2026-08-21 finding 7).
    @ScaledMetric(relativeTo: .title2) private var scoreTileMinWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .title2) private var scoreTileMinHeight: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            grabber
            chipRail
            if detent != .peek {
                venueContent
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: detent == .full ? fullHeight : nil, alignment: .top)
        .brewDeskGlass(in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.15), radius: 14, y: -3)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(resizeDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-discovery-shelf")
        .onAppear { detent = ShelfDetentMemory.session.last }
        .onChange(of: detent) { ShelfDetentMemory.session.last = detent }
        // A light tick when the shelf settles into a detent, or a filter
        // chip is toggled (brewdesk#75) — `.sensoryFeedback` already no-ops
        // under Reduce Motion.
        .sensoryFeedback(.selection, trigger: detent)
        .sensoryFeedback(.selection, trigger: model.laptopFriendlyOnly)
        .sensoryFeedback(.selection, trigger: model.minWifi)
        .sensoryFeedback(.selection, trigger: model.minOutlets)
        .sensoryFeedback(.selection, trigger: model.minSeating)
    }

    // MARK: - Resize

    /// The whole card resizes on a vertical drag (the inner rails claim
    /// horizontal drags and taps for themselves); the grabber is the visual
    /// promise plus the assistive-tech handle.
    private var grabber: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity, minHeight: 24)
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
                dragOffset = dampened(value.translation.height)
            }
            .onEnded { value in
                let target = ShelfDetent.resolve(
                    from: detent,
                    projectedTranslation: value.predictedEndTranslation.height
                )
                if reduceMotion {
                    dragOffset = 0
                    detent = target
                } else {
                    withAnimation(.snappy) {
                        dragOffset = 0
                        detent = target
                    }
                }
            }
    }

    /// Live feedback: collapse-direction drags track the finger; expand
    /// drags lift with resistance (the card grows on release, not mid-drag);
    /// drags past an end detent rubber-band.
    private func dampened(_ translation: CGFloat) -> CGFloat {
        let collapsing = translation > 0
        let hasRoom = collapsing ? detent.collapsed != nil : detent.expanded != nil
        guard hasRoom else { return translation * 0.10 }
        return translation * (collapsing ? 0.85 : 0.25)
    }

    private func setDetent(_ target: ShelfDetent) {
        if reduceMotion {
            detent = target
        } else {
            withAnimation(.snappy) { detent = target }
        }
    }

    // MARK: - Content

    private var chipRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: "Laptop friendly",
                    symbol: "laptopcomputer",
                    selected: model.laptopFriendlyOnly
                ) {
                    model.laptopFriendlyOnly.toggle()
                }
                filterChip(
                    title: model.minWifi == .fast ? "Fast Wi-Fi" : "Wi-Fi",
                    symbol: "wifi",
                    selected: model.minWifi != nil
                ) {
                    model.cycleWifiMinimum()
                }
                filterChip(
                    title: model.minOutlets == .plenty ? "Plenty of outlets" : "Outlets",
                    symbol: "powerplug.fill",
                    selected: model.minOutlets != nil
                ) {
                    model.cycleOutletMinimum()
                }
                filterChip(
                    title: "Seating",
                    symbol: "chair.lounge",
                    selected: model.minSeating != nil
                ) {
                    model.cycleSeatingMinimum()
                }
                if model.venueTypesAvailable {
                    ForEach(VenueTypeFilter.allCases, id: \.rawValue) { type in
                        filterChip(
                            title: LocalizedStringKey(type.rawValue),
                            symbol: Self.venueTypeSymbol(type),
                            selected: model.venueType == type
                        ) {
                            model.venueType = model.venueType == type ? nil : type
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var venueContent: some View {
        if model.venues.isEmpty {
            // Only a *loaded* empty result is an empty state; while loading
            // or failed the overlay owns the message and the shelf stays quiet.
            if model.phase == .loaded {
                ContentUnavailableView {
                    Label("No cafes in this view", systemImage: "cup.and.saucer")
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
        } else if detent == .full {
            fullList
        } else {
            horizontalRail
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

    private static func venueTypeSymbol(_ type: VenueTypeFilter) -> String {
        switch type {
        case .cafe: "cup.and.saucer.fill"
        case .park: "tree.fill"
        case .library: "books.vertical.fill"
        case .mall: "building.2.fill"
        case .other: "mappin"
        }
    }

    private func filterChip(
        title: LocalizedStringKey,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(selected ? BrewDeskPalette.roast : Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "On" : "Off")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                ProvenanceStamp(attributes: venue.attributes)
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
