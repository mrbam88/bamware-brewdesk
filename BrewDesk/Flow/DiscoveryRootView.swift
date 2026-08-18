import BrewDeskKit
import Factory
import SwiftUI
import VenueKit

struct DiscoveryRootView: View {
    let configuration: AppConfiguration
    let locationService: LocationService
    @State private var model = VenuesModel(api: Container.shared.venueAPI())

    var body: some View {
        let request = model.request

        TabView {
            CafeMapScreen(model: model)
                .tabItem { Label("Explore", systemImage: "map.fill") }

            CafeListScreen(model: model)
                .tabItem { Label("Nearby", systemImage: "cup.and.saucer.fill") }

            about
                .tabItem { Label("About", systemImage: "info.circle") }
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

    private var about: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(configuration.appName)
                            .font(.title2.bold())
                        Text(configuration.tagline)
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
}
