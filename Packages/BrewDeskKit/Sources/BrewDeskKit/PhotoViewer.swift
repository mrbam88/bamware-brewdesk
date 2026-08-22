import SwiftUI
import VenueKit

/// Fullscreen photo view. This is where the Google Places author attribution
/// lives (name + profile link) — the thumbnails deliberately omit it, which
/// the Places policy permits only while this larger view displays it fully.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: VenuePhoto
    let venueName: String
    @State private var attempt = 0
    // Report/block (brewdesk#48): community photos only — Google Places
    // photos are licensed, not UGC. Self-contained state + default services
    // so the (untouched) VenueDetailScreen call site stays a two-arg init.
    @State private var showsReportSheet = false
    @State private var showsBlockConfirm = false
    var blockStore: ContributorBlockStore = .shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AsyncImage(url: URL(string: photo.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        // Never a spinner forever: say so, offer Retry, keep Close.
                        ContentUnavailableView {
                            Label("Photo unavailable", systemImage: "photo")
                        } description: {
                            Text("Check your connection and try again.")
                        } actions: {
                            Button("Retry") { attempt += 1 }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("photo-viewer-retry")
                        }
                        .colorScheme(.dark)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("photo-viewer-error")
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .id(attempt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

                // Community photos (brewdesk#49): our own attribution UI —
                // just the contributor byline, no Google link. Takes
                // precedence over the Google block (see VenuePhoto docs).
                if let byline = photo.communityByline {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.caption)
                        Text("Photo by \(byline)")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("photo-community-byline")
                } else if photo.attribution != nil || photo.attributionUri != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.caption)
                        if let attribution = photo.attribution {
                            Text("Photo by \(attribution)")
                                .font(.caption)
                        }
                        Spacer()
                        if let uriString = photo.attributionUri, let uri = URL(string: uriString) {
                            Link("View on Google Maps", destination: uri)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("photo-attribution")
                }
            }
            .navigationTitle(Text(verbatim: venueName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Moderation menu is store-gated (brewdesk#67): the
                // submission build ships no report/block surface.
                if let byline = photo.communityByline, !StoreSurface.isGated {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                showsReportSheet = true
                            } label: {
                                Label("Report Photo", systemImage: "flag")
                            }
                            .accessibilityIdentifier("photo-report-entry")
                            Button(role: .destructive) {
                                showsBlockConfirm = true
                            } label: {
                                Label("Block \(byline)", systemImage: "hand.raised")
                            }
                            .accessibilityIdentifier("photo-block-entry")
                        } label: {
                            Label("Photo Options", systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("photo-moderation-menu")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showsReportSheet) {
                ReportContentSheet(photo: photo, venueName: venueName)
            }
            .confirmationDialog(
                "Block \(photo.communityByline ?? "contributor")?",
                isPresented: $showsBlockConfirm,
                titleVisibility: .visible
            ) {
                Button("Block", role: .destructive) {
                    if let byline = photo.communityByline {
                        blockStore.block(byline)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their photos will be hidden on this device. You can unblock from Account → Contact & Content Rules.")
            }
        }
    }
}
