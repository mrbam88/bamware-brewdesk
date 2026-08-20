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
    #if DEBUG
    @State private var envTapCount = 0
    @State private var showEnvPicker = false
    #endif

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

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Self.marketingVersion)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                #if DEBUG
                .onTapGesture {
                    envTapCount += 1
                    if envTapCount >= 5 {
                        envTapCount = 0
                        showEnvPicker = true
                    }
                }
                #endif
            }
        }
        .navigationTitle("About")
        #if DEBUG
        .sheet(isPresented: $showEnvPicker) { environmentPicker }
        #endif
    }

    private static var marketingVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    #if DEBUG
    private var environmentPicker: some View {
        NavigationStack {
            List(DebugEnvironment.allCases) { env in
                Button {
                    DebugEnvironmentStore.shared.current = env
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(env.label)
                            Text(env.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if DebugEnvironmentStore.shared.current == env {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Environment")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
    #endif
}
