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
    /// Camera region recovered after a gesture settles (see `scheduleReplan`).
    /// Mid-gesture frames never touch state, so a pan composites existing
    /// annotation views instead of re-evaluating this body (brewdesk#54).
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var replanTask: Task<Void, Never>?
    /// Shelf-card score tile scales with Dynamic Type instead of clipping in
    /// a fixed 72×82 frame (ui-review-2026-08-21 finding 7).
    @ScaledMetric(relativeTo: .title2) private var scoreTileMinWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .title2) private var scoreTileMinHeight: CGFloat = 82

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
        // Camera tracking WITHOUT `.onMapCameraChange`: measured on-simulator
        // (brewdesk#54), merely attaching that modifier cost ~1.5–2% of frame
        // time to per-frame camera bookkeeping. Instead the camera region is
        // recovered on demand — a gesture ending schedules one debounced
        // `MapProxy` corner conversion after momentum settles, and
        // programmatic moves (cluster zoom, recenter) write the region they
        // already know. Mid-gesture frames never touch SwiftUI state.
        MapReader { proxy in
            GeometryReader { geometry in
                Map(position: $position) {
                    UserAnnotation()
                    annotations(for: plan)
                    // A venue chosen from a dot, cluster zoom-in, or the shelf
                    // still shows a full selected pin even when the plan has
                    // no pin for it.
                    if let selected, !plan.containsVenue(id: selected.id) {
                        Annotation("", coordinate: coordinate(of: selected)) {
                            pinButton(for: selected, isSelected: true)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onEnded { _ in scheduleReplan(proxy: proxy, size: geometry.size) }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onEnded { _ in scheduleReplan(proxy: proxy, size: geometry.size) }
                )
                // Built-in double-tap zoom has no drag or magnify phase.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { scheduleReplan(proxy: proxy, size: geometry.size) }
                )
            }
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
            // At medium detent a scroll gesture must scroll the detail content
            // (clearing the action dock) rather than resize the sheet first —
            // the dock occluded the photo strip with no way to scroll it into
            // view (ui-review-2026-08-21 finding 6).
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: model.centerLat) {
            position = .region(Self.region(lat: model.centerLat, lng: model.centerLng))
            visibleRegion = Self.region(lat: model.centerLat, lng: model.centerLng)
        }
        .onChange(of: model.centerLng) {
            position = .region(Self.region(lat: model.centerLat, lng: model.centerLng))
            visibleRegion = Self.region(lat: model.centerLat, lng: model.centerLng)
        }
        .onDisappear { replanTask?.cancel() }
    }

    // MARK: - Camera-driven re-planning

    /// One re-plan per settled gesture. A fling keeps the camera decelerating
    /// long after touch-up, and re-planning mid-animation is itself a visible
    /// hitch — so poll the camera center (two cheap point conversions) until
    /// two consecutive readings match, then re-plan at rest. Hysteresis skips
    /// the update entirely while the culling margin still covers the viewport,
    /// so small pans and taps never rebuild annotations.
    private func scheduleReplan(proxy: MapProxy, size: CGSize) {
        replanTask?.cancel()
        replanTask = Task {
            let midpoint = CGPoint(x: size.width / 2, y: size.height / 2)
            var previous: CLLocationCoordinate2D?
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard let center = proxy.convert(midpoint, from: .local) else { return }
                if let previous,
                   abs(previous.latitude - center.latitude) < 1e-7,
                   abs(previous.longitude - center.longitude) < 1e-7 {
                    break
                }
                previous = center
            }
            guard !Task.isCancelled, let region = Self.cameraRegion(proxy: proxy, size: size) else { return }
            guard Self.needsReplan(from: visibleRegion, to: region) else { return }
            visibleRegion = region
        }
    }

    /// The region between the map view's corners, via `MapProxy`.
    private static func cameraRegion(proxy: MapProxy, size: CGSize) -> MKCoordinateRegion? {
        guard size.width > 0, size.height > 0,
              let topLeft = proxy.convert(.zero, from: .local),
              let bottomRight = proxy.convert(CGPoint(x: size.width, y: size.height), from: .local)
        else { return nil }
        let latDelta = abs(topLeft.latitude - bottomRight.latitude)
        let lngDelta = abs(bottomRight.longitude - topLeft.longitude)
        guard latDelta > 0, lngDelta > 0 else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                longitude: (topLeft.longitude + bottomRight.longitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
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
            // Programmatic move: the target region is known, so re-plan
            // directly — no camera observation needed.
            visibleRegion = zoomed
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

    /// One glass card for search + count + hint + stat strip: bare text
    /// painted on the map collided with map labels in light mode and vanished
    /// dark-on-dark (ui-review-2026-08-21 finding 2). Banners dock directly
    /// beneath the card as sibling rows (finding 15's grouping).
    private var searchHeader: some View {
        VStack(spacing: 8) {
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
                .frame(minHeight: 44)
                .background(.thinMaterial, in: Capsule())

                HStack {
                    Text(localizedWorkCafeCount(model.venues.count))
                        .font(.caption.bold())
                    Spacer()
                    Text("Scores show Work Fit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)

                DatasetStatStrip(model: model)
            }
            .padding(10)
            .brewDeskGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("map-header-card")

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
                // No fixed shelf height: cards reflow vertically at
                // accessibility sizes instead of clipping (finding 7).
                .fixedSize(horizontal: false, vertical: true)
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

    /// Shelf card. No fixed frames on the score tile and no hard-coded 8pt
    /// label: at accessibility sizes the old 72×82 tile clipped to "7 WOR"
    /// (ui-review-2026-08-21 finding 7). The tile now scales with the score's
    /// text style and the caption rides Dynamic Type via `.caption2`.
    private func venueCard(_ venue: Venue) -> some View {
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
        }
        .padding(10)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 330 : 285, alignment: .leading)
        .background(BrewDeskPalette.surface, in: RoundedRectangle(cornerRadius: 20))
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
