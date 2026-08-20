import BrewDeskKit
import SwiftUI
import VenueKit

struct DiscoveryRootView: View {
    let configuration: AppConfiguration
    let locationService: LocationService
    private let venueListing: any VenueListing
    private let venueDetails: any VenueDetailServing
    @State private var model: VenuesModel
    @State private var savedVenues = SavedVenuesStore()

    init(
        configuration: AppConfiguration,
        locationService: LocationService,
        venueListing: any VenueListing,
        venueDetails: any VenueDetailServing
    ) {
        self.configuration = configuration
        self.locationService = locationService
        self.venueListing = venueListing
        self.venueDetails = venueDetails
        _model = State(initialValue: VenuesModel(api: venueListing))
    }

    var body: some View {
        let request = model.request

        TabView {
            CafeMapScreen(model: model, savedVenues: savedVenues)
                .tabItem { Label("Explore", systemImage: "map.fill") }

            CafeListScreen(model: model, savedVenues: savedVenues)
                .tabItem { Label("Nearby", systemImage: "cup.and.saucer.fill") }

            savedTab
                .tabItem {
                    Label {
                        Text("saved_tab_title")
                    } icon: {
                        Image(systemName: "bookmark.fill")
                    }
                }
        }
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
    }

    private var savedTab: some View {
        NavigationStack {
            SavedCafesScreen(savedVenues: savedVenues, venueDetails: venueDetails, listing: venueListing)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            about
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                    }
                }
        }
    }

    private var about: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(configuration.appName)
                        .font(.title2.bold())
                    Text(LocalizedStringKey(configuration.tagline))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Help & legal") {
                Link("Support", destination: configuration.supportURL)
                Link("Privacy Policy", destination: configuration.privacyURL)
                Link("Terms of Use", destination: configuration.termsURL)
            }

            Section("Data sources") {
                Link("OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }
        .navigationTitle("About")
    }
}
