import MapKit
import SwiftUI
import VenueKit

public struct CafeMapScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// The shelf's resting detent (brewdesk#76). Changes once per settled
    /// drag — never per frame — so this body stays out of mid-gesture frames
    /// (the brewdesk#54 invariant). Mid-drag state lives in the card itself.
    @State private var shelfDetent: ShelfDetent = .medium
    /// Backs the search field so map taps, shelf drags, Return, and the
    /// keyboard toolbar's Done button can all resign focus (brewdesk#87).
    @FocusState private var searchFocused: Bool
    /// Full map height, captured once per layout for the `.full` card height.
    @State private var mapHeight: CGFloat = 0
    /// Dynamic Type–aware estimates of the shelf card's height per detent, so
    /// map controls and attribution ride above the card the way detail
    /// content clears the action dock (same safe-area mechanism).
    @ScaledMetric(relativeTo: .caption) private var shelfChipRowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var shelfCardBlockHeight: CGFloat = 138

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
                // Any touch on the map — a tap or the start of a pan —
                // resigns the search field (brewdesk#87). `minimumDistance:
                // 0` fires on touch-down, and `simultaneousGesture` keeps it
                // from stealing the touch from pin/cluster buttons or the
                // other map gestures above.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in searchFocused = false }
                )
            }
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        // Compass, user-location button, and attribution stay clear of the
        // shelf card at its resting detent — scoped to the map subtree so the
        // card overlay below doesn't inherit (and stack on) its own clearance.
        .safeAreaPadding(.bottom, shelfClearance)
        // Frame-timing evidence seam (brewdesk#54); inert without the flag.
        // Inside the clearance so the HUD sits above the shelf card and its
        // taps (perf tests zero the counters by tapping it) still land.
        .overlay(alignment: .bottomTrailing) {
            if MapFrameStatsHUD.isEnabled {
                MapFrameStatsHUD(annotationCount: plan.annotationCount)
                    .padding(.trailing, 8)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            mapHeight = height
        }
        .safeAreaInset(edge: .top) { searchHeader }
        .overlay { loadStatus }
        // The honest bottom sheet (brewdesk#76): an in-tab overlay with real
        // detents — bottom-aligned to the tab content's safe area, so the tab
        // bar stays reachable at every detent (a `.sheet` would cover it).
        .overlay(alignment: .bottom) {
            DiscoveryShelfCard(
                model: model,
                detent: $shelfDetent,
                selectedID: selected?.id,
                fullHeight: max(320, mapHeight * 0.7)
            ) { venue in
                selected = venue
                position = .region(
                    MKCoordinateRegion(
                        center: coordinate(of: venue),
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    )
                )
            }
            // Dragging the shelf (resize or its own scroll content) also
            // resigns the search field (brewdesk#87). Applied at the call
            // site rather than inside `DiscoveryShelfCard` — its own
            // `minimumDistance: 8` resize gesture and any internal
            // scrolling both still recognize normally alongside this one.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in searchFocused = false }
            )
            .scrollDismissesKeyboard(.immediately)
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
                        .focused($searchFocused)
                        .onSubmit {
                            model.submitSearch()
                            searchFocused = false
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    searchFocused = false
                                }
                                .accessibilityIdentifier("search-done")
                            }
                        }
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

    /// Extra bottom safe area for the map subtree while the shelf rests at
    /// the current detent — how compass, user-location button, and attribution
    /// avoid the card, mirroring the detail dock's safe-area approach. Sized
    /// from Dynamic Type–scaled estimates of the card's intrinsic parts, and
    /// capped at the medium clearance for `.full` (the map is covered anyway).
    private var shelfClearance: CGFloat {
        let peek = shelfChipRowHeight + 56
        switch shelfDetent {
        case .peek: return peek
        case .medium, .full: return peek + shelfCardBlockHeight + 12
        }
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
