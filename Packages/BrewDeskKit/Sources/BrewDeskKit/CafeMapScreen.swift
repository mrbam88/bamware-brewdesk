import MapKit
import SwiftUI
import UIKit
import VenueKit

public struct CafeMapScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locationDenied) private var locationDenied
    @Environment(\.locationUndetermined) private var locationUndetermined
    @Environment(\.requestLocationAccess) private var requestLocationAccess
    @Environment(\.launchEnvironment) private var launchEnvironment
    @Environment(\.openURL) private var openURL
    @Bindable private var model: VenuesModel
    @Bindable private var savedVenues: SavedVenuesStore
    /// Transport for the Apple feature card's "Suggest this café" action
    /// (bd#182). Defaults to the documented no-op stub — see
    /// `CafeSuggestionContract.swift` for why no real endpoint exists yet.
    private let cafeSuggesting: any CafeSuggesting
    @State private var selected: Venue?
    /// The Apple base-map POI label currently selected via `Map`'s own
    /// selection binding (bd#182) — distinct from `selected`, which is only
    /// ever one of OUR venues. Reset to `nil` once handled so a repeat tap
    /// on the same label still fires `onChange`.
    @State private var appleFeatureSelection: MapFeature?
    /// Drives `AppleFeatureCard`'s sheet: set once a selected Apple feature
    /// (or a tapped gap-fill marker) fails to match one of our venues.
    @State private var appleFeatureCandidate: AppleCafeCandidate?
    /// Best-effort `MKMapItem` for the current `appleFeatureCandidate`,
    /// resolved async (`AppleCafeDetailsResolver`) so Directions can hand
    /// Maps a precise place once it lands; `nil` renders and still works
    /// (Directions falls back to a plain coordinate placemark).
    @State private var resolvedAppleMapItem: MKMapItem?
    /// Grey "unverified" markers from the feature-flagged gap-fill
    /// (`AppleGapFillService`, default OFF) — never mixed into `plan`'s
    /// scored pins/dots/clusters, recomputed on every camera settle.
    @State private var appleGapFillMarkers: [AppleUnverifiedPOI] = []
    @State private var gapFillTask: Task<Void, Never>?
    /// brewdesk#117: forces the detail sheet to open at `.large` — see the
    /// `.sheet` modifier below for why.
    @State private var detailDetent: PresentationDetent = .large
    @State private var position: MapCameraPosition
    /// Camera region recovered after a gesture settles (see `scheduleReplan`).
    /// Mid-gesture frames never touch state, so a pan composites existing
    /// annotation views instead of re-evaluating this body (brewdesk#54).
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var replanTask: Task<Void, Never>?
    /// True for the duration of a drag or pinch on the map (see the
    /// `DragGesture`/`MagnifyGesture` handlers below) — brewdesk#158's
    /// search-fit camera move must never fight a gesture the user's finger
    /// is still driving.
    ///
    /// Held in a plain reference box, NOT as observed `@State` value: the
    /// gesture `onChanged` handlers fire every frame of a pan, and the
    /// brewdesk#54 invariant is that mid-gesture frames never invalidate this
    /// body (each evaluation re-runs the annotation planner).
    @State private var mapInteraction = MapInteractionFlag()
    /// Debounced search→camera fit (brewdesk#158). Cancelled and
    /// rescheduled on every keystroke; only the settled query moves the
    /// camera.
    @State private var searchFitTask: Task<Void, Never>?
    /// The shelf's resting detent (brewdesk#76). Changes once per settled
    /// drag — never per frame — so this body stays out of mid-gesture frames
    /// (the brewdesk#54 invariant). Mid-drag state lives in the card itself.
    @State private var shelfDetent: ShelfDetent = .medium
    /// Backs the search field so map taps, shelf drags, Return, and the
    /// keyboard toolbar's Done button can all resign focus (brewdesk#87).
    @FocusState private var searchFocused: Bool
    /// Full map height, captured once per layout for the `.full` card height.
    @State private var mapHeight: CGFloat = 0
    /// Full map size, captured alongside `mapHeight` (bd#209) — the
    /// annotation planner needs both dimensions to convert a venue's
    /// coordinate into a screen point for its collision-free layout pass.
    @State private var mapSize: CGSize = .zero
    /// Memoizes `MapAnnotationPlanner.plan(...)` (bd#209). `body` here
    /// re-evaluates on every state change this screen has — a locate-button
    /// pulse frame, a shelf-detent drag, search focus — not just a camera
    /// settle (the brewdesk#54 invariant only promises mid-GESTURE frames
    /// skip it; SwiftUI still re-runs `body` for plenty else). #204/#208's
    /// planner was cheap enough that recomputing it on every one of those
    /// renders was invisible; bd#209's collision-aware layout is not, so an
    /// unrelated re-render now reuses the last plan instead of rebuilding
    /// it. A plain reference box, not `@State` itself, so writing the cache
    /// during body's own evaluation can never trigger a further
    /// invalidation — the same reasoning `mapInteraction` above documents.
    @State private var planCache = PlanCacheBox()
    /// Dynamic Type–aware estimates of the shelf card's height per detent, so
    /// map controls and attribution ride above the card the way detail
    /// content clears the action dock (same safe-area mechanism).
    @ScaledMetric(relativeTo: .caption) private var shelfChipRowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var shelfCardBlockHeight: CGFloat = 138
    /// True right after `centerOnUser()` lands and no pan/zoom/selection has
    /// moved the camera away since (bd#185) — drives `LocateMeButton`'s
    /// filled/"tracking" symbol. A plain `@State` flip, not a real MapKit
    /// follow mode: see `centerOnUser`'s doc comment for why this screen
    /// stopped relying on the framework's own `.userLocation` tracking.
    @State private var isTrackingUserLocation = false
    /// Scale driving `LocateMeButton`'s tap pulse (bd#185); 1 at rest.
    @State private var locateButtonScale: CGFloat = 1
    /// Set when the locate button is tapped while authorization is still
    /// `.notDetermined` (or before a first location fix has replaced the
    /// Union Square fallback in `model.centerLat/Lng`) — the next
    /// `model.centerLat`/`centerLng` change then centers automatically
    /// instead of applying the plain, unanimated default-span recenter
    /// those `onChange` handlers otherwise apply. Cleared once consumed, or
    /// if the user pans/zooms/selects before a fix arrives (bd#185).
    @State private var pendingLocateAfterPermission = false
    /// Drives the denied-state alert (bd#185); `LocationDeniedBanner`
    /// already offers the same "Open Settings" affordance in the header,
    /// this is the same action reachable from the map control itself.
    @State private var showLocationDeniedAlert = false
    /// bd#192: true from a "Search this area" tap until `model.phase`
    /// leaves `.loading` — drives the pill's inline progress state. Purely
    /// a UI affordance; the fetch itself is the same `model.request`
    /// pipeline every other viewport change already uses.
    @State private var isSearchingThisArea = false
    /// bd#192: polls `model.phase` back to `false` once the tap's own fetch
    /// leaves `.loading` — NOT a `.onChange(of: model.phase)` handler.
    /// `ScenarioVenueService` (every UI-test fixture) answers with no
    /// artificial delay, so a `.loading → .loaded` round trip can complete
    /// inside one SwiftUI render pass; `onChange` only fires by comparing
    /// the last RENDERED value to the next one; and re-fetches this fast
    /// never render an intermediate `.loading` frame at all, so `onChange`
    /// never observes a change and the flag would stay stuck true forever.
    /// Reading `model.phase` directly, each poll, sidesteps that
    /// coalescing entirely — a fetch that already finished by the first
    /// poll clears the flag immediately instead of waiting on an event
    /// that already happened.
    @State private var searchAreaFetchTask: Task<Void, Never>?

    public init(
        model: VenuesModel,
        savedVenues: SavedVenuesStore,
        cafeSuggesting: any CafeSuggesting = NullCafeSuggestionClient()
    ) {
        self.model = model
        self.savedVenues = savedVenues
        self.cafeSuggesting = cafeSuggesting
        self._position = State(initialValue: .region(Self.region(lat: model.centerLat, lng: model.centerLng)))
    }

    public var body: some View {
        let plan = cachedPlan()
        // bd#192: purely derived from state already tracked elsewhere —
        // `isSearchingThisArea` keeps the pill (with its progress state) up
        // through the tap's own fetch, and once that clears, the pill's
        // visibility falls straight out of comparing the settled
        // `visibleRegion` against what `model` actually last queried. No
        // separate "hide after fetch" flag: `searchThisArea()` updates
        // `model`'s center/radius to match the region it fetched for, so
        // the comparison naturally goes false the moment that lands.
        // bd#200: a text search already re-queries city-wide on its own —
        // the "Search this area" pill (a LOCAL viewport re-fetch) would be a
        // confusing second, unrelated affordance while one's in flight.
        let showSearchAreaPill = model.searchQuery.isEmpty && (isSearchingThisArea || visibleRegion.map {
            Self.needsSearchAreaPill(
                loadedCenterLat: model.centerLat,
                loadedCenterLng: model.centerLng,
                loadedRadiusM: model.radiusM,
                visibleRegion: $0
            )
        } == true)
        // Camera tracking (brewdesk#54 / PR #61): the region is recovered on
        // demand — a gesture ending schedules one debounced `MapProxy` corner
        // conversion after momentum settles, and programmatic moves (cluster
        // zoom, recenter) write the region they already know. Mid-gesture
        // frames never touch SwiftUI state.
        //
        // PR #61 measured "merely attaching `.onMapCameraChange` ≈ +1.5–2%
        // hitch time" and left it off. brewdesk#157 re-adds it at
        // `frequency: .onEnd` (below) because the locate control (bd#185:
        // now a custom `LocateMeButton`, originally the stock
        // `MapUserLocationButton`) moves the camera with no gesture at all,
        // so nothing else can refresh `visibleRegion` after a locate tap.
        // Re-measured 2026-09-17 on the
        // same harness (Release, iPhone 17 Pro Max sim, dot zoom): baseline
        // hitchRatio 0.083–0.115 without the modifier, 0.067–0.084 with it —
        // inside run-to-run noise. If `MapPerformanceUITests` ever regresses,
        // this callback is the first suspect.
        MapReader { proxy in
            GeometryReader { geometry in
                // `selection` (bd#182) binds ONLY Apple's own base-map POI
                // labels — our pins/dots/clusters keep their existing
                // Button-driven `selected` flow untouched, so this is a
                // second, independent selection channel, not a replacement.
                Map(position: $position, selection: $appleFeatureSelection) {
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
                    // Gap-fill (bd#182, feature-flagged, default OFF): grey
                    // "unverified" Apple POIs shown only while the region is
                    // thin on our own pins. Never part of `plan` — these
                    // never compete with or get counted as scored venues.
                    gapFillAnnotations
                }
                // Apple's base-map labels are restricted to food/drink
                // categories (bd#182) — the only ones this screen makes
                // selectable/relevant; every other Apple POI label (transit,
                // parks, shops, …) stays off the map entirely rather than
                // being selectable-but-ignored.
                .mapStyle(.standard(pointsOfInterest: .including(Self.selectablePointsOfInterest)))
                // Suppresses Apple's own callout bubble: our own
                // `AppleFeatureCard` sheet (driven by the `onChange` below)
                // is the single source of truth for what a selected feature
                // looks like, so the system presentation would otherwise
                // double up on it. A non-empty `Marker` still highlights the
                // tapped label on the map itself while our sheet is up.
                .mapFeatureSelectionContent { feature in
                    Marker(feature.title ?? "", coordinate: feature.coordinate)
                }
                .onChange(of: appleFeatureSelection) { _, newValue in
                    handleAppleFeatureSelection(newValue)
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    refreshVisibleRegion(context.region)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            mapInteraction.isActive = true
                            stopTrackingUserLocation()
                        }
                        .onEnded { _ in
                            mapInteraction.isActive = false
                            scheduleReplan(proxy: proxy, size: geometry.size)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { _ in
                            mapInteraction.isActive = true
                            stopTrackingUserLocation()
                        }
                        .onEnded { _ in
                            mapInteraction.isActive = false
                            scheduleReplan(proxy: proxy, size: geometry.size)
                        }
                )
                // Built-in double-tap zoom has no drag or magnify phase.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            stopTrackingUserLocation()
                            scheduleReplan(proxy: proxy, size: geometry.size)
                        }
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
                // brewdesk#157: a search clear, filter change, or any other
                // venue-list change must never ride on a `visibleRegion` that
                // was captured for a different list. No gesture accompanies
                // this, so there's no settle to wait for — resync straight
                // from the current camera image; if the proxy can't convert
                // yet, `MapAnnotationPlanner`'s own un-culled fallback covers
                // the render in the meantime.
                .onChange(of: model.venues) { _, _ in
                    if let region = Self.cameraRegion(proxy: proxy, size: geometry.size) {
                        visibleRegion = region
                    }
                    // bd#200: the citywide server search lands asynchronously,
                    // after `scheduleSearchFit`'s own 260ms debounce may
                    // already have fit the camera to whatever LOCAL results
                    // existed at that moment (or fit nothing at all, empty).
                    // Re-evaluate the fit whenever the result set itself
                    // changes while a search is still settled, so a
                    // server-only match still pulls the camera onto it
                    // instead of leaving the user staring at an empty local
                    // viewport. A no-op (via `scheduleSearchFit`'s own
                    // guards) for an empty query, a stale query, or a
                    // venues change with no search active at all.
                    scheduleSearchFit(query: model.searchQuery)
                }
            }
        }
        .mapControls {
            MapCompass()
        }
        // Compass and attribution stay clear of the shelf card at its
        // resting detent — scoped to the map subtree so the card overlay
        // below doesn't inherit (and stack on) its own clearance.
        .safeAreaPadding(.bottom, shelfClearance)
        // UI-test seam (bd#185): MapKit's camera has no accessibility
        // surface XCUITest can read, so this invisible element exposes the
        // settled camera center as "lat,lng" — `MapLocateButtonUITests`
        // reads it to confirm a tap actually moved the map, rather than
        // trusting animation timing alone.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("map-camera-center")
                .accessibilityLabel("Map camera center")
                .accessibilityValue(cameraCenterAccessibilityValue)
                .allowsHitTesting(false)
        }
        // bd#192 UI-test seam: exposes what `model` actually last queried
        // (center + radius), distinct from `map-camera-center`'s live
        // camera position — `MapSearchAreaUITests` reads this to prove a
        // "Search this area" tap dispatched a NEW viewport query rather
        // than just moving the camera. Scenario fixtures (`fixtureOK`, …)
        // return the same venues regardless of query params, so this is
        // the only observable proof of a re-query in that harness.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("map-last-query")
                .accessibilityLabel("Map last query")
                .accessibilityValue(lastQueryAccessibilityValue)
                .allowsHitTesting(false)
        }
        // bd#192: the "Search this area" pill — top-center of the map,
        // clear of the search header above it (attached here, before the
        // outer `.safeAreaInset(edge: .top)` below reserves that header's
        // space, so this aligns to the MAP's own top edge once that inset
        // pushes it down, not the screen's absolute top).
        .overlay(alignment: .top) {
            if showSearchAreaPill {
                SearchAreaPill(isSearching: isSearchingThisArea, action: searchThisArea)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showSearchAreaPill)
        .alert("Location Access Needed", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on Location Services for BrewDesk in Settings to center the map on where you are.")
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            mapHeight = size.height
            mapSize = size
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
                fullHeight: max(320, mapHeight * 0.7),
                isSearchFocused: searchFocused
            ) { venue in
                selected = venue
                stopTrackingUserLocation()
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
        // The locate button (bd#185, replacing the stock
        // `MapUserLocationButton()` — see its own doc comment for why) and,
        // beneath it, the frame-timing evidence seam (brewdesk#54; inert
        // without `-UITestFrameStats`). Deliberately chained AFTER the
        // `DiscoveryShelfCard` overlay above, not alongside the compass in
        // `.mapControls` or in an earlier overlay: a SwiftUI `.overlay`
        // composites on top of everything already attached to the view, so
        // an EARLIER overlay here (where this block used to live, before
        // `.safeAreaPadding(.bottom, shelfClearance)`'s clearance was
        // trusted to be enough on its own) still rendered BELOW the shelf
        // card's own later overlay — invisible at any detent that reaches
        // that corner, and a tap there landed on whatever shelf content was
        // underneath instead (reproduced with `MapLocateButtonUITests`: a
        // tap on the identifier's own reported frame opened a venue's detail
        // sheet). `shelfClearance` still reserves the vertical space; this
        // fixes who draws on top of it.
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if MapFrameStatsHUD.isEnabled {
                    MapFrameStatsHUD(annotationCount: plan.annotationCount)
                }
                LocateMeButton(
                    isTracking: isTrackingUserLocation,
                    isDenied: locationDenied,
                    pulseScale: locateButtonScale,
                    action: handleLocateTap
                )
            }
            .padding(.trailing, 12)
            .padding(.bottom, shelfClearance)
        }
        .sheet(item: $selected) { venue in
            NavigationStack {
                VenueDetailScreen(venue: venue, savedVenues: savedVenues)
                    // brewdesk#117: `.presentationContentInteraction(.scrolls)`
                    // means swipes scroll the detail content — the drag
                    // indicator is the only gesture path out, so the sheet
                    // gets an explicit Close affordance too (and tests use it).
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                selected = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("detail-close")
                        }
                    }
            }
            // brewdesk#117: defaults to `.large` (an explicit `selection`,
            // not just detent order — SwiftUI opens at the first detent in
            // the set otherwise, i.e. `.medium`). Detail was never laid out
            // for half the screen: it was always a full push before this
            // ticket made the map/shelf sheet its only route from Spots, and
            // `.medium` crowded real content into real a11y-audit failures
            // (clipped text, sub-44pt hit targets) that a full push never
            // hit. `.medium` stays reachable by dragging down — this only
            // changes where the sheet opens.
            .presentationDetents([.medium, .large], selection: $detailDetent)
            .presentationDragIndicator(.visible)
            // At medium detent a scroll gesture must scroll the detail content
            // (clearing the action dock) rather than resize the sheet first —
            // the dock occluded the photo strip with no way to scroll it into
            // view (ui-review-2026-08-21 finding 6).
            .presentationContentInteraction(.scrolls)
        }
        // brewdesk#117: each fresh selection opens full-height, regardless
        // of whatever detent a previous venue's sheet was left at.
        .onChange(of: selected) { _, newValue in
            if newValue != nil { detailDetent = .large }
        }
        // brewdesk#158: a settled, non-empty search must move the camera to
        // its results (critique finding 9 — a one-result search left the
        // map showing an unrelated neighborhood with no pin in view).
        .onChange(of: model.searchQuery) { _, newValue in
            scheduleSearchFit(query: newValue)
        }
        .onChange(of: model.centerLat) {
            applyCenterChange()
        }
        .onChange(of: model.centerLng) {
            applyCenterChange()
        }
        // Gap-fill (bd#182): recomputed on every settled camera region —
        // the same signal `MapAnnotationPlanner` re-plans from — never
        // during a mid-gesture frame (brewdesk#54 invariant: `visibleRegion`
        // itself only ever updates post-settle). `MKCoordinateRegion` isn't
        // Equatable, so `onChange` watches a small Equatable snapshot of it
        // instead of the region itself.
        .onChange(of: visibleRegion.map(RegionSnapshot.init)) { _, _ in
            scheduleGapFill(region: visibleRegion)
        }
        .sheet(item: $appleFeatureCandidate, onDismiss: {
            appleFeatureSelection = nil
            resolvedAppleMapItem = nil
        }) { candidate in
            AppleFeatureCard(
                candidate: candidate,
                referenceCoordinate: CLLocationCoordinate2D(latitude: model.centerLat, longitude: model.centerLng),
                resolvedMapItem: resolvedAppleMapItem,
                suggesting: cafeSuggesting
            )
            .presentationDetents([.height(260), .medium])
            .presentationDragIndicator(.visible)
        }
        // bd#182 UI-test seam: Apple's base-map labels render in the
        // platform map layer, not the accessibility tree, so
        // `MapFeatureCardUITests` cannot reliably tap a real one on the
        // simulator. A launch fixture opens the card directly so its
        // rendering and actions are still exercised end to end.
        .task {
            if let fixture = launchEnvironment.appleFeatureFixture {
                appleFeatureCandidate = AppleCafeCandidate(
                    name: fixture.name,
                    coordinate: CLLocationCoordinate2D(latitude: fixture.lat, longitude: fixture.lng)
                )
            }
        }
        .onDisappear {
            replanTask?.cancel()
            searchFitTask?.cancel()
            gapFillTask?.cancel()
            searchAreaFetchTask?.cancel()
        }
    }

    // MARK: - Spoken labels (brewdesk#159)

    /// Pin label contract: "<name>, <score phrase>, <neighborhood>". UI tests
    /// match on the "<name>," prefix; VoiceOver must never read the engine's
    /// neutral fallback number for a venue nobody has checked.
    static func pinLabel(for venue: Venue) -> String {
        let score = venue.isObserved ? "Work Fit \(venue.workScore)" : "not checked yet"
        return "\(venue.name), \(score), \(venue.neighborhood)"
    }

    /// bd#204: deliberately never mentions a score, even for a cell with
    /// observed venues — the old wording ("best Work Fit N") is exactly the
    /// score-shaped language that made Bilal read a cluster count as an
    /// out-of-range score. A cluster is a "how many, go zoom in" affordance,
    /// never a quality signal.
    static func clusterLabel(for cluster: VenueCluster) -> String {
        let noun = cluster.count == 1 ? "café" : "cafés"
        return "\(cluster.count) \(noun) in this area. Double-tap to zoom in."
    }

    // MARK: - Search-driven camera fit (brewdesk#158)

    /// Cancels any pending fit and, for a non-empty query, schedules one
    /// past `VenuesModel.scheduleSearchApplication`'s own ~200ms debounce
    /// so `model.venues` already reflects the settled search by the time
    /// this reads it. Clearing the query (or narrowing it to blank) simply
    /// cancels — no move, camera stays put, matching the ticket's scope.
    private func scheduleSearchFit(query: String) {
        searchFitTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchFitTask = Task {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            // Superseded by further typing, or the user is mid-gesture —
            // never yank the camera out from under a drag/pinch in flight.
            guard model.searchQuery == query, !mapInteraction.isActive else { return }
            let results = model.venues
            guard !results.isEmpty,
                  let region = Self.searchFitRegion(for: results, mapHeight: mapHeight, shelfClearance: shelfClearance)
            else { return }
            // Programmatic move: the target region is already known, so
            // re-plan pins for it directly rather than waiting on a camera
            // settle (same pattern as the cluster-zoom handler above).
            visibleRegion = region
            stopTrackingUserLocation()
            if reduceMotion {
                position = .region(region)
            } else {
                withAnimation(.snappy) { position = .region(region) }
            }
        }
    }

    /// The camera region that fits `results`: a single result centers at
    /// neighborhood zoom (the same span `DiscoveryShelfCard`'s selection
    /// callback uses); several results fit their bounding box with padding.
    /// The fitted box is biased north by half of `shelfClearance`'s share of
    /// `mapHeight` so a southerly result still lands above the shelf card
    /// rather than behind it.
    static func searchFitRegion(
        for results: [Venue], mapHeight: CGFloat, shelfClearance: CGFloat
    ) -> MKCoordinateRegion? {
        guard let first = results.first else { return nil }
        var minLat = first.lat, maxLat = first.lat
        var minLng = first.lng, maxLng = first.lng
        for venue in results.dropFirst() {
            minLat = min(minLat, venue.lat)
            maxLat = max(maxLat, venue.lat)
            minLng = min(minLng, venue.lng)
            maxLng = max(maxLng, venue.lng)
        }

        let neighborhoodZoomSpan = 0.012
        let paddingMultiplier = 1.6
        let paddedLatSpan = max((maxLat - minLat) * paddingMultiplier, neighborhoodZoomSpan)
        let paddedLngSpan = max((maxLng - minLng) * paddingMultiplier, neighborhoodZoomSpan)

        let shelfFraction: Double
        if mapHeight > 0, shelfClearance > 0, shelfClearance < mapHeight {
            shelfFraction = Double(shelfClearance / mapHeight)
        } else {
            shelfFraction = 0
        }
        let latitudeDelta = shelfFraction < 1 ? paddedLatSpan / (1 - shelfFraction) : paddedLatSpan
        // Half the reserved gap shifts the geometric center south so the
        // results — which stay at their true latitude — render in the
        // northern (visible, non-shelf-covered) part of the map.
        let latitudeShift = (shelfFraction / 2) * latitudeDelta

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2 - latitudeShift,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: paddedLngSpan)
        )
    }

    // MARK: - Locate me (bd#185)

    /// Handles a `LocateMeButton` tap for the current permission state.
    /// Denied/restricted never touches the camera — it only offers the
    /// Settings alert, matching `LocationDeniedBanner`'s existing affordance
    /// rather than doing nothing silently (the original bug report).
    private func handleLocateTap() {
        // bd#192: locate-me is one of the two moves that refetch without
        // the "Search this area" pill (the other is the very first load) —
        // never leave the pill's own progress state stuck on if it was
        // mid-tap when the user reached for locate-me instead.
        searchAreaFetchTask?.cancel()
        isSearchingThisArea = false
        if locationDenied {
            showLocationDeniedAlert = true
            return
        }
        if locationUndetermined {
            // No coordinate to center on yet — ask, then let
            // `applyCenterChange()` finish the job once a fix lands.
            pendingLocateAfterPermission = true
            requestLocationAccess?()
            return
        }
        // Already authorized: center on whatever `model.centerLat/Lng`
        // holds right now (the Union Square fallback if no fix has arrived
        // yet), and also arm `pendingLocateAfterPermission` so a real fix
        // that lands moments later self-corrects the camera instead of
        // leaving it on the fallback silently.
        pendingLocateAfterPermission = true
        centerOnUser()
    }

    /// Animates the camera to `model.centerLat/Lng` at a walking zoom, with
    /// a short pulse + filled/"tracking" symbol on the locate button.
    ///
    /// Reuses `model`'s center rather than reading Core Location a second
    /// time here: `model.centerLat/Lng` is the exact coordinate
    /// `DiscoveryRootView` already derived from `LocationService.location`
    /// (`updateCenterIfNeeded`), so this stays the single source of truth
    /// for "where the user is" instead of introducing a second one.
    ///
    /// Diagnosis (bd#185): the stock `MapUserLocationButton()` drives the
    /// map's own OS-managed `.userLocation` follow mode by writing through
    /// the `position` binding internally. This screen already had two
    /// `onChange(of: model.centerLat/Lng)` handlers (now folded into
    /// `applyCenterChange()`) and a shelf-selection callback that overwrite
    /// `position` with a plain `.region(...)` case — any one of those firing
    /// after the stock button engaged tracking would silently cancel it,
    /// which reads to a user as "I tapped Locate and nothing happened" with
    /// no error, no log, nothing to grep for. A fully custom button that
    /// only ever writes `.region(...)` itself — never depending on a
    /// framework-owned tracking mode another handler could clobber — removes
    /// that failure mode outright rather than trying to sequence around it.
    private func centerOnUser() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: model.centerLat, longitude: model.centerLng),
            span: MKCoordinateSpan(latitudeDelta: Self.locateZoomSpan, longitudeDelta: Self.locateZoomSpan)
        )
        visibleRegion = region
        // bd#192: locate-me "refetches around the user" per the ticket —
        // the center is already `model.centerLat/Lng` (this IS the user),
        // so only the radius actually changes here, from whatever the last
        // viewport query used to the walking-zoom radius this camera move
        // lands on. Keeps the pill's own comparison in sync too: without
        // this, a locate tap coming from a much-wider or much-tighter last
        // query would leave `needsSearchAreaPill` true and the pill would
        // reappear right after a locate move, which is the one thing the
        // ticket says must never happen.
        //
        // bd#198: `model.centerOnUser`, NOT `model.updateViewport` — the
        // latter would mark the result `.exploredViewport` and stop
        // following GPS, which is exactly backwards for a locate-me tap:
        // this is the one action that should ARM following again after a
        // "Search this area" tap or a manual pan turned it off.
        model.centerOnUser(
            lat: model.centerLat, lng: model.centerLng, radiusM: Self.radiusMeters(for: region)
        )
        if reduceMotion {
            position = .region(region)
        } else {
            withAnimation(.snappy) { position = .region(region) }
        }
        isTrackingUserLocation = true
        pulseLocateButton()
    }

    /// Scale 1 → 1.12 → 1 tap feedback on the locate button; skipped under
    /// Reduce Motion, matching every other animated camera move here.
    private func pulseLocateButton() {
        guard !reduceMotion else { return }
        withAnimation(.snappy(duration: 0.16)) {
            locateButtonScale = 1.12
        }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.16)) {
                locateButtonScale = 1
            }
        }
    }

    /// Any camera move NOT driven by `centerOnUser()` calls this — dropping
    /// both the tracking symbol and a still-pending "center once a fix
    /// lands" request the user has since panned, zoomed, or selected away
    /// from (bd#185).
    private func stopTrackingUserLocation() {
        if isTrackingUserLocation { isTrackingUserLocation = false }
        if pendingLocateAfterPermission { pendingLocateAfterPermission = false }
    }

    /// Shared body of the `model.centerLat`/`centerLng` `onChange` handlers:
    /// a `pendingLocateAfterPermission` request in flight gets the full
    /// animated, walking-zoom `centerOnUser()` treatment; otherwise this
    /// keeps the screen's original plain, unanimated recenter (e.g. the
    /// silent cold-start correction once a first fix replaces the Union
    /// Square fallback).
    private func applyCenterChange() {
        if pendingLocateAfterPermission {
            pendingLocateAfterPermission = false
            centerOnUser()
            return
        }
        // bd#198: a `.exploredViewport` centre change — "Search this area"
        // or a manual pan that triggered a refetch — is only ever set FROM
        // the camera's own settled position (`searchThisArea()` reads
        // `visibleRegion.center`), so the camera is already exactly there.
        // Recentering here would be redundant at best; at worst it resets
        // the user's zoom to `Self.region`'s fixed span, which reads as
        // exactly the "snaps back" bug this ticket fixes, just to a
        // different place. Keep the camera exactly where the user left it —
        // only the pins (via `model.venues`) change.
        guard model.centerSource != .exploredViewport else { return }
        // bd#209: a REAL location fix (`.userLocation`) replacing the Union
        // Square/NYC fallback opens at a walking-scale span (~0.014) — the
        // first view should read as "your neighbourhood," not half of
        // Manhattan. The Browse-NYC fallback (`.coverageDefault`) keeps the
        // original wider span unchanged — that's the screen the ticket says
        // not to touch.
        let span = model.centerSource == .userLocation ? Self.firstFixSpan : Self.defaultSpan
        let region = Self.region(lat: model.centerLat, lng: model.centerLng, span: span)
        position = .region(region)
        visibleRegion = region
    }

    /// The camera center as "lat,lng" — see the `map-camera-center`
    /// accessibility element this backs.
    ///
    /// While `isTrackingUserLocation` is true, reports `model.centerLat/Lng`
    /// directly rather than `visibleRegion`'s reconstructed center: the
    /// latter is recovered from `MapProxy` corner conversions across the
    /// FULL (edge-to-edge) view (`cameraRegion(proxy:size:)`, used for
    /// annotation culling), which is measurably offset from the requested
    /// `.region()` center once `.safeAreaPadding(.bottom, shelfClearance)`
    /// is in play — the same bias `searchFitRegion`'s own `latitudeShift`
    /// exists to compensate for on a fitted bounding box. `centerOnUser()`
    /// deliberately does NOT apply that compensation (it centers like every
    /// other single-point camera move in this file — cluster zoom, shelf
    /// selection — none of which shift for the shelf either), so reading
    /// `model.centerLat/Lng` here reports the coordinate actually asked
    /// for, not a shelf-shifted reconstruction of where the full-screen
    /// camera rect happens to sit.
    private var cameraCenterAccessibilityValue: String {
        let center: CLLocationCoordinate2D
        if isTrackingUserLocation {
            center = CLLocationCoordinate2D(latitude: model.centerLat, longitude: model.centerLng)
        } else {
            center = visibleRegion?.center
                ?? CLLocationCoordinate2D(latitude: model.centerLat, longitude: model.centerLng)
        }
        return String(format: "%.6f,%.6f", center.latitude, center.longitude)
    }

    private static let locateZoomSpan = 0.012

    // MARK: - Camera-driven re-planning

    /// Applies a settled camera region reported by `.onMapCameraChange` —
    /// the catch-all for camera moves no gesture handler here observes (the
    /// locate button chief among them, brewdesk#157). Gated by the same
    /// hysteresis as `scheduleReplan` so a settle this callback and a
    /// settle a gesture handler already captured don't double re-plan.
    private func refreshVisibleRegion(_ region: MKCoordinateRegion) {
        guard Self.needsReplan(from: visibleRegion, to: region) else { return }
        visibleRegion = region
    }

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

    // MARK: - "Search this area" (bd#192)

    /// The pill's tap action: re-fetches for whatever `visibleRegion`
    /// currently holds. A no-op (never sets `isSearchingThisArea`, never
    /// shows a spinner with nothing behind it) if the region somehow isn't
    /// known yet — the pill itself only ever shows once it is.
    private func searchThisArea() {
        guard let visibleRegion else { return }
        searchAreaFetchTask?.cancel()
        isSearchingThisArea = true
        stopTrackingUserLocation()
        model.updateViewport(
            lat: visibleRegion.center.latitude,
            lng: visibleRegion.center.longitude,
            radiusM: Self.radiusMeters(for: visibleRegion)
        )
        // Polls rather than observes — see `isSearchingThisArea`'s doc
        // comment for why a `.onChange(of: model.phase)` handler can miss
        // a fast fixture/scenario fetch entirely. Bounded so a genuinely
        // stuck load (network hang past `VenueAPI`'s own 15s timeout)
        // still clears the pill's progress state instead of spinning
        // forever.
        searchAreaFetchTask = Task {
            for _ in 0..<200 {
                guard !Task.isCancelled else { return }
                if model.phase != .loading { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            isSearchingThisArea = false
        }
    }

    /// "<lat>,<lng>,<radiusM>" — what `model` last actually queried with,
    /// backing the `map-last-query` UI-test seam.
    private var lastQueryAccessibilityValue: String {
        String(format: "%.6f,%.6f,%d", model.centerLat, model.centerLng, model.radiusM)
    }

    /// Half the longer visible side, clamped to `VenuesModel`'s
    /// viewport-query bounds (bd#192) — the radius both the "Search this
    /// area" tap and the locate-me refetch request.
    static func radiusMeters(for region: MKCoordinateRegion) -> Int {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLng = metersPerDegreeLat * cos(region.center.latitude * .pi / 180)
        let heightM = region.span.latitudeDelta * metersPerDegreeLat
        let widthM = region.span.longitudeDelta * abs(metersPerDegreeLng)
        let half = max(heightM, widthM) / 2
        let clamped = min(max(half, Double(VenuesModel.minRadiusM)), Double(VenuesModel.maxRadiusM))
        return Int(clamped.rounded())
    }

    /// The pill's own hysteresis (bd#192) — deliberately distinct from
    /// `needsReplan` below: that one decides when to recompute annotations
    /// for the SAME result set on every settle; this one decides whether
    /// the loaded result set might itself be stale for the new viewport,
    /// checked against `model`'s last-queried center/radius rather than an
    /// annotation-culling margin. True once the settled region's center has
    /// moved more than 35% of the loaded radius, or the region's own
    /// radius-equivalent has changed by more than 2× in either direction.
    static func needsSearchAreaPill(
        loadedCenterLat: Double, loadedCenterLng: Double, loadedRadiusM: Int,
        visibleRegion: MKCoordinateRegion
    ) -> Bool {
        guard loadedRadiusM > 0 else { return true }
        let movedM = VenuesModel.metersBetween(
            loadedCenterLat, loadedCenterLng,
            visibleRegion.center.latitude, visibleRegion.center.longitude
        )
        let candidateRadiusM = Double(radiusMeters(for: visibleRegion))
        let radiusRatio = candidateRadiusM / Double(loadedRadiusM)
        return movedM > Double(loadedRadiusM) * 0.35 || radiusRatio > 2 || radiusRatio < 0.5
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

    /// `MapAnnotationPlanner.plan(...)`, memoized against `planCache` (see
    /// its doc comment) — `body` re-evaluates far more often than the
    /// camera actually settles, and bd#209's collision-aware layout is
    /// expensive enough that recomputing it on every one of those renders
    /// is what actually regressed #208's frame timing, not the algorithm's
    /// own per-call cost.
    private func cachedPlan() -> MapAnnotationPlan {
        let key = PlanCacheKey(
            venues: model.venues,
            region: visibleRegion.map(RegionSnapshot.init),
            mapSize: mapSize,
            selectedID: selected?.id
        )
        if let cachedKey = planCache.key, cachedKey == key, let cached = planCache.plan {
            return cached
        }
        let plan = MapAnnotationPlanner.plan(
            venues: model.venues,
            region: visibleRegion,
            mapSize: mapSize,
            selectedVenueID: selected?.id
        )
        planCache.key = key
        planCache.plan = plan
        return plan
    }

    /// bd#204: the three representations are no longer mutually exclusive —
    /// a dense viewport draws all three layers at once (top-ranked score
    /// pins always on top, dots for the mid tier, clusters for whatever
    /// overflows both), so this renders every non-empty layer unconditionally
    /// rather than switching on a single case.
    @MapContentBuilder
    private func annotations(for plan: MapAnnotationPlan) -> some MapContent {
        ForEach(plan.pins) { venue in
            Annotation("", coordinate: coordinate(of: venue)) {
                pinButton(for: venue, isSelected: selected?.id == venue.id)
            }
        }
        ForEach(plan.dots) { venue in
            Annotation("", coordinate: coordinate(of: venue)) {
                dotButton(for: venue)
            }
        }
        ForEach(plan.clusters) { cluster in
            Annotation("", coordinate: cluster.coordinate) {
                clusterButton(for: cluster)
            }
        }
    }

    /// Split out of the `Map` content builder (bd#182): a `ForEach` here
    /// alongside `annotations(for:)`'s own inline one and the selected-pin
    /// overlay made the whole `Map { … }` trailing closure too much for the
    /// type checker ("unable to type-check this expression in reasonable
    /// time") — same fix as `annotations(for:)` already being its own
    /// function rather than inline.
    @MapContentBuilder
    private var gapFillAnnotations: some MapContent {
        ForEach(appleGapFillMarkers) { poi in
            Annotation("", coordinate: poi.coordinate) {
                gapFillButton(for: poi)
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
        .accessibilityLabel(Self.pinLabel(for: venue))
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
        .accessibilityLabel(Self.pinLabel(for: venue))
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
            stopTrackingUserLocation()
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
        .accessibilityLabel(Self.clusterLabel(for: cluster))
        .accessibilityHint("Zooms in to show them")
    }

    // MARK: - Apple base-map features (bd#182)

    /// Food/drink-only, per the ticket's point-of-interest filter — every
    /// other Apple POI category (transit, parks, shops, …) is left off the
    /// base map entirely rather than shown-but-inert.
    static let selectablePointsOfInterest: [MKPointOfInterestCategory] = [
        .cafe, .bakery, .restaurant, .foodMarket, .brewery, .winery,
    ]

    /// `Map`'s own selection binding fired: resolve the tapped feature
    /// against our venues (`AppleFeatureMatcher`) — a match opens our
    /// regular venue detail sheet (it IS one of ours, just drawn by Apple's
    /// free label); no match opens `AppleFeatureCard`. Either way the
    /// binding resets to `nil` so a repeat tap on the same label still
    /// fires this `onChange` the next time.
    private func handleAppleFeatureSelection(_ feature: MapFeature?) {
        defer { appleFeatureSelection = nil }
        guard let feature, let name = feature.title, !name.isEmpty else { return }
        if let matched = AppleFeatureMatcher.matchingVenue(
            name: name, lat: feature.coordinate.latitude, lng: feature.coordinate.longitude, in: model.venues
        ) {
            selected = matched
            return
        }
        resolvedAppleMapItem = nil
        let candidate = AppleCafeCandidate(
            name: name, coordinate: feature.coordinate, category: feature.pointOfInterestCategory
        )
        appleFeatureCandidate = candidate
        Task {
            let item = await AppleCafeDetailsResolver.resolveMapItem(
                name: name, coordinate: feature.coordinate, feature: feature
            )
            // The card may have already been dismissed (or a different
            // feature selected) by the time this lands.
            guard appleFeatureCandidate?.id == candidate.id else { return }
            resolvedAppleMapItem = item
        }
    }

    /// A tapped gap-fill marker: already pre-deduped against our venues
    /// (`AppleGapFillService.fetch`), so this always opens the card — no
    /// re-matching needed, and no async detail resolution either (a
    /// gap-fill POI came straight from `MKMapItem` already, but Directions
    /// works fine off the plain coordinate, so this stays cheap).
    private func gapFillButton(for poi: AppleUnverifiedPOI) -> some View {
        Button {
            resolvedAppleMapItem = nil
            appleFeatureCandidate = AppleCafeCandidate(name: poi.name, coordinate: poi.coordinate)
        } label: {
            AppleUnverifiedPin()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(poi.name), unverified, not yet in BrewDesk")
        .accessibilityIdentifier("apple-gap-fill-pin")
    }

    /// Re-evaluates the feature-flagged gap-fill (default OFF) for the
    /// current `region`: fewer than `AppleGapFillService
    /// .minimumPinsBeforeGapFill` of our own pins in view triggers an
    /// on-device `MKLocalPointsOfInterestRequest`. Cancels any in-flight
    /// fetch first — a fast pan/zoom must never race two of these.
    private func scheduleGapFill(region: MKCoordinateRegion?) {
        gapFillTask?.cancel()
        guard AppleGapFillService.isEnabled, let region else {
            appleGapFillMarkers = []
            return
        }
        let ourPinCount = MapAnnotationPlanner.culled(model.venues, region: region).count
        guard AppleGapFillService.shouldGapFill(ourPinCount: ourPinCount) else {
            appleGapFillMarkers = []
            return
        }
        let venues = model.venues
        gapFillTask = Task {
            let markers = await AppleGapFillService.fetch(region: region, excluding: venues)
            guard !Task.isCancelled else { return }
            appleGapFillMarkers = markers
        }
    }

    @ViewBuilder
    private var loadStatus: some View {
        switch model.phase {
        // `.idle` with nothing loaded (first paint, or a cancelled load) is
        // shown as loading — never a bare map with no explanation.
        case .idle where model.venues.isEmpty, .loading where model.venues.isEmpty:
            ProgressView("Finding work spots…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("map-state-loading")
        // With snapshot rows on the map, failure is a banner in the header.
        case .failed where model.venues.isEmpty:
            ContentUnavailableView {
                Label("Spot service unavailable", systemImage: "wifi.exclamationmark")
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

    /// One glass card for search + filters + the single count line
    /// (ui-review-2026-08-21 finding 2). Banners dock directly beneath the
    /// card as sibling rows (finding 15's grouping).
    ///
    /// UI3 (brewdesk#118): the field's trailing control and the count line
    /// below it are the whole header now — the old chip rail moved into
    /// `WorkFitFilterMenu`, and `DatasetStatStrip`'s separate row folded into
    /// the one count line (both numbers dynamic; never hardcoded).
    private var searchHeader: some View {
        VStack(spacing: 8) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search spots", text: $model.searchQuery)
                            .submitLabel(.search)
                            .focused($searchFocused)
                            .onSubmit {
                                model.submitSearch()
                                searchFocused = false
                            }
                        if !model.searchQuery.isEmpty {
                            // bd#200: the citywide server search's own
                            // in-flight indicator, distinct from the
                            // viewport load spinner (`map-state-loading`) —
                            // this one is scoped to the search field itself.
                            if model.isSearchingServer {
                                ProgressView()
                                    .controlSize(.mini)
                                    .accessibilityIdentifier("search-server-progress")
                                    .accessibilityLabel("Searching all of NYC")
                            }
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

                    // Trailing control: the filter badge normally, Cancel
                    // while the field has focus — dismisses the keyboard and
                    // clears focus (brewdesk#87's cannot-dismiss-keyboard fix).
                    // Retired the floating keyboard-toolbar Done button that
                    // used to draw over the venue card.
                    if searchFocused {
                        Button("Cancel") {
                            searchFocused = false
                        }
                        .font(.subheadline.bold())
                        .accessibilityIdentifier("search-cancel")
                    } else {
                        WorkFitFilterButton(model: model)
                    }
                }

                HStack {
                    Text(countLine)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    // bd#204: names both marker kinds explicitly — the old
                    // "Scores show Work Fit" said nothing about clusters, so
                    // a count pill under it read as another score. Three
                    // fallback lengths (`ViewThatFits`) so the smallest
                    // supported width and large Dynamic Type both still fit
                    // on one line instead of clipping.
                    ViewThatFits(in: .horizontal) {
                        Text("Circles: Work Fit score · Stacks: cafés grouped")
                        Text("Circles: score · Stacks: grouped")
                        Text("Score · Grouped")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 6)
                .accessibilityIdentifier("map-count-line")
            }
            .padding(10)
            .brewDeskGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("map-header-card")

            if let state = model.snapshotBanner {
                SnapshotBanner(state: state) { model.retry() }
            }

            if model.coverage == .baseline {
                CoverageBaselineBanner()
            }

            if locationDenied {
                LocationDeniedBanner()
            } else if locationUndetermined, let requestLocationAccess {
                LocationUndeterminedBanner(requestAccess: requestLocationAccess)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// "N of M spots" — the two competing counts (a plain venue count and
    /// `DatasetStatStrip`'s dataset total) collapsed into one line
    /// (brewdesk#118). Both numbers stay dynamic: `N` is the live, filtered
    /// `model.venues.count`; `M` is the dataset total from `model.health`
    /// once it loads, and falls back to the plain count (never a hardcoded
    /// figure) before health answers.
    private var countLine: String {
        guard let total = model.health?.venueCount else {
            return localizedWorkSpotCount(model.venues.count)
        }
        return String(
            format: String(localized: "%1$lld of %2$lld spots"),
            locale: .current,
            model.venues.count,
            total
        )
    }

    /// Extra bottom safe area for the map subtree — how compass,
    /// user-location button, and attribution avoid the card, mirroring the
    /// detail dock's safe-area approach. Sized from Dynamic Type–scaled
    /// estimates of the MEDIUM card's intrinsic parts and deliberately
    /// CONSTANT across detents (brewdesk#128): `Map` re-fits its camera into
    /// the safe viewport whenever this inset changes, so a per-detent value
    /// made the map visibly jump with every shelf drag. The card is an
    /// overlay; the map underneath must not move with it. At `.peek` the
    /// controls simply rest where the medium card's top would be, and `.full`
    /// covers them either way.
    private var shelfClearance: CGFloat {
        shelfChipRowHeight + 56 + shelfCardBlockHeight + 12
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

    /// The screen's original camera span (Browse NYC fallback, and every
    /// call site not covered by bd#209's item E below).
    private static let defaultSpan = 0.035
    /// bd#209: the span a REAL first location fix opens at — walking scale,
    /// so the first view reads as a neighbourhood instead of half of
    /// Manhattan. See `applyCenterChange` for the one call site that uses
    /// this instead of `defaultSpan`.
    private static let firstFixSpan = 0.014

    private static func region(lat: Double, lng: Double, span: Double = defaultSpan) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    private func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }
}

/// Unobserved mutable flag for "a finger is driving the map right now"
/// (brewdesk#158). A class so writing it never invalidates a SwiftUI body.
@MainActor
private final class MapInteractionFlag {
    var isActive = false
}

/// Prominent "center on me" control (bd#185), replacing the stock
/// `MapUserLocationButton()`: a solid 48pt brand-filled circle rather than a
/// small translucent glass pill, so it reads as tappable at a glance next to
/// `MapCompass()`. State is carried entirely by icon + a brief scale pulse —
/// never by color alone (the founder is red-green colorblind) — so the
/// denied state (`location.slash`) is as legible as the tracking state
/// (`location.fill`) to anyone who can't distinguish a tint shift.
struct LocateMeButton: View {
    var isTracking: Bool
    var isDenied: Bool
    var pulseScale: CGFloat
    var action: () -> Void

    private var symbolName: String {
        if isDenied { return "location.slash" }
        return isTracking ? "location.fill" : "location"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(BrewDeskPalette.foam)
                .frame(width: 48, height: 48)
                .background(BrewDeskPalette.roast, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .scaleEffect(pulseScale)
        .accessibilityIdentifier("map-locate-me")
        .accessibilityLabel("Center map on my location")
    }
}

/// `MKCoordinateRegion` isn't `Equatable`, so the gap-fill `onChange` (bd#182)
/// watches this small snapshot of it instead.
private struct RegionSnapshot: Equatable {
    let lat: Double
    let lng: Double
    let latDelta: Double
    let lngDelta: Double

    init(_ region: MKCoordinateRegion) {
        lat = region.center.latitude
        lng = region.center.longitude
        latDelta = region.span.latitudeDelta
        lngDelta = region.span.longitudeDelta
    }
}

/// Everything `MapAnnotationPlanner.plan(...)`'s output actually depends on
/// (bd#209) — see `planCache`'s doc comment on why this exists.
private struct PlanCacheKey: Equatable {
    let venues: [Venue]
    let region: RegionSnapshot?
    let mapSize: CGSize
    let selectedID: String?
}

/// Plain reference box, not `@State` itself — see `planCache`'s doc comment.
private final class PlanCacheBox {
    var key: PlanCacheKey?
    var plan: MapAnnotationPlan?
}
