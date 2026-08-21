import SwiftUI
import VenueKit

/// The optional account (brewdesk#48). BrewDesk works fully anonymously —
/// this screen exists because Apple 1.2 requires accounts, report/block,
/// published contact, and in-app deletion before any UGC ships. Reached from
/// the Saved tab toolbar; resolves its own auth service (environment override
/// → `AccountServiceResolver`) so the composition root stays untouched.
public struct AccountScreen: View {
    @Environment(\.accountAuthService) private var injectedService

    @State private var model: AccountModel?
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""

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
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = AccountModel(
                    auth: injectedService ?? AccountServiceResolver.resolve(),
                    sessions: .shared
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ model: AccountModel) -> some View {
        List {
            if let session = model.sessions.session {
                signedIn(model, session: session)
            } else {
                signedOut(model)
            }

            Section {
                NavigationLink {
                    AccountPoliciesScreen()
                } label: {
                    Label("Contact & Content Rules", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("account-policies-entry")
            }
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
            Text("No account needed to browse, save cafés, or share observations. An account only links future community contributions to a name you choose.")
        }
    }

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
