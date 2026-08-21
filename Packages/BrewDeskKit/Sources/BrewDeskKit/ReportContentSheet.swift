import SwiftUI
import VenueKit

/// Report a community photo (brewdesk#48, Apple 1.2 flagging mechanism).
/// Presented from the fullscreen photo viewer. Resolves its own reporting
/// service (`ReportSpool` v1 — see ReportContract.swift for the proposed
/// engine endpoint), so no composition-root wiring is needed.
struct ReportContentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let photo: VenuePhoto
    let venueName: String
    var service: any ContentReporting = ReportSpool()

    @State private var phase: Phase = .choosing
    @State private var selectedReason: ReportReason?

    private enum Phase: Equatable {
        case choosing
        case submitting
        case submitted
        case failed
    }

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .choosing, .submitting, .failed:
                    reasonSection
                case .submitted:
                    submittedSection
                }
            }
            .navigationTitle("Report Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("report-close")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report-sheet")
    }

    @ViewBuilder
    private var reasonSection: some View {
        Section {
            ForEach(ReportReason.allCases, id: \.rawValue) { reason in
                Button {
                    selectedReason = reason
                } label: {
                    HStack {
                        Text(reason.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedReason == reason {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityIdentifier("report-reason-\(reason.rawValue)")
            }
        } header: {
            Text("Why are you reporting this photo?")
        } footer: {
            Text("Reports are reviewed within 24 hours. Objectionable content is removed and the contributor is ejected. You can also email bmalik.ee@gmail.com.")
        }

        Section {
            if phase == .failed {
                Text("Couldn't save your report. Try again in a moment.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("report-error")
            }
            Button {
                Task { await submit() }
            } label: {
                if phase == .submitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Submit Report")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedReason == nil || phase == .submitting)
            .accessibilityIdentifier("report-submit")
        }
    }

    @ViewBuilder
    private var submittedSection: some View {
        Section {
            ContentUnavailableView {
                Label("Thanks for the report", systemImage: "checkmark.seal")
            } description: {
                Text("We review reports within 24 hours and remove content that breaks the rules.")
            } actions: {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("report-done")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("report-success")
        }
    }

    private func submit() async {
        guard let selectedReason, phase != .submitting else { return }
        phase = .submitting
        do {
            try await service.submitReport(
                ContentReport(
                    venueName: venueName,
                    photoURL: photo.url,
                    contributorName: photo.communityByline,
                    reason: selectedReason
                )
            )
            phase = .submitted
        } catch {
            phase = .failed
        }
    }
}
