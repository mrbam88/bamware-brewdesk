import BamwareCafeKit
import Factory
import SwiftUI
import VenueKit

struct DiscoveryRootView: View {
    private enum Tab: Hashable {
        case explore, nearby, ask, account
    }

    let auth: AuthSessionStore
    let locationService: LocationService
    @State private var model = VenuesModel(api: Container.shared.venueAPI())
    @State private var selectedTab: Tab = ProcessInfo.processInfo.arguments.contains("-UITestOpenConversation")
        ? .ask
        : .explore

    var body: some View {
        TabView(selection: $selectedTab) {
            CafeMapScreen(model: model)
                .tabItem { Label("Explore", systemImage: "map.fill") }
                .tag(Tab.explore)

            CafeListScreen(model: model)
                .tabItem { Label("Nearby", systemImage: "cup.and.saucer.fill") }
                .tag(Tab.nearby)

            ConversationScreen(currentUser: conversationUser)
                .tabItem { Label("Ask", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.ask)

            account
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(Tab.account)
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

    private var conversationUser: ConversationParticipant {
        if case .authenticated(let user) = auth.state {
            return ConversationParticipant(id: user.userId, displayName: user.name, kind: .human)
        }
        return ConversationParticipant(id: "local-user", displayName: "You", kind: .human)
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
