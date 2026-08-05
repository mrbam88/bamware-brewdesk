import BamwareCafeKit
import Factory
import SwiftUI
import VenueKit

struct DiscoveryRootView: View {
    let auth: AuthSessionStore
    let locationService: LocationService
    @State private var model = VenuesModel(api: Container.shared.venueAPI())

    var body: some View {
        TabView {
            CafeMapScreen(model: model)
                .tabItem { Label("Explore", systemImage: "map.fill") }

            CafeListScreen(model: model)
                .tabItem { Label("Nearby", systemImage: "cup.and.saucer.fill") }

            account
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .task {
            if let coordinate = locationService.location?.coordinate {
                model.updateCenter(lat: coordinate.latitude, lng: coordinate.longitude)
            }
            await model.load()
        }
        .onChange(of: locationService.location) { _, location in
            guard let coordinate = location?.coordinate else { return }
            model.updateCenter(lat: coordinate.latitude, lng: coordinate.longitude)
            Task { await model.load() }
        }
    }

    private var account: some View {
        NavigationStack {
            List {
                if case .authenticated(let user) = auth.state {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.logout() }
                    }
                }
            }
            .navigationTitle("Account")
        }
    }
}
