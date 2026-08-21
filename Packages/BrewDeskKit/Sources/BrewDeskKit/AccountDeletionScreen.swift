import SwiftUI
import VenueKit

/// In-app account deletion (Apple 5.1.1(v)), ported from Baat's two-step
/// double-confirm screen (dating-app #18): an explain step listing exactly
/// what is deleted, then a type-to-confirm step. The actual deletion order
/// lives in `AccountModel.deleteAccount` (content → auth record → local
/// session) and is pinned by `AccountModelTests`.
public struct AccountDeletionScreen: View {
    @Environment(\.dismiss) private var dismiss

    /// Typed, not localized — deliberate friction (same as Baat).
    static let confirmWord = "DELETE"

    private let model: AccountModel
    @State private var step: Step = .explain
    @State private var confirmText = ""
    @State private var errorMessage: String?
    @State private var isDeleting = false

    private enum Step {
        case explain
        case confirm
    }

    public init(model: AccountModel) {
        self.model = model
    }

    public var body: some View {
        List {
            switch step {
            case .explain: explainSection
            case .confirm: confirmSection
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Step 1: explain

    @ViewBuilder
    private var explainSection: some View {
        Section {
            Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                bullet("Your account and sign-in")
                bullet("Your name and email on our servers")
                bullet("Community contributions linked to your account")
                bullet("You will be signed out on this device")
            }
        } footer: {
            Text("Kept where legally required: safety records (e.g. reports filed against content). Saved cafés live only on this device and are not affected.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-delete-explain")

        Section {
            Button("Continue to Delete", role: .destructive) {
                step = .confirm
            }
            .accessibilityIdentifier("account-delete-continue")
            Button("Cancel") {
                dismiss()
            }
            .accessibilityIdentifier("account-delete-cancel")
        }
    }

    // MARK: - Step 2: type-to-confirm

    private var confirmed: Bool {
        confirmText.trimmingCharacters(in: .whitespaces) == Self.confirmWord
    }

    @ViewBuilder
    private var confirmSection: some View {
        Section {
            TextField("Type \(Self.confirmWord) to confirm", text: $confirmText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .accessibilityIdentifier("account-delete-confirm-field")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("account-delete-error")
            }

            Button {
                Task { await performDeletion() }
            } label: {
                if isDeleting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Delete My Account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!confirmed || isDeleting)
            .accessibilityIdentifier("account-delete-confirm")
        } header: {
            Text("Final confirmation")
        } footer: {
            Text("Deleting removes your account permanently.")
        }

        Section {
            Button("Cancel") {
                dismiss()
            }
            .accessibilityIdentifier("account-delete-cancel")
        }
    }

    private func performDeletion() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        let outcome = await model.deleteAccount()
        isDeleting = false
        switch outcome {
        case .completed, .authIncomplete:
            // Signed out either way; the account screen shows its signed-out
            // state. `.authIncomplete` is retryable end-to-end after a fresh
            // sign-in (both endpoints treat "already gone" as success).
            dismiss()
        case .contentFailed(let message):
            errorMessage = message
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .font(.subheadline)
    }
}
