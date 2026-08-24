import SwiftUI
import VenueKit

/// You tab root (brewdesk#117 — was reached from the Saved toolbar as
/// "Account"; the tab restructure makes it a tab of its own and folds in
/// what used to be `DiscoveryRootView`'s private About screen). Reads as a
/// deliberate About surface even in the `STORE_SURFACE_GATED` build, where
/// the account card is hidden: How scoring works, Contact & Content Rules,
/// and Support/Privacy/Terms/credits/version still carry the screen.
///
/// Order matches the brewdesk#117 spec: (1) account card / sign-in — Apple
/// 1.2 requires accounts, report/block, published contact, and in-app
/// deletion before any UGC ships, and this section is gated by
/// `StoreSurface.isGated` (moved here from the old Saved-toolbar entry
/// point, which gated the whole entry link instead); (2) How scoring works
/// + Contact & Content Rules; (3) About (Support, Privacy, Terms, credits,
/// version). Resolves its own auth service (environment override →
/// `AccountServiceResolver`) so the composition root stays untouched.
public struct AccountScreen: View {
    @Environment(\.accountAuthService) private var injectedService
    @Environment(\.accountAboutInfo) private var aboutInfo

    @State private var model: AccountModel?
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    #if DEBUG
    @State private var envTapCount = 0
    @State private var showEnvPicker = false
    #endif

    private enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
    }

    public init() {}

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
                model = AccountModel(
                    auth: injectedService ?? AccountServiceResolver.resolve(),
                    sessions: .shared
                )
            }
        }
        #if DEBUG
        .sheet(isPresented: $showEnvPicker) { environmentPicker }
        #endif
    }

    @ViewBuilder
    private func content(_ model: AccountModel) -> some View {
        List {
            // Account card / sign-in — exactly as it existed at the old
            // Saved-toolbar entry point, just gated here instead of at the
            // (now-removed) entry link (brewdesk#67, brewdesk#117).
            if !StoreSurface.isGated {
                if let session = model.sessions.session {
                    signedIn(model, session: session)
                } else {
                    signedOut(model)
                }
            }

            Section {
                NavigationLink {
                    MethodologyScreen()
                } label: {
                    Label("How scoring works", systemImage: "info.circle")
                }
                .accessibilityIdentifier("methodology-link")

                NavigationLink {
                    AccountPoliciesScreen()
                } label: {
                    Label("Contact & Content Rules", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("account-policies-entry")
            }

            aboutSection
        }
    }

    // MARK: - Signed in

    @ViewBuilder
    private func signedIn(_ model: AccountModel, session: AuthSession) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.user.name)
                    .font(.headline)
                Text(session.user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account-signed-in")
        } footer: {
            Text("Your account will link community contributions to you. Everything else in BrewDesk works without it.")
        }

        Section {
            Button("Sign Out") {
                model.signOut()
            }
            .accessibilityIdentifier("account-sign-out")

            NavigationLink {
                AccountDeletionScreen(model: model)
            } label: {
                Text("Delete Account")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("account-delete-entry")
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private func signedOut(_ model: AccountModel) -> some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("account-mode-toggle")

            if mode == .createAccount {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .accessibilityIdentifier("account-name-field")
            }
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("account-email-field")
            SecureField("Password (at least 8 characters)", text: $password)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("account-password-field")

            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("account-error")
            }

            Button {
                Task { await submit(model) }
            } label: {
                if model.isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit || model.isWorking)
            .accessibilityIdentifier("account-submit")
        } header: {
            Text(mode == .signIn ? "Welcome back" : "Join BrewDesk")
        } footer: {
            Text("No account needed to browse, save spots, or share observations. An account only links future community contributions to a name you choose.")
        }
    }

    // MARK: - About (brewdesk#117 — folded in from `DiscoveryRootView`'s
    // old private About screen so the You tab reads as a complete surface
    // on its own, gated build included)

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

    private var canSubmit: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passwordOK = password.count >= 8
        let nameOK = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOK && passwordOK && nameOK
    }

    private func submit(_ model: AccountModel) async {
        switch mode {
        case .signIn:
            await model.signIn(email: email, password: password)
        case .createAccount:
            await model.signUp(
                email: email,
                password: password,
                name: name.trimmingCharacters(in: .whitespaces)
            )
        }
        if model.sessions.isSignedIn {
            password = ""
        }
    }
}

// MARK: - About info injection

/// Static app metadata the About section renders — name/tagline/legal URLs.
/// Mirrors `\.accountAuthService`'s optional-first pattern isn't needed here
/// since every value has a sensible BrewDesk-shaped default; the app target
/// still overrides it from its own `AppConfiguration` so there is one source
/// of truth for these strings/URLs (`RootView` → `DiscoveryRootView` →
/// `.environment(\.accountAboutInfo, ...)`).
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
