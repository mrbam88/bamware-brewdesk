import BamwareAccounts
import BamwareAccountUI
import SwiftUI
import VenueKit

/// You tab root (bamware-brewdesk#174 — replaces the retired
/// BrewDeskKit-local `AccountScreen`/`AccountModel`/`AccountSessionStore`
/// with the shared `BamwareAccounts`/`BamwareAccountUI` packages,
/// bamware-ios B5-B8). Keeps the brewdesk#117 shape — account entry, How
/// scoring works, Contact & Content Rules, About — as one list-driven
/// surface so the tab still reads as a complete surface at a glance.
///
/// The package's `SignInScreen`/`AccountScreen` are each a complete,
/// self-scrolling screen (their own `ScrollView`/`List` + background) —
/// nesting either one's scrolling container inside this tab's own `List`
/// does not lay out (an unbounded-height scroll view inside another one).
/// So they are presented as sheets from a single "Your account" row
/// instead of embedded inline; that composition choice is explicitly the
/// app's to make (`BamwareAccountUI`'s README: "this package draws no
/// navigation between AccountScreen and SignInScreen"). Each sheet
/// auto-dismisses when `AccountModel.sessions.isSignedIn` flips to the
/// state that no longer matches it (signed in while looking at "Sign In";
/// signed out — including via account deletion — while looking at
/// "Account"), so the You tab root is always what the user sees next.
public struct YouTabScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accountAboutInfo) private var aboutInfo
    @Environment(\.launchEnvironment) private var launchEnvironment

    @State private var model: AccountModel?
    @State private var isAccountPresented = false
    @State private var isSignInPresented = false
    #if DEBUG
    @State private var envTapCount = 0
    @State private var showEnvPicker = false
    #endif

    public init() {}

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("You")
        .task {
            if model == nil {
                model = BrewDeskAccountStack.makeModel(environment: launchEnvironment)
            }
        }
        #if DEBUG
        .sheet(isPresented: $showEnvPicker) { environmentPicker }
        #endif
    }

    @ViewBuilder
    private func content(_ model: AccountModel) -> some View {
        List {
            accountSection(model)

            Section {
                NavigationLink {
                    MethodologyScreen()
                } label: {
                    Label("How scoring works", systemImage: "info.circle")
                }
                .accessibilityIdentifier("methodology-link")

                NavigationLink {
                    ContentPoliciesScreen()
                } label: {
                    Label("Contact & Content Rules", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("account-policies-entry")
            }

            aboutSection
        }
        .sheet(isPresented: $isAccountPresented) {
            NavigationStack {
                AccountScreen(model: model, theme: theme)
                    .navigationTitle("Account")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isAccountPresented = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isSignInPresented) {
            NavigationStack {
                signInSheetContent(model)
            }
        }
        .onChange(of: model.sessions.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                isSignInPresented = false
            } else {
                isAccountPresented = false
            }
        }
    }

    // MARK: - Account entry (brewdesk#174: the only row this ticket's
    // "why bother signing in" copy and the package screens live behind)

    @ViewBuilder
    private func accountSection(_ model: AccountModel) -> some View {
        Section {
            if model.sessions.isSignedIn, let session = model.sessions.session {
                Button {
                    isAccountPresented = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.user.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(session.user.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("account-entry")
            } else {
                Button {
                    isSignInPresented = true
                } label: {
                    Text("Sign In or Create Account")
                }
                .accessibilityIdentifier("account-entry")
            }
        } header: {
            Text("Your account")
        } footer: {
            if !model.sessions.isSignedIn {
                Text(Self.signInValuePropText)
            }
        }
    }

    /// BrewDesk's own copy for why an account is worth having — sync across
    /// devices and future alerts (saved-spot sync is brewdesk C10, alerts
    /// are the push platform's D package; both out of this ticket's scope,
    /// but the value prop is the reason to sign in now). Shown twice: as
    /// this section's footer, and again ahead of the sign-in form itself
    /// (`signInSheetContent`) and on the onboarding step
    /// (`AccountOnboardingHost`) — one string, three call sites.
    public static let signInValuePropText =
        "Create an account to keep your saved spots with you across devices and hear about changes to the ones you're watching. Everything else in BrewDesk — browsing, saving locally, rating a visit — works without one."

    /// The value-prop copy renders ABOVE the package's `SignInScreen`
    /// (its own header/buttons/form), not inside it — `SignInScreen` has no
    /// slot for app-supplied copy, so this is a plain `VStack` stacking the
    /// two, matching how `AccountOnboardingStep` takes app copy as
    /// title/body instead.
    private func signInSheetContent(_ model: AccountModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sync spots. Get alerts.")
                    .font(.title3.bold())
                Text(Self.signInValuePropText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account-sign-in-value-prop")

            SignInScreen(model: model, theme: theme)
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { isSignInPresented = false }
            }
        }
    }

    // MARK: - About (brewdesk#117 — folded in from `DiscoveryRootView`'s
    // old private About screen so the You tab reads as a complete surface
    // on its own)

    private var aboutSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(aboutInfo.appName)
                        .font(.title2.bold())
                    Text(LocalizedStringKey(aboutInfo.tagline))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Help & legal") {
                Link("Support", destination: aboutInfo.supportURL)
                Link("Privacy Policy", destination: aboutInfo.privacyURL)
                Link("Terms of Use", destination: aboutInfo.termsURL)
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

// MARK: - About info injection

/// Static app metadata the About section renders — name/tagline/legal URLs.
/// The app target overrides it from its own `AppConfiguration` so there is
/// one source of truth for these strings/URLs (`RootView` ->
/// `DiscoveryRootView` -> `.environment(\.accountAboutInfo, ...)`).
public struct AccountAboutInfo: Sendable {
    public let appName: String
    public let tagline: String
    public let supportURL: URL
    public let privacyURL: URL
    public let termsURL: URL

    public init(appName: String, tagline: String, supportURL: URL, privacyURL: URL, termsURL: URL) {
        self.appName = appName
        self.tagline = tagline
        self.supportURL = supportURL
        self.privacyURL = privacyURL
        self.termsURL = termsURL
    }

    public static let brewDesk = AccountAboutInfo(
        appName: "BrewDesk",
        tagline: "Find a spot where the Wi-Fi works and laptops are welcome.",
        supportURL: URL(string: "https://bamware.io/brewdesk/support")!,
        privacyURL: URL(string: "https://bamware.io/brewdesk/privacy")!,
        termsURL: URL(string: "https://bamware.io/brewdesk/terms")!
    )
}

private struct AccountAboutInfoKey: EnvironmentKey {
    static let defaultValue = AccountAboutInfo.brewDesk
}

extension EnvironmentValues {
    public var accountAboutInfo: AccountAboutInfo {
        get { self[AccountAboutInfoKey.self] }
        set { self[AccountAboutInfoKey.self] = newValue }
    }
}
