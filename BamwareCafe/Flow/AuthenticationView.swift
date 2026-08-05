import SwiftUI

struct AuthenticationView: View {
    let configuration: AppConfiguration
    @Bindable var auth: AuthSessionStore
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showingPasswordReset = false

    private enum Mode {
        case signIn, register
    }

    var body: some View {
        ZStack {
            AppBrand.pageGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Spacer(minLength: 42)
                    Text(configuration.appName.uppercased())
                        .font(.caption.bold())
                        .tracking(2.4)
                        .foregroundStyle(AppBrand.clay)
                    Text(mode == .signIn ? "Welcome back to better workdays." : "Save your next favorite desk.")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(AppBrand.espresso)
                    Text(configuration.tagline)
                        .font(.body)
                        .foregroundStyle(AppBrand.muted)

                    VStack(spacing: 14) {
                        if mode == .register {
                            field("Name", text: $name, contentType: .name)
                        }
                        field("Email", text: $email, contentType: .emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .padding(16)
                            .background(AppBrand.foam, in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppBrand.clay)
                    }

                    Button(auth.isSubmitting ? "Working…" : mode == .signIn ? "Sign in" : "Create account") {
                        Task {
                            if mode == .signIn {
                                await auth.login(email: email, password: password)
                            } else {
                                await auth.register(name: name, email: email, password: password)
                            }
                        }
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(!formValid || auth.isSubmitting)
                    .opacity(formValid ? 1 : 0.45)

                    if mode == .signIn {
                        Button("Forgot password?") { showingPasswordReset = true }
                            .font(.subheadline.bold())
                            .foregroundStyle(AppBrand.roast)
                            .frame(maxWidth: .infinity)
                    }

                    Button(mode == .signIn ? "New here? Create an account" : "Already have an account? Sign in") {
                        auth.clearError()
                        mode = mode == .signIn ? .register : .signIn
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppBrand.muted)
                    .frame(maxWidth: .infinity)

                    Text("By continuing, you agree to the Terms and Privacy Policy.")
                        .font(.caption)
                        .foregroundStyle(AppBrand.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showingPasswordReset) {
            PasswordResetView(auth: auth, initialEmail: email)
        }
    }

    private var formValid: Bool {
        email.contains("@") && password.count >= 8 && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func field(_ title: String, text: Binding<String>, contentType: UITextContentType) -> some View {
        TextField(title, text: text)
            .textContentType(contentType)
            .padding(16)
            .background(AppBrand.foam, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    let auth: AuthSessionStore
    @State private var email: String
    @State private var sent = false
    @State private var isSending = false

    init(auth: AuthSessionStore, initialEmail: String) {
        self.auth = auth
        self._email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reset your password")
                    .font(.largeTitle.bold())
                Text(sent
                     ? "If an account exists for that email, reset instructions are on the way."
                     : "Enter your email and we'll send reset instructions.")
                    .foregroundStyle(.secondary)
                if !sent {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                    Button(isSending ? "Sending…" : "Send instructions") {
                        isSending = true
                        Task {
                            try? await auth.sendPasswordReset(email: email)
                            isSending = false
                            sent = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!email.contains("@") || isSending)
                }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
