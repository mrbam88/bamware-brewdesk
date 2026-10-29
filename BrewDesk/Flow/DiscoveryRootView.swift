import BrewDeskKit
import SwiftUI
import VenueKit

struct DiscoveryRootView: View {
    /// Tab selection is programmable so empty states can route the user
    /// (Saved's "Browse Spots" CTA — ui-review-2026-08-21 finding 5).
    /// brewdesk#117: Explore + Nearby collapsed into one Spots surface, and
    /// Account became its own You tab. bd#247 adds Ask (grounded café chat),
    /// shown only when the engine's health advertises `features.chat` (or a
    /// scenario launch is active) — so three tabs on an old engine, four on
    /// a chat-enabled one.
    enum DiscoveryTab: Hashable {
        case spots, saved, ask, you
    }

    let configuration: AppConfiguration
    let locationService: LocationService
    private let venueListing: any VenueListing
    private let venueDetails: any VenueDetailServing
    @State private var model: VenuesModel
    @State private var savedVenues: SavedVenuesStore
    // nil for scenario/UI-test launches (bamware-brewdesk#175): those keep
    // plain local `SavedVenuesStore()` persistence, same as before this
    // ticket, so DegradedStateTests' Saved-tab cases stay deterministic and
    // make no real network call. Only a normal launch gets the server sync
    // adapter, and only it needs foreground/appear sync ticks.
    @State private var savedVenuesSync: ServerSavedVenuePersistence?
    /// bd#247: owned here (not in `AskScreen`) so the transcript survives
    /// tab switches for the life of the discovery root, like `model` does.
    @State private var chatModel: ChatModel
    @State private var connectivity = ConnectivityMonitor()
    @State private var selectedTab: DiscoveryTab = .spots
    @Environment(\.scenePhase) private var scenePhase

    init(
        configuration: AppConfiguration,
        locationService: LocationService,
        venueListing: any VenueListing,
        venueDetails: any VenueDetailServing,
        chatClient: any ChatClient,
        snapshot: [Venue] = []
    ) {
        self.configuration = configuration
        self.locationService = locationService
        self.venueListing = venueListing
        self.venueDetails = venueDetails
        _model = State(initialValue: VenuesModel(api: venueListing, snapshot: snapshot))
        // Location rides along only with a real authorized fix — denied,
        // undetermined, or no fix yet all send no `location` at all.
        _chatModel = State(initialValue: ChatModel(client: chatClient, locationProvider: {
            guard locationService.isAuthorized, let coordinate = locationService.location?.coordinate else {
                return nil
            }
            return ChatLocation(lat: coordinate.latitude, lng: coordinate.longitude)
        }))
        if LaunchEnvironment.current.scenario != nil {
            _savedVenues = State(initialValue: SavedVenuesStore())
            _savedVenuesSync = State(initialValue: nil)
        } else {
            let sync = ServerSavedVenuePersistence(
                syncing: SavedSpotsSyncClient(),
                tokenProvider: { await BrewDeskAccountTenant.freshAccessToken() }
            )
            _savedVenues = State(initialValue: SavedVenuesStore(persistence: sync))
            _savedVenuesSync = State(initialValue: sync)
        }
    }

    var body: some View {
        let request = model.request

        TabView(selection: $selectedTab) {
            CafeMapScreen(model: model, savedVenues: savedVenues)
                .tabItem {
                    Label("Spots", systemImage: "map.fill")
                        .accessibilityIdentifier("tab-spots")
                }
                .tag(DiscoveryTab.spots)

            savedTab
                .tabItem {
                    Label {
                        Text("saved_tab_title")
                    } icon: {
                        Image(systemName: "bookmark.fill")
                    }
                    .accessibilityIdentifier("tab-saved")
                }
                .tag(DiscoveryTab.saved)

            if showsAskTab {
                askTab
                    .tabItem {
                        Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                            .accessibilityIdentifier("tab-ask")
                    }
                    .tag(DiscoveryTab.ask)
            }

            youTab
                .tabItem {
                    Label("You", systemImage: "person.circle")
                        .accessibilityIdentifier("tab-you")
                }
                .tag(DiscoveryTab.you)
        }
        // Warm Utilitarian (brewdesk#98): the primary green becomes the
        // selected-tab accent. iOS 26's floating glass tab bar already draws
        // the selected item as a filled circle inside the glass pill from
        // this tint — no custom pill container needed (and none was in the
        // fence: layout/composition of the tab bar itself is untouched,
        // only its accent color). iOS 17 falls back to a tinted icon, the
        // same fallback shape the rest of the app already uses for glass.
        .tint(BrewDeskPalette.roast)
        .environment(\.locationDenied, locationService.isDenied)
        // brewdesk#149: past the intro, the map still offers one way to ask.
        .environment(\.locationUndetermined, locationService.isUndetermined)
        .environment(\.requestLocationAccess) { locationService.requestAccess() }
        // brewdesk#117: the You tab's About section reads its copy/URLs from
        // here instead of hardcoding them a second time.
        .environment(
            \.accountAboutInfo,
            AccountAboutInfo(
                appName: configuration.appName,
                tagline: configuration.tagline,
                supportURL: configuration.supportURL,
                privacyURL: configuration.privacyURL,
                termsURL: configuration.termsURL
            )
        )
        // Dataset stats are independent of the venue request and the TabView
        // always exists — the strip itself cannot load them (brewdesk#34).
        .task { await model.loadHealthIfNeeded() }
        // Cold start (brewdesk#28): a reconnect retries a failed load so the
        // snapshot gives way to live data without a relaunch.
        .task { connectivity.start() }
        .onChange(of: connectivity.isOnline) { wasOnline, isOnline in
            guard wasOnline == false, isOnline == true, case .failed = model.phase else { return }
            model.retry()
        }
        // Saved-spots sync (bamware-brewdesk#175): first appearance merges
        // server ∪ local for whoever is signed in (or reports local-only,
        // no prompt, if nobody is); returning to the foreground flushes the
        // offline write queue. Both are no-ops when `savedVenuesSync` is
        // nil (scenario/UI-test launches).
        .task { await savedVenuesSync?.syncIfNeeded(); savedVenues.reload() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let savedVenuesSync else { return }
            Task {
                await savedVenuesSync.syncIfNeeded()
                savedVenues.reload()
            }
        }
        // bd#198 root cause: `request` changes whenever the viewport does
        // (a "Search this area" tap, a manual pan), so this task re-runs on
        // every one of those too — not just on a real location change. It
        // used to ask `updateCenterIfNeeded` unconditionally here, and that
        // call used to accept ANY differing coordinate, so a GPS fix that
        // simply differed from the freshly-explored viewport would win and
        // overwrite it, then `CafeMapScreen.applyCenterChange()` would move
        // the camera back to the phone's location — every later GPS tick
        // repeated it. `updateCenterIfNeeded` now refuses to apply once the
        // model is `.exploredViewport` (see `VenuesModel.centerSource`), so
        // this branch only ever "wins" (and skips loading the request
        // as-is) while the model is still following the user — a request
        // that came from `updateViewport` is always loaded as-is.
        .task(id: request) {
            if let coordinate = locationService.location?.coordinate,
               model.updateCenterIfNeeded(lat: coordinate.latitude, lng: coordinate.longitude) {
                return
            }
            await model.load(request)
        }
        .onChange(of: locationService.location) { _, location in
            guard let coordinate = location?.coordinate else { return }
            model.updateCenterIfNeeded(lat: coordinate.latitude, lng: coordinate.longitude)
        }
        #if DEBUG
        .overlay(alignment: .top) {
            if DebugEnvironmentStore.shared.current != .production {
                Text(verbatim: "ENV: \(DebugEnvironmentStore.shared.current.label)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
        }
        #endif
    }

    private var savedTab: some View {
        NavigationStack {
            SavedCafesScreen(
                savedVenues: savedVenues,
                venueDetails: venueDetails,
                listing: venueListing,
                browseSpots: { selectedTab = .spots }
            )
        }
    }

    private var youTab: some View {
        NavigationStack {
            YouTabScreen()
        }
    }

    /// bd#247: the engine says whether chat is live (`GET /v1/health`
    /// `features.chat`); a scenario launch always shows the tab so the
    /// fixture conversation is testable without the endpoint.
    private var showsAskTab: Bool {
        LaunchEnvironment.current.scenario != nil || model.health?.features?.chat == true
    }

    private var askTab: some View {
        NavigationStack {
            AskScreen(model: chatModel, savedVenues: savedVenues)
        }
    }
}
