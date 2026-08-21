import MapKit
import SwiftUI
import VenueKit

public struct CafeMapScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locationDenied) private var locationDenied
    @Bindable private var model: VenuesModel
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var selected: Venue?
    @State private var position: MapCameraPosition
    /// Camera region captured at gesture end (`.onMapCameraChange(.onEnd)`).
    /// Mid-gesture frames never touch state, so a pan composites existing
    /// annotation views instead of re-evaluating this body (brewdesk#54).
    @State private var visibleRegion: MKCoordinateRegion?

    public init(model: VenuesModel, savedVenues: SavedVenuesStore) {
        self.model = model
        self.savedVenues = savedVenues
        self._position = State(initialValue: .region(Self.region(lat: model.centerLat, lng: model.centerLng)))
    }

    public var body: some View {
        let plan = MapAnnotationPlanner.plan(
            venues: model.venues,
            region: visibleRegion ?? Self.region(lat: model.centerLat, lng: model.centerLng)
        )
        Map(position: $position) {
            UserAnnotation()
            annotations(for: plan)
            // A venue chosen from a dot, cluster zoom-in, or the shelf still
            // shows a full selected pin even when the plan has no pin for it.
            if let selected, !plan.containsVenue(id: selected.id) {
                Annotation("", coordinate: coordinate(of: selected)) {
                    pinButton(for: selected, isSelected: true)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            // Debounced re-planning: `.onEnd` keeps mid-gesture frames free of
            // state writes, and the hysteresis below skips re-plans while the
            // culling margin still covers the viewport — small pans composite
            // existing annotation views instead of diffing new ones.
            guard Self.needsReplan(from: visibleRegion, to: context.region) else { return }
            visibleRegion = context.region
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .top) { searchHeader }
        .safeAreaInset(edge: .bottom) { discoveryShelf }
        .overlay { loadStatus }
        // Frame-timing evidence seam (brewdesk#54); inert without the flag.
        .overlay(alignment: .bottomTrailing) {
            if MapFrameStatsHUD.isEnabled {
                MapFrameStatsHUD(annotationCount: plan.annotationCount)
                    .padding(.trailing, 8)
            }
        }
        .sheet(item: $selected) { venue in
            NavigationStack {
                VenueDetailScreen(venue: venue, savedVenues: savedVenues)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.centerLat) {
            position = .region(Self.region(lat: model.centerLat, lng: model.centerLng))
        }
        .onChange(of: model.centerLng) {
            position = .region(Self.region(lat: model.centerLat, lng: model.centerLng))
        }
    }

    // MARK: - Annotations (representation from MapAnnotationPlanner,
    // styling from MapAnnotationViews — see brewdesk#54/#55)

    @MapContentBuilder
    private func annotations(for plan: MapAnnotationPlan) -> some MapContent {
        switch plan {
        case .pins(let venues):
            ForEach(venues) { venue in
                Annotation("", coordinate: coordinate(of: venue)) {
                    pinButton(for: venue, isSelected: selected?.id == venue.id)
                }
            }
        case .dots(let venues):
            ForEach(venues) { venue in
                Annotation("", coordinate: coordinate(of: venue)) {
                    dotButton(for: venue)
                }
            }
        case .clusters(let clusters):
            ForEach(clusters) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    clusterButton(for: cluster)
                }
            }
        }
    }

    private func pinButton(for venue: Venue, isSelected: Bool) -> some View {
        Button {
            selected = venue
        } label: {
            VenueScorePin(venue: venue, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dotButton(for venue: Venue) -> some View {
        Button {
            selected = venue
        } label: {
            VenueScoreDot(venue: venue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood)")
    }

    /// Tapping a cluster zooms one representation step in on it.
    private func clusterButton(for cluster: VenueCluster) -> some View {
        Button {
            let span = visibleRegion?.span
                ?? MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            let zoomed = MKCoordinateRegion(
                center: cluster.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: span.latitudeDelta / 3,
                    longitudeDelta: span.longitudeDelta / 3
                )
            )
            if reduceMotion {
                position = .region(zoomed)
            } else {
                withAnimation(.snappy) { position = .region(zoomed) }
            }
        } label: {
            VenueClusterPill(cluster: cluster)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map-cluster")
        .accessibilityLabel("\(cluster.count) venues, best Work Fit \(cluster.bestScore)")
        .accessibilityHint("Zooms in to show them")
    }

    @ViewBuilder
    private var loadStatus: some View {
        switch model.phase {
        // `.idle` with nothing loaded (first paint, or a cancelled load) is
        // shown as loading — never a bare map with no explanation.
        case .idle where model.venues.isEmpty, .loading where model.venues.isEmpty:
            ProgressView("Finding work-friendly cafes…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("map-state-loading")
        // With snapshot rows on the map, failure is a banner in the header.
        case .failed where model.venues.isEmpty:
            ContentUnavailableView {
                Label("Cafe service unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Retry") { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("map-retry")
            }
            .padding()
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("map-state-error")
        default:
            EmptyView()
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cafes", text: $model.searchQuery)
                    .submitLabel(.search)
                    .onSubmit { model.submitSearch() }
                if !model.searchQuery.isEmpty {
                    Button {
                        model.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .brewDeskGlass(in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            HStack {
                Text(localizedWorkCafeCount(model.venues.count))
                    .font(.caption.bold())
                Spacer()
                Text("Scores show Work Fit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            DatasetStatStrip(model: model)

            if let state = model.snapshotBanner {
                SnapshotBanner(state: state) { model.retry() }
            }

            if model.isOutsideCoverage {
                Label("You're outside NYC — showing our NYC coverage.", systemImage: "mappin.slash")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .brewDeskGlass(in: Capsule())
                    .accessibilityIdentifier("coverage-banner")
            }

            if locationDenied {
                LocationDeniedBanner()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var discoveryShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)

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
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.venues.prefix(12)) { venue in
                            Button {
                                selected = venue
                                position = .region(
                                    MKCoordinateRegion(
                                        center: coordinate(of: venue),
                                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                                    )
                                )
                            } label: {
                                venueCard(venue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood)"
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 126)
            }
        }
        .padding(.vertical, 10)
        .brewDeskGlass(in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.15), radius: 14, y: -3)
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

    private func venueCard(_ venue: Venue) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(venue.scoreTier.color.opacity(0.14))
                VStack(spacing: 3) {
                    Text("\(venue.workScore)")
                        .font(.title2.monospacedDigit().bold())
                    Text("WORK FIT")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.5)
                }
                .foregroundStyle(venue.scoreTier.color)
            }
            .frame(width: 72, height: 82)

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
        }
        .padding(10)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 330 : 285, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .animation(reduceMotion ? nil : .snappy, value: selected?.id)
    }

    /// A new plan is needed once the camera leaves what the current plan's
    /// culling margin (`MapAnnotationPlanner.cullMargin`) already annotated:
    /// the center moved by more than a quarter span, or the zoom changed
    /// meaningfully. Anything less keeps the existing annotations untouched.
    static func needsReplan(from current: MKCoordinateRegion?, to next: MKCoordinateRegion) -> Bool {
        guard let current else { return true }
        let latMove = abs(next.center.latitude - current.center.latitude)
        let lngMove = abs(next.center.longitude - current.center.longitude)
        guard current.span.latitudeDelta > 0 else { return true }
        let spanRatio = next.span.latitudeDelta / current.span.latitudeDelta
        return latMove > current.span.latitudeDelta * 0.25
            || lngMove > current.span.longitudeDelta * 0.25
            || spanRatio < 0.75 || spanRatio > 1.33
    }

    private static func region(lat: Double, lng: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
    }

    private func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }
}
