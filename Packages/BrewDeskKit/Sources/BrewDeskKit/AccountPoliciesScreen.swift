import SwiftUI
import VenueKit

/// Contact method + content rules (brewdesk#48; Apple 1.2 requires published
/// contact information and clear UGC rules). Also manages the device-local
/// blocked-contributors list so a block is always reversible.
public struct AccountPoliciesScreen: View {
    private let blockStore: ContributorBlockStore
    @State private var blockedNames: [String] = []

    public init(blockStore: ContributorBlockStore = .shared) {
        self.blockStore = blockStore
    }

    public var body: some View {
        List {
            contactSection
            rulesSection
            blockedSection
        }
        .navigationTitle("Contact & Content Rules")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { blockedNames = blockStore.blockedNames }
    }

    private var contactSection: some View {
        Section {
            if let url = URL(string: "mailto:bmalik.ee@gmail.com") {
                Link(destination: url) {
                    Label("bmalik.ee@gmail.com", systemImage: "envelope")
                }
                .accessibilityIdentifier("account-contact-email")
            }
        } header: {
            Text("Contact")
        } footer: {
            Text("Questions, feedback, or concerns about content — email us. Reports of objectionable content are acted on within 24 hours: the content is removed and the contributor is ejected.")
        }
    }

    private var rulesSection: some View {
        Section {
            rule("Photos and observations must be about the café as a workspace.")
            rule("No offensive, harassing, or discriminatory content.")
            rule("No personal information about other people.")
            rule("No spam, ads, or misleading content.")
        } header: {
            Text("Community content rules")
        } footer: {
            Text("Report any photo from its fullscreen view, or block a contributor to hide their photos on this device.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-content-rules")
    }

    @ViewBuilder
    private var blockedSection: some View {
        if !blockedNames.isEmpty {
            Section {
                ForEach(blockedNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Unblock") {
                            blockStore.unblock(name)
                            blockedNames = blockStore.blockedNames
                        }
                        .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("account-blocked-contributor")
                }
            } header: {
                Text("Blocked contributors")
            } footer: {
                Text("Their photos are hidden on this device.")
            }
        }
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .font(.subheadline)
    }
}
