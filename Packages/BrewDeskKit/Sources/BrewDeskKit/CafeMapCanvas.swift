import MapKit
import SwiftUI
import VenueKit

/// Everything the map draws, as one value (brewdesk#211).
///
/// `CafeMapCanvas` is rebuilt only when this changes. The marker plan comes
/// out of `CafeMapScreen`'s plan cache, so an unchanged plan is the same
/// array buffer and compares in constant time.
struct CafeMapCanvasContent: Equatable {
    var plan: MapAnnotationPlan
    /// A selected venue the plan did not place (chosen from the shelf, or
    /// panned away from since) still shows a full selected teardrop (bd#212,
    /// the same fallback bd#209's selected pin always used). `nil` whenever
    /// the plan already draws it.
    var unplacedSelection: Venue?
    /// Radius of a demoted rated dot, in metres at the settled zoom.
    var dotRadius: CLLocationDistance
    /// Radius of an unrated dot, in metres at the settled zoom.
    var unratedDotRadius: CLLocationDistance
    /// bd#265: unrated dots fade out between 12 and 16 m/pt.
    var unratedDotOpacity: Double
    /// Gap-fill (bd#182, feature-flagged, default OFF): grey "unverified"
    /// Apple POIs. Never part of `plan`.
    var gapFillMarkers: [AppleUnverifiedPOI]

    init(
        plan: MapAnnotationPlan, selected: Venue?, metersPerPoint: Double,
        gapFillMarkers: [AppleUnverifiedPOI]
    ) {
        self.plan = plan
        if let selected, !plan.containsVenue(id: selected.id) {
            unplacedSelection = selected
        } else {
            unplacedSelection = nil
        }
        dotRadius = Self.dotRadiusMeters(forMetersPerPoint: metersPerPoint)
        unratedDotRadius = Self.unratedDotRadiusMeters(forMetersPerPoint: metersPerPoint)
        unratedDotOpacity = MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: metersPerPoint)
        self.gapFillMarkers = gapFillMarkers
    }

    /// ~4pt apparent diameter (2pt radius) at the current zoom — matches
    /// the design's own "4pt dot, no number" city-zoom target — clamped so
    /// it neither vanishes at wide zoom nor balloons at the closest zoom.
    /// Supervisor's own starting number ("~5 m radius") is close to this at
    /// the demotion zooms (≈1.8-3.6 m/pt ⇒ 3.6-7.2m here); the clamp mainly
    /// matters at ≥7.2 m/pt, where a bare 5m would already be sub-pixel.
    static func dotRadiusMeters(forMetersPerPoint mpp: Double) -> CLLocationDistance {
        min(max(2.0 * mpp, 3.0), 15.0)
    }

    /// Same shape as `dotRadiusMeters(forMetersPerPoint:)`, a touch smaller
    /// (~3pt apparent diameter) so an unrated dot stays visually
    /// subordinate to a rated dot at the same zoom. The upper clamp covers
    /// the whole range unrated dots now draw in (bd#265: out to
    /// `MapAnnotationPlanner.unratedDotHiddenMetersPerPoint`).
    static func unratedDotRadiusMeters(forMetersPerPoint mpp: Double) -> CLLocationDistance {
        min(max(1.5 * mpp, 2.0), 1.5 * MapAnnotationPlanner.unratedDotHiddenMetersPerPoint)
    }
}

/// What the canvas tells its screen (brewdesk#211). A plain reference box,
/// not observed and not part of the canvas's equality: `CafeMapScreen`
/// rewrites every closure on each of its own body evaluations, so a canvas
/// whose body was skipped still calls the screen's CURRENT handlers, never a
/// copy captured several renders ago.
@MainActor
final class CafeMapCanvasActions {
    /// The live map's proxy and layout size, recorded by the canvas so the
    /// screen can read the camera without sitting inside the `MapReader`.
    fileprivate(set) var proxy: MapProxy?
    fileprivate(set) var size: CGSize = .zero

    /// Every frame of a drag or pinch on the map.
    var gestureChanged: () -> Void = {}
    /// A drag or pinch lifted.
    var gestureEnded: () -> Void = {}
    /// Built-in double-tap zoom (no drag or magnify phase).
    var doubleTapped: () -> Void = {}
    /// Any touch-down on the map.
    var touchedDown: () -> Void = {}
    /// A tap at a point in the map's own coordinate space.
    var tapped: (CGPoint) -> Void = { _ in }
    /// MapKit reports the camera at rest.
    var cameraCameToRest: (MKCoordinateRegion, Double) -> Void = { _, _ in }
    /// The Map's own layout frame, in `CafeMapScreen.mapPlaneSpace`.
    var windowFrameChanged: (CGRect) -> Void = { _ in }
    var appleFeatureSelected: (MapFeature?) -> Void = { _ in }
    var venueSelected: (Venue) -> Void = { _ in }
    var gapFillSelected: (AppleUnverifiedPOI) -> Void = { _ in }

    fileprivate func record(proxy: MapProxy, size: CGSize) {
        self.proxy = proxy
        self.size = size
    }
}

/// The `Map` and everything drawn on it, split out of `CafeMapScreen`
/// (brewdesk#211).
///
/// Rebuilding the `Map`'s content is the expensive part of this screen: one
/// evaluation with ~220 markers costs a 120-170 ms frame whether or not
/// anything on the map changed. Inside `CafeMapScreen.body` that price was
/// paid for every header, shelf, search and loading-state change. Here it is
/// paid only when `content` — a plain `Equatable` value — actually differs.
/// Nothing in this view reads the model or the environment.
struct CafeMapCanvas: View, Equatable {
    @Binding var position: MapCameraPosition
    /// `selection` (bd#182) binds ONLY Apple's own base-map POI labels —
    /// our pins and dots keep their own tap flow, so this is a second,
    /// independent selection channel, not a replacement.
    @Binding var appleFeatureSelection: MapFeature?
    let content: CafeMapCanvasContent
    let actions: CafeMapCanvasActions

    static func == (lhs: CafeMapCanvas, rhs: CafeMapCanvas) -> Bool {
        lhs.content == rhs.content && lhs.actions === rhs.actions
    }

    var body: some View {
        let _ = MapPerfProbe.mapBodyEvaluated()
        MapReader { proxy in
            GeometryReader { geometry in
                let _ = actions.record(proxy: proxy, size: geometry.size)
                Map(position: $position, selection: $appleFeatureSelection) {
                    UserAnnotation()
                    teardropAnnotations
                    dotCircles
                    unplacedSelectionAnnotation
                    gapFillAnnotations
                }
                // Apple's base-map labels are restricted to food/drink
                // categories (bd#182) — the only ones this screen makes
                // selectable/relevant; every other Apple POI label (transit,
                // parks, shops, …) stays off the map entirely rather than
                // being selectable-but-ignored.
                .mapStyle(.standard(pointsOfInterest: .including(CafeMapScreen.selectablePointsOfInterest)))
                // Suppresses Apple's own callout bubble: our own
                // `AppleFeatureCard` sheet is the single source of truth for
                // what a selected feature looks like, so the system
                // presentation would otherwise double up on it. A non-empty
                // `Marker` still highlights the tapped label on the map
                // itself while our sheet is up.
                .mapFeatureSelectionContent { feature in
                    Marker(feature.title ?? "", coordinate: feature.coordinate)
                }
                .onChange(of: appleFeatureSelection) { _, newValue in
                    actions.appleFeatureSelected(newValue)
                }
                // bd#265: where the Map's own layout frame sits inside the
                // map plane — see `CafeMapScreen.mapWindowFrame`.
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(CafeMapScreen.mapPlaneSpace))
                } action: { frame in
                    actions.windowFrameChanged(frame)
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    actions.cameraCameToRest(context.region, context.camera.heading)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            MapPerfProbe.gestureChanged()
                            actions.gestureChanged()
                        }
                        .onEnded { _ in
                            MapPerfProbe.gestureEnded()
                            actions.gestureEnded()
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { _ in
                            MapPerfProbe.gestureChanged()
                            actions.gestureChanged()
                        }
                        .onEnded { _ in
                            MapPerfProbe.gestureEnded()
                            actions.gestureEnded()
                        }
                )
                // Built-in double-tap zoom has no drag or magnify phase.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { actions.doubleTapped() }
                )
                // Any touch on the map — a tap or the start of a pan —
                // resigns the search field (brewdesk#87). `minimumDistance:
                // 0` fires on touch-down, and `simultaneousGesture` keeps it
                // from stealing the touch from pin buttons or the other map
                // gestures above.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in actions.touchedDown() }
                )
                // bd#212 (supervisor revision): `.dot` markers are native
                // `MapCircle` overlays, not SwiftUI buttons, so they need
                // their own tap dispatch. `SpatialTapGesture` is
                // simultaneous with every gesture above, so it never blocks
                // panning/zooming/Apple-label selection; it only acts when
                // the tap actually lands near one of these markers.
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in actions.tapped(value.location) }
                )
            }
        }
    }

    // MARK: - Map content (representation from MapAnnotationPlanner,
    // styling from MapAnnotationViews — see brewdesk#54/#55)

    /// bd#212 (supervisor revision): only TEARDROPS are real SwiftUI
    /// `Annotation`s — identified by venue id, which keeps a size/selection
    /// change an in-place update of the SAME hosted annotation view rather
    /// than a remove+insert. Demoted dots and overflow unrated dots are
    /// native `MapCircle` overlay content (`dotCircles`) — the perf fix for
    /// #211's stalls: hosting every one of ~150-200 unrated venues as a
    /// SwiftUI annotation view (each wrapped in a 44pt Button) was the real
    /// cost, not view type churn. bd#265 brings back a CAPPED number of
    /// unrated venues as real pins (`MapAnnotationPlanner.maxUnratedPins`),
    /// inside the total the pan measurement already covers.
    /// bd#221: `anchor` is no longer always `.bottom` — a teardrop carrying
    /// a name label reports WIDER content (the label is a real `HStack`
    /// sibling now, not an overflow overlay MapKit never measured; see
    /// `TeardropMarkerView.body`'s doc comment), so the anchor must shift
    /// to the pin's own fraction of that wider content or the tip would
    /// visibly slide off the venue's true coordinate.
    @MapContentBuilder
    private var teardropAnnotations: some MapContent {
        ForEach(content.plan.teardrops) { placement in
            Annotation("", coordinate: coordinate(of: placement.venue), anchor: TeardropMarkerView.annotationAnchor(for: placement)) {
                markerButton(for: placement)
            }
        }
    }

    /// bd#212 (supervisor revision): demoted rated venues and overflow
    /// unrated venues, drawn as cheap native `MapCircle`s — MapKit's own
    /// overlay primitive, never a hosted SwiftUI view.
    ///
    /// Radius is derived from the LIVE metres-per-point, not a bare fixed
    /// metres constant: a pure fixed radius (the supervisor's own starting
    /// suggestion, "~5 m") shrinks toward invisibility once a rated venue is
    /// a `.dot` because the WHOLE zoom is past the teardrop threshold (city
    /// zoom, ≥7.2 m/pt) rather than because of a collision demotion at a
    /// closer zoom — a 5m dot at 7.2 m/pt is well under 1pt on screen,
    /// which undersells the "4pt dot" visual target that same zoom level
    /// is supposed to read as. Scaling the radius by the settled mpp keeps
    /// a dot's ON-SCREEN size roughly constant across zoom levels —
    /// still a cheap native overlay, just sized to actually be seen.
    @MapContentBuilder
    private var dotCircles: some MapContent {
        // bd#265: unrated dots no longer vanish at 5 m/pt — full strength
        // to 12 m/pt, then a linear fade (the planner stops emitting them
        // where this reaches zero).
        let unratedFill = BrewDeskPalette.markerUnratedDotFill.opacity(content.unratedDotOpacity)
        ForEach(content.plan.dots) { placement in
            MapCircle(center: coordinate(of: placement.venue), radius: content.dotRadius)
                .foregroundStyle(BrewDeskPalette.markerFill(score: placement.venue.workScore))
        }
        ForEach(content.plan.unratedDots) { placement in
            MapCircle(center: coordinate(of: placement.venue), radius: content.unratedDotRadius)
                .foregroundStyle(unratedFill)
        }
    }

    @MapContentBuilder
    private var unplacedSelectionAnnotation: some MapContent {
        if let selected = content.unplacedSelection {
            Annotation("", coordinate: coordinate(of: selected), anchor: .bottom) {
                markerButton(for: MarkerPlacement(
                    venue: selected,
                    kind: .teardrop(diameter: MapAnnotationPlanner.selectedDiameter),
                    showsNumber: selected.isRated,
                    isSelected: true,
                    isUnrated: !selected.isRated
                ))
            }
        }
    }

    @MapContentBuilder
    private var gapFillAnnotations: some MapContent {
        ForEach(content.gapFillMarkers) { poi in
            Annotation("", coordinate: poi.coordinate) {
                gapFillButton(for: poi)
            }
        }
    }

    /// bd#212: the button a TEARDROP uses (dots are native `MapCircle`
    /// overlays with no button of their own — see
    /// `CafeMapScreen.handleMapCircleTap`). The min-44pt frame is attached
    /// to the BUTTON, not baked into `TeardropMarkerView`'s own layout, so
    /// even the smallest teardrop still gets a full-size tap target without
    /// the marker's own visual footprint (and therefore its collision math)
    /// growing to match.
    private func markerButton(for placement: MarkerPlacement) -> some View {
        Button {
            actions.venueSelected(placement.venue)
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
        .accessibilityLabel(
            placement.isUnrated
                ? CafeMapScreen.unratedPinLabel(for: placement.venue)
                : CafeMapScreen.pinLabel(for: placement.venue)
        )
        .accessibilityValue(placement.isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(placement.isSelected ? .isSelected : [])
        // bd#219 UI-test seam: a dedicated identifier for the SELECTED
        // marker specifically (every marker already carries the café's
        // name in its label) — lets a test assert the selected teardrop
        // exists and is hittable after a search fly-to without depending
        // on label text alone, which every OTHER unselected marker on
        // screen also partially matches.
        .accessibilityIdentifier(placement.isSelected ? "map-selected-marker" : "map-marker")
    }

    /// A tapped gap-fill marker: already pre-deduped against our venues
    /// (`AppleGapFillService.fetch`), so this always opens the card.
    private func gapFillButton(for poi: AppleUnverifiedPOI) -> some View {
        Button {
            actions.gapFillSelected(poi)
        } label: {
            AppleUnverifiedPin()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(poi.name), unverified, not yet in BrewDesk")
        .accessibilityIdentifier("apple-gap-fill-pin")
    }

    private func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }
}
