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
    /// bd#217: the settled camera's heading in degrees, reported alongside
    /// `visibleRegion` by the same `.onMapCameraChange(frequency: .onEnd)`
    /// callback — MapKit's own `MapCompass()` control only draws itself
    /// once the map is rotated off true-north, and this app has no other
    /// way to know that state exists. Drives `compassExclusionRect` below.
    @State private var mapHeading: Double = 0
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
    /// bd#219: fires once a search-selection fly-to (`selectSearchResult`)
    /// has had time to settle, to load the surroundings around the newly
    /// selected café. Cancelled by a later selection or `onDisappear`.
    @State private var flySettleTask: Task<Void, Never>?
    /// bd#219: the exact `model.searchQuery` text an explicit selection
    /// (`selectSearchResult`) committed to. `scheduleSearchFit` bails
    /// whenever the CURRENT query still equals this — an explicit tap or
    /// return always wins over a late server search answer (or this same
    /// selection's own `updateViewport` reload changing `model.venues`
    /// again) landing after it. A genuinely new query no longer equals this
    /// stale value, so the guard stops applying on its own with no explicit
    /// reset needed.
    @State private var searchSelectionQuery: String?
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
    /// bd#210: true once a real drag/pinch/double-tap gesture has settled —
    /// the ONLY thing allowed to make `showSearchAreaPill` visible. A
    /// programmatic camera move (first GPS fix, "Browse NYC", search fit,
    /// locate-me) resets this false, so a data/radius mismatch from one of
    /// THOSE never shows the pill with zero user interaction — the ticket's
    /// own bug ("pill visible at launch with no gesture") was exactly a
    /// radius mismatch on the first GPS fix masquerading as "you moved the
    /// map." (The radius mismatch itself is also fixed directly —
    /// `VenuesModel.syncRadiusToCamera` — this flag is the belt-and-braces
    /// backstop.)
    @State private var userHasMovedCamera = false
    /// bd#210: chrome frames the annotation planner treats as already-
    /// occupied, all measured in `Self.mapPlaneSpace` (the SAME local
    /// coordinate space `mapSize` implicitly uses — nothing between the
    /// view `mapSize`/these are measured on and the actual `Map` changes
    /// its own frame, only adds floating overlays/insets on top of it).
    /// `searchAreaPillFrame` is `nil` whenever the pill itself isn't in the
    /// view tree — never a stale rect from the last time it was visible.
    /// bd#217 adds a fifth chrome rect, the compass — see
    /// `compassExclusionRect`'s own doc comment for why it isn't a
    /// `@State`-backed measured frame like these four.
    @State private var searchHeaderFrame: CGRect = .zero
    @State private var searchAreaPillFrame: CGRect?
    @State private var locateButtonFrame: CGRect = .zero
    @State private var shelfFrame: CGRect = .zero
    /// Named coordinate space for the chrome-exclusion measurements above —
    /// declared on the OUTERMOST modifier of this screen's `body` (every
    /// overlay/safeAreaInset attached anywhere in the chain is a structural
    /// descendant of it) so every measurement shares one reference frame.
    nonisolated private static let mapPlaneSpace = "CafeMapScreen.mapPlane"

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
        // bd#210: `userHasMovedCamera` gates the whole thing — a
        // center/radius mismatch from a PROGRAMMATIC move (first GPS fix,
        // "Browse NYC", search fit, locate-me) must never show this with no
        // actual gesture; see the property's own doc comment.
        let showSearchAreaPill = userHasMovedCamera && model.searchQuery.isEmpty && (isSearchingThisArea || visibleRegion.map {
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
                    mapCircles(for: plan)
                    // A venue chosen from the shelf (or panned away from
                    // since) still shows a full selected teardrop even when
                    // it fell outside the current plan's culled/collision
                    // pass (bd#212 — same fallback bd#209's selected pin
                    // always used).
                    if let selected, !plan.containsVenue(id: selected.id) {
                        Annotation("", coordinate: coordinate(of: selected), anchor: .bottom) {
                            markerButton(for: MarkerPlacement(
                                venue: selected,
                                kind: .teardrop(diameter: MapAnnotationPlanner.selectedDiameter),
                                showsNumber: selected.isRated,
                                isSelected: true
                            ))
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
                    // bd#217: `mapHeading` change alone must still trigger a
                    // re-plan (a rotate-only gesture with no pan/zoom would
                    // otherwise leave `visibleRegion` — and so the memoized
                    // plan — untouched even though the compass exclusion
                    // rect just appeared/moved).
                    mapHeading = context.camera.heading
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            mapInteraction.isActive = true
                            stopTrackingUserLocation()
                        }
                        .onEnded { _ in
                            mapInteraction.isActive = false
                            userHasMovedCamera = true
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
                            userHasMovedCamera = true
                            scheduleReplan(proxy: proxy, size: geometry.size)
                        }
                )
                // Built-in double-tap zoom has no drag or magnify phase.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            stopTrackingUserLocation()
                            userHasMovedCamera = true
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
                // bd#212 (supervisor revision): `.dot`/`.speck` markers are
                // native `MapCircle` overlays, not SwiftUI buttons, so they
                // need their own tap dispatch — nearest marker within 22pt
                // of the touch, rated (dot) preferred over unrated (speck).
                // `SpatialTapGesture` is simultaneous with every gesture
                // above, so it never blocks panning/zooming/Apple-label
                // selection; it only acts when the tap actually lands near
                // one of these markers.
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleMapCircleTap(at: value.location, plan: plan, proxy: proxy)
                        }
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
                    // bd#210: measured only while the pill actually exists in
                    // the view tree — `showSearchAreaPill` going false below
                    // this view disappearing entirely, never a stale rect.
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.mapPlaneSpace))
                    } action: { rect in
                        searchAreaPillFrame = rect
                    }
            }
        }
        .onChange(of: showSearchAreaPill) { _, visible in
            if !visible { searchAreaPillFrame = nil }
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
        .safeAreaInset(edge: .top) {
            searchHeader
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.mapPlaneSpace))
                } action: { rect in
                    searchHeaderFrame = rect
                }
        }
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
                // bd#219: a row tap while a search is active (typed text
                // still in the field, matching `showSearchAreaPill`'s own
                // gate) is a SEARCH RESULT selection — fly-to at walking
                // scale, collapse the shelf, load surroundings. A plain
                // browsing tap (no search text) keeps the original
                // neighborhood-zoom recenter untouched.
                if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectSearchResult(venue)
                } else {
                    selected = venue
                    stopTrackingUserLocation()
                    position = .region(
                        MKCoordinateRegion(
                            center: coordinate(of: venue),
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        )
                    )
                }
            }
            // Dragging the shelf (resize or its own scroll content) also
            // resigns the search field (brewdesk#87). Applied at the call
            // site rather than inside `DiscoveryShelfCard` — its own
            // `minimumDistance: 8` resize gesture and any internal
            // scrolling both still recognize normally alongside this one.
            //
            // bd#219: `minimumDistance: 8`, not `0` — a zero-distance drag
            // fires its `onChanged` on the very first touch-DOWN, before a
            // tap gesture underneath (a venue row's `Button`) gets to
            // recognize the touch as a tap. In search mode that touch-down
            // set `searchFocused = false` immediately, which flips
            // `DiscoveryShelfCard.isSearchFocused` mid-touch and swaps its
            // content from the vertical search list back to the horizontal
            // rail out from under the finger — cancelling the row's own tap
            // gesture entirely (reproduced: a synthesized row tap in
            // XCUITest never reached `onVenueTap` at all). Matches the same
            // fix the card's own resize gesture already uses, and the same
            // rationale ("venue-card and chip taps stay taps") — this
            // gesture's own doc comment already says it exists for DRAGS
            // (resize/scroll), never a stationary tap.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in searchFocused = false }
            )
            .scrollDismissesKeyboard(.immediately)
            // bd#210: the shelf's REAL rendered frame at whatever detent
            // it's currently at — not `shelfClearance`'s constant estimate
            // (deliberately detent-invariant so the MAP doesn't jump; the
            // exclusion rect is the opposite — it should track the card
            // exactly, so a marker under a `.peek` shelf is fine but the
            // same marker under `.full` is excluded).
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.mapPlaneSpace))
            } action: { rect in
                shelfFrame = rect
            }
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
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.mapPlaneSpace))
                } action: { rect in
                    locateButtonFrame = rect
                }
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
            // bd#212 VERIFY seam: opens the camera at a scripted real-world
            // metres-per-point instead of the normal GPS-fix/Browse-NYC
            // default, so a screenshot pass or `MapPerformanceUITests`' "dot
            // zoom" run can script an exact marker-size target (city/
            // neighborhood/street density) directly rather than depending on
            // a real pan/pinch to reach it, or guessing a degree span MapKit
            // might render wider once it fits the device's aspect ratio.
            // Converted to a coordinate span using the CURRENT center
            // latitude and whatever `mapSize` is known right now (falling
            // back to `MapAnnotationPlanner.fallbackMapSize` before the
            // first `GeometryReader` report) — an approximation good enough
            // to land the FIRST camera in the ballpark; the very next
            // re-plan re-derives the real metres/point from the actually
            // settled region/mapSize regardless. Gated by `isUITestRun`
            // (true only when some `-UITest…` argument is ALSO present,
            // same pattern `MapFrameStatsHUD.isEnabled` and every other
            // `-brewdesk.*`/`-UITest*` seam in this file already uses)
            // rather than `#if DEBUG`: `MapPerformanceUITests` runs this
            // exact seam against a RELEASE + ENABLE_TESTABILITY build (the
            // ticket's own perf-measurement configuration), where `#if
            // DEBUG` would have compiled it out entirely. A real launch —
            // App Store or TestFlight — never carries a `-UITest…`
            // argument, so this can never drive one.
            if launchEnvironment.isUITestRun, let metersPerPoint = launchEnvironment.debugInitialMetersPerPoint {
                let assumedWidth = mapSize.width > 0 ? mapSize.width : MapAnnotationPlanner.fallbackMapSize.width
                let metersPerDegreeLng = 111_320.0 * cos(model.centerLat * .pi / 180)
                let span = metersPerPoint * Double(assumedWidth) / metersPerDegreeLng
                let region = Self.region(lat: model.centerLat, lng: model.centerLng, span: span)
                position = .region(region)
                visibleRegion = region
            }
        }
        .onDisappear {
            replanTask?.cancel()
            searchFitTask?.cancel()
            gapFillTask?.cancel()
            searchAreaFetchTask?.cancel()
            flySettleTask?.cancel()
        }
        // bd#210: declared LAST (outermost) so every overlay/safeAreaInset
        // attached anywhere above — the search header, the search-area
        // pill, the locate button, the shelf card — is a structural
        // descendant of this exact view and can resolve `.named(…)`
        // against the SAME reference frame `mapSize` is measured in
        // (nothing between them changes the base view's own bounds; every
        // modifier in between only adds floating overlays/insets on top of
        // it).
        .coordinateSpace(name: Self.mapPlaneSpace)
    }

    // MARK: - Spoken labels (brewdesk#159)

    /// Pin label contract: "<name>, <score phrase>, <neighborhood>". UI tests
    /// match on the "<name>," prefix; VoiceOver must never read the engine's
    /// neutral fallback number for a venue nobody has rated (brewdesk#213:
    /// driven by `displayScore`, which honors the server's own
    /// `scoreDisplay` over the `isObserved` heuristic).
    static func pinLabel(for venue: Venue) -> String {
        let score = venue.displayScore.map { "Work Fit \($0)" } ?? "not rated yet"
        return "\(venue.name), \(score), \(venue.neighborhood)"
    }

    // MARK: - Search-driven camera fit (brewdesk#158)

    /// Pure guard behind `scheduleSearchFit` (bd#219, extracted for direct
    /// unit testing — everything else about the fit's scheduling/animation
    /// needs a running `Map`). A "fit all results" pass is only ever
    /// appropriate while the user is still typing/browsing a query with NO
    /// committed selection: false for an empty/blank query (nothing to fit),
    /// and false once `selectionQuery` — `searchSelectionQuery`, set by
    /// `selectSearchResult` — already equals the query being asked about,
    /// however that call arrived (a late server search answer, or the
    /// selection's own surroundings reload changing `model.venues` again).
    static func shouldApplySearchFit(forQuery query: String, selectionQuery: String?) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && query != selectionQuery
    }

    /// Cancels any pending fit and, for a non-empty query, schedules one
    /// past `VenuesModel.scheduleSearchApplication`'s own ~200ms debounce
    /// so `model.venues` already reflects the settled search by the time
    /// this reads it. Clearing the query (or narrowing it to blank) simply
    /// cancels — no move, camera stays put, matching the ticket's scope.
    private func scheduleSearchFit(query: String) {
        searchFitTask?.cancel()
        guard Self.shouldApplySearchFit(forQuery: query, selectionQuery: searchSelectionQuery) else { return }
        searchFitTask = Task {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            // Superseded by further typing, the user is mid-gesture (never
            // yank the camera out from under a drag/pinch in flight), or an
            // explicit selection landed for this query while sleeping —
            // re-checked here since `searchSelectionQuery` may have been set
            // AFTER this task's own guard above already passed.
            guard model.searchQuery == query, !mapInteraction.isActive,
                  Self.shouldApplySearchFit(forQuery: query, selectionQuery: searchSelectionQuery)
            else { return }
            let results = model.venues
            guard !results.isEmpty,
                  let region = Self.searchFitRegion(for: results, mapHeight: mapHeight, shelfClearance: shelfClearance)
            else { return }
            // Programmatic move: the target region is already known, so
            // re-plan pins for it directly rather than waiting on a camera
            // settle (same pattern as the cluster-zoom handler above).
            visibleRegion = region
            stopTrackingUserLocation()
            // bd#210: a search fit is programmatic, not a gesture.
            userHasMovedCamera = false
            if reduceMotion {
                position = .region(region)
            } else {
                withAnimation(.snappy) { position = .region(region) }
            }
        }
    }

    /// The camera region that fits `results`: a single result centers at
    /// WALKING zoom (bd#219 — a single match, whether from a settled
    /// search-as-you-type or an explicit selection via `selectSearchResult`,
    /// reads as a Google-Maps-style pin drop, not a neighborhood overview);
    /// several results fit their bounding box with padding at the original,
    /// wider neighborhood-zoom floor. The fitted box is biased north by half
    /// of `shelfClearance`'s share of `mapHeight` so a southerly result
    /// still lands above the shelf card rather than behind it.
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

        let neighborhoodZoomSpan = results.count == 1 ? walkingZoomSpan : 0.012
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

    /// bd#219: walking scale for a flown-to/single-result search selection —
    /// ≈1.8–2.4 m/pt at NYC's latitude, per the ticket's spec range
    /// (0.008–0.010°). Distinct from `locateZoomSpan` (0.012, the
    /// locate-me/plain-browsing-tap neighborhood zoom): a search result the
    /// user picked by name is a precise pin drop, not "somewhere near here."
    static let walkingZoomSpan = 0.009

    /// bd#219: the fly-to's visible-area bias, as a FIXED fraction of
    /// `walkingZoomSpan`, deliberately not `searchFitRegion`'s live
    /// `shelfClearance`/`mapHeight` ratio (the "still typing/browsing" fit
    /// above reuses that, unchanged). That ratio is unreliable at exactly a
    /// selection tap's call site: the keyboard's own dismiss relayout is
    /// still in flight the instant a row is tapped
    /// (`selectSearchResult` only just requested `searchFocused = false`),
    /// so `mapHeight` reads anywhere from its keyboard-shrunk value to its
    /// settled one depending on exactly when it's sampled — measured
    /// shifts from ~350m to over 4km for the SAME tap while iterating on
    /// this fix, including with a short deferred read and with
    /// `.ignoresSafeArea(.keyboard)` (both tried, both reverted — the
    /// latter also changed `MapShelfDetentUITests`'
    /// `testGrabberDragsUpToFullAndListOpensDetail`'s full-detent height, a
    /// regression nothing about this ticket should touch). A fixed
    /// fraction of the ALWAYS-known target span keeps the shift small,
    /// deterministic, and immune to that race — 0.22 lands the venue
    /// comfortably in the upper ~60% of the visible map at this zoom.
    static let flyToNorthBiasFraction = 0.22

    // MARK: - Search result selection (bd#219)

    /// A tap on a search result — a shelf row while `DiscoveryShelfCard` is
    /// in search mode, or a keyboard Search/return with exactly one match
    /// (see `searchHeader`'s `.onSubmit`) — always wins over whatever
    /// `scheduleSearchFit` is doing: resigns the keyboard, commits
    /// `searchSelectionQuery` so no late fit (server search landing, or this
    /// selection's own surroundings reload below) can move the camera again
    /// for this query, collapses the shelf to `.medium`, selects the venue,
    /// and flies the camera to it at walking scale, biased north (see
    /// `flyToNorthBiasFraction`) so it lands in the visible area above the
    /// newly collapsed shelf.
    private func selectSearchResult(_ venue: Venue) {
        searchFitTask?.cancel()
        searchSelectionQuery = model.searchQuery
        searchFocused = false
        shelfDetent = .medium
        selected = venue
        stopTrackingUserLocation()
        let shift = Self.walkingZoomSpan * Self.flyToNorthBiasFraction
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: venue.lat - shift, longitude: venue.lng),
            span: MKCoordinateSpan(latitudeDelta: Self.walkingZoomSpan, longitudeDelta: Self.walkingZoomSpan)
        )
        // A search selection is a programmatic move, not a gesture — same
        // convention every other programmatic camera move in this file
        // follows (bd#210): the "Search this area" pill must stay gated off.
        userHasMovedCamera = false
        if reduceMotion {
            position = .region(region)
        } else {
            withAnimation(.snappy) { position = .region(region) }
        }
        visibleRegion = region
        loadSurroundings(of: venue, region: region)
    }

    /// Loads the area around a just-selected search result once the fly-to
    /// has had time to settle. No completion callback exists for a
    /// `MapCameraPosition` binding write, so this waits a fixed interval the
    /// same way `pulseLocateButton` already does for its own `.snappy`
    /// animation. `model.updateViewport` marks the new centre
    /// `.exploredViewport` (bd#198) — a later passive GPS tick can never
    /// snap the camera back off it — and `userHasMovedCamera` is reset
    /// false right after so this programmatic fetch never arms the "Search
    /// this area" pill (bd#210).
    private func loadSurroundings(of venue: Venue, region: MKCoordinateRegion) {
        flySettleTask?.cancel()
        flySettleTask = Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 420))
            guard !Task.isCancelled, selected?.id == venue.id else { return }
            model.updateViewport(
                lat: venue.lat, lng: venue.lng, radiusM: Self.radiusMeters(for: region)
            )
            userHasMovedCamera = false
            // bd#219: `updateViewport` changes `model.request`, which loads
            // new surroundings and so changes `model.venues` — and THIS
            // screen's own `.onChange(of: model.venues)` unconditionally
            // re-derives `visibleRegion` from the MapKit proxy's live
            // camera corners for every such change (brewdesk#157, so a
            // search clear/filter change never rides on a region captured
            // for a different list). If the `.snappy` fly-to animation
            // triggered above hasn't visually finished settling by the time
			// that fires, this read races it and can capture an
            // in-flight/stale intermediate region instead of the real fly-to
            // target — the actual `Map` camera keeps animating to the right
            // place regardless (that proxy read never touches `position`),
            // but the `map-camera-center` accessibility value this
            // selection is judged by can get stuck reporting the stale one.
            // Re-asserting the KNOWN fly-to target here, after the
            // surroundings load that can trigger that race, is cheap
            // insurance — a later real camera settle still corrects
            // `visibleRegion` again via `.onMapCameraChange` regardless.
            visibleRegion = region
        }
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
        // bd#210: an explicit locate-me tap is a programmatic move, not a
        // gesture — resets the "Search this area" pill's gate the same way
        // `applyCenterChange()`'s other programmatic moves do.
        userHasMovedCamera = false
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
        // bd#210: a real fix syncs the query radius to the span the camera
        // is ABOUT to show, in the same synchronous update as `visibleRegion`
        // below — `updateCenterIfNeeded` (the passive path this reacts to)
        // never had a radius to carry, so without this the first fetch after
        // a fix stayed at `defaultRadiusM` while the camera opened much
        // tighter, which alone made `needsSearchAreaPill` see a spurious
        // >2× radius "change" with no gesture involved.
        if model.centerSource == .userLocation {
            model.syncRadiusToCamera(Self.radiusMeters(for: region))
        }
        // bd#210: this is always a PROGRAMMATIC move (a fix landing, or
        // "Browse NYC" via `browseCoverageCenter()` — both land here since
        // neither is `.exploredViewport`), never a gesture — the pill must
        // stay gated off until a real drag/pinch/double-tap sets it back.
        userHasMovedCamera = false
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
        let exclusionRects = chromeExclusionRects()
        let key = PlanCacheKey(
            venues: model.venues,
            region: visibleRegion.map(RegionSnapshot.init),
            mapSize: mapSize,
            selectedID: selected?.id,
            exclusionRects: exclusionRects
        )
        if let cachedKey = planCache.key, cachedKey == key, let cached = planCache.plan {
            return cached
        }
        let plan = MapAnnotationPlanner.plan(
            venues: model.venues,
            region: visibleRegion,
            mapSize: mapSize,
            selectedVenueID: selected?.id,
            exclusionRects: exclusionRects
        )
        planCache.key = key
        planCache.plan = plan
        return plan
    }

    /// bd#210: the chrome rects the planner treats as already-occupied —
    /// (a) top of the map through the search header's bottom edge + 8pt
    /// (covers the status bar too, since the map itself renders full-bleed
    /// behind it — see `Self.mapPlaneSpace`'s doc comment), (b) the
    /// "Search this area" pill's own frame while it's actually on screen,
    /// (c) the locate button, (d) the shelf card at whatever detent it's
    /// currently resting at. All measured, never hard-coded, so this stays
    /// correct across Dynamic Type sizes, device widths, and shelf drags.
    private func chromeExclusionRects() -> [CGRect] {
        var rects: [CGRect] = []
        if mapSize.width > 0 {
            rects.append(CGRect(x: 0, y: 0, width: mapSize.width, height: searchHeaderFrame.maxY + 8))
        }
        if let searchAreaPillFrame {
            rects.append(searchAreaPillFrame)
        }
        if let compassExclusionRect {
            rects.append(compassExclusionRect)
        }
        if locateButtonFrame != .zero {
            rects.append(locateButtonFrame)
        }
        if shelfFrame != .zero {
            rects.append(shelfFrame)
        }
        return rects
    }

    /// bd#217: `MapCompass()` (attached via this screen's `.mapControls`
    /// modifier, earlier in `body`) is a
    /// native MapKit control, not a view this screen composes itself — it
    /// has no frame `.onGeometryChange` can observe the way every other
    /// chrome rect here does. Only drawn by MapKit at all once the camera
    /// is rotated off true-north (`mapHeading`), and always placed
    /// top-trailing, just clear of the search header, at a fixed
    /// ~44pt-across system control size — this rect is a deliberately
    /// generous hand-measured approximation of that fixed placement rather
    /// than a live measurement, wide enough to cover the control at every
    /// Dynamic Type size (the header's own height already flexes for
    /// that, and this rect anchors off the header's real measured bottom
    /// edge, not a hard-coded y).
    private static let compassApproxDiameter: CGFloat = 44
    private static let compassApproxMargin: CGFloat = 12

    private var compassExclusionRect: CGRect? {
        guard mapSize.width > 0, abs(mapHeading) > 0.5 else { return nil }
        let side = Self.compassApproxDiameter + Self.compassApproxMargin
        return CGRect(
            x: mapSize.width - side - Self.compassApproxMargin,
            y: searchHeaderFrame.maxY + 8,
            width: side,
            height: side
        )
    }

    /// bd#212 (supervisor revision): only numbered TEARDROPS are real
    /// SwiftUI `Annotation`s — `id: \.id` (the venue id) keeps a size/
    /// selection change an in-place update of the SAME hosted annotation
    /// view rather than a remove+insert. Demoted dots and unrated specks
    /// are native `MapCircle` overlay content (`mapCircles(for:)`) — the
    /// perf fix for #211's stalls: hosting every one of ~150-200 unrated
    /// venues as a SwiftUI annotation view (each wrapped in a 44pt Button)
    /// was the real cost, not view type churn.
    @MapContentBuilder
    private func annotations(for plan: MapAnnotationPlan) -> some MapContent {
        ForEach(plan.teardrops) { placement in
            Annotation("", coordinate: coordinate(of: placement.venue), anchor: .bottom) {
                markerButton(for: placement)
            }
        }
    }

    /// bd#212 (supervisor revision): demoted rated venues and unrated
    /// specks, drawn as cheap native `MapCircle`s — MapKit's own overlay
    /// primitive, never a hosted SwiftUI view.
    ///
    /// Radius is derived from the LIVE metres-per-point, not a bare fixed
    /// metres constant: a pure fixed radius (the supervisor's own starting
    /// suggestion, "~5 m") shrinks toward invisibility once a rated venue is
    /// a `.dot` because the WHOLE zoom is past the teardrop threshold (city
    /// zoom, ≥7.2 m/pt) rather than because of a collision demotion at a
    /// closer zoom — a 5m dot at 7.2 m/pt is well under 1pt on screen,
    /// which undersells the "4pt dot" visual target that same zoom level
    /// is supposed to read as. Scaling the radius by the settled mpp keeps
    /// a dot/speck's ON-SCREEN size roughly constant across zoom levels —
    /// still a cheap native overlay, just sized to actually be seen.
    @MapContentBuilder
    private func mapCircles(for plan: MapAnnotationPlan) -> some MapContent {
        let mpp = visibleRegion.map { MapAnnotationPlanner.metersPerPoint(region: $0, mapWidth: mapSize.width) } ?? 3.3
        let dotRadius = Self.dotRadiusMeters(forMetersPerPoint: mpp)
        let speckRadius = Self.speckRadiusMeters(forMetersPerPoint: mpp)
        ForEach(plan.dots) { placement in
            MapCircle(center: coordinate(of: placement.venue), radius: dotRadius)
                .foregroundStyle(BrewDeskPalette.markerFill(score: placement.venue.workScore))
        }
        ForEach(plan.specks) { placement in
            MapCircle(center: coordinate(of: placement.venue), radius: speckRadius)
                .foregroundStyle(BrewDeskPalette.markerSpeckFill)
        }
    }

    /// ~4pt apparent diameter (2pt radius) at the current zoom — matches
    /// the design's own "4pt dot, no number" city-zoom target — clamped so
    /// it neither vanishes at wide zoom nor balloons at the closest zoom.
    /// Supervisor's own starting number ("~5 m radius") is close to this at
    /// the demotion zooms (≈1.8-3.6 m/pt ⇒ 3.6-7.2m here); the clamp mainly
    /// matters at ≥7.2 m/pt, where a bare 5m would already be sub-pixel.
    private static func dotRadiusMeters(forMetersPerPoint mpp: Double) -> CLLocationDistance {
        min(max(2.0 * mpp, 3.0), 15.0)
    }

    /// Same shape as `dotRadiusMeters(forMetersPerPoint:)`, a touch smaller
    /// (~2.6pt apparent diameter) so an unrated speck stays visually
    /// subordinate to a rated dot at the same zoom (supervisor spec: "~3-4
    /// m radius").
    private static func speckRadiusMeters(forMetersPerPoint mpp: Double) -> CLLocationDistance {
        min(max(1.3 * mpp, 2.0), 10.0)
    }
    /// Screen-point radius a tap must land within to select a `.dot`/
    /// `.speck` marker (supervisor spec: "nearest venue within 22pt").
    private static let mapCircleTapRadius: CGFloat = 22

    /// bd#212 (supervisor revision): `.dot`/`.speck` markers have no
    /// SwiftUI button of their own to catch a tap (they're `MapCircle`
    /// overlays), so a tap anywhere on the map is checked against every
    /// dot/speck's SCREEN position (via `MapProxy.convert(_:to:)`) and the
    /// nearest one within `mapCircleTapRadius` wins — rated (dot) preferred
    /// over unrated (speck) at an equal distance, matching the spec's "nearest
    /// marker … preferring rated over unrated." A miss (nothing within
    /// range) is a no-op, so a plain map tap still reaches Apple's own
    /// base-map label selection untouched.
    @MainActor
    private func handleMapCircleTap(at location: CGPoint, plan: MapAnnotationPlan, proxy: MapProxy) {
        func nearest(in placements: [MarkerPlacement]) -> (MarkerPlacement, CGFloat)? {
            var best: (MarkerPlacement, CGFloat)?
            for placement in placements {
                guard let point = proxy.convert(coordinate(of: placement.venue), to: .local) else { continue }
                let distance = hypot(point.x - location.x, point.y - location.y)
                guard distance <= Self.mapCircleTapRadius else { continue }
                if best == nil || distance < best!.1 {
                    best = (placement, distance)
                }
            }
            return best
        }
        if let (dot, _) = nearest(in: plan.dots) {
            selected = dot.venue
        } else if let (speck, _) = nearest(in: plan.specks) {
            selected = speck.venue
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

    /// bd#212: the button a numbered TEARDROP uses (dots/specks are native
    /// `MapCircle` overlays with no button of their own — see
    /// `handleMapCircleTap`). The min-44pt frame is attached to the BUTTON,
    /// not baked into `TeardropMarkerView`'s own layout, so even the
    /// smallest teardrop still gets a full-size tap target without the
    /// marker's own visual footprint (and therefore its collision math)
    /// growing to match.
    private func markerButton(for placement: MarkerPlacement) -> some View {
        Button {
            selected = placement.venue
        } label: {
            TeardropMarkerView(placement: placement)
        }
        .buttonStyle(.plain)
        // `alignment: .bottom` keeps the invisible tap-frame's growth
        // symmetric around the marker's TIP (the frame's bottom edge,
        // matching `Annotation(..., anchor: .bottom)`) rather than
        // recentering the whole button and shifting the visual tip away
        // from the venue's true coordinate.
        .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityLabel(Self.pinLabel(for: placement.venue))
        .accessibilityValue(placement.isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(placement.isSelected ? .isSelected : [])
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
                                // bd#219: exactly one match already settled
                                // (a citywide server answer that landed
                                // before Return, or a plain local match) is
                                // treated as an explicit selection, same as
                                // tapping that one shelf row — flies to it
                                // rather than leaving the camera on a fit
                                // for a single-item list. A server answer
                                // still in flight at the moment of Return
                                // falls through to the ordinary settled-fit
                                // path once it lands (`scheduleSearchFit`
                                // via `.onChange(of: model.venues)`) —
                                // `searchFitRegion` already flies a lone
                                // result at the same walking scale.
                                if model.venues.count == 1, let only = model.venues.first {
                                    selectSearchResult(only)
                                } else {
                                    searchFocused = false
                                }
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
                    Text(ratedCafeCountLine)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    // bd#212: no clusters/stacks left to explain — the only
                    // thing on the map that needs a legend now is what the
                    // marker number itself means.
                    Text("Numbers are Work Fit")
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

    /// "N rated · M cafés" (bd#212 — replaces "N of M spots" now that every
    /// café draws its own marker instead of collapsing into a count
    /// cluster; "rated" is the number a viewer actually cares about, so it
    /// leads). `rated` is the live, filtered `model.venues` with real Work
    /// Fit evidence (`Venue.isRated`, brewdesk#213 — honors the server's own
    /// `scoreDisplay` over the older `isObserved` heuristic); `total` is the
    /// plain loaded count — both dynamic, never hardcoded.
    private var ratedCafeCountLine: String {
        let rated = model.venues.filter(\.isRated).count
        let total = model.venues.count
        return String(
            format: String(localized: "%1$lld rated · %2$lld cafés"),
            locale: .current,
            rated,
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
    /// this instead of `defaultSpan`. bd#212 (supervisor review): bumped
    /// from 0.014 — at a typical ~390pt device width and NYC's latitude,
    /// 0.014 landed at ≈3.0 m/pt, the very EDGE of the ≈3.0–3.6 m/pt target
    /// (a user's first view should show numbered 12–13pt teardrops, not sit
    /// right at the boundary where a slightly wider device tips it into
    /// dot-only territory). 0.0155 lands mid-range (≈3.3 m/pt) with margin
    /// either way. Exact metres/point still varies by device width and
    /// latitude — this only aims the DEFAULT camera at the target; marker
    /// SIZE always reflects whatever the real settled metres/point turns
    /// out to be (`MapAnnotationPlanner.metersPerPoint(region:mapWidth:)`).
    private static let firstFixSpan = 0.0155

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
/// (bd#209, extended bd#210 with the chrome exclusion rects) — see
/// `planCache`'s doc comment on why this exists.
private struct PlanCacheKey: Equatable {
    let venues: [Venue]
    let region: RegionSnapshot?
    let mapSize: CGSize
    let selectedID: String?
    let exclusionRects: [CGRect]
}

/// Plain reference box, not `@State` itself — see `planCache`'s doc comment.
private final class PlanCacheBox {
    var key: PlanCacheKey?
    var plan: MapAnnotationPlan?
}
