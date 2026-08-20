import SwiftUI
import VenueKit

/// Fullscreen photo view. This is where the Google Places author attribution
/// lives (name + profile link) — the thumbnails deliberately omit it, which
/// the Places policy permits only while this larger view displays it fully.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: VenuePhoto
    let venueName: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AsyncImage(url: URL(string: photo.url)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

                if photo.attribution != nil || photo.attributionUri != nil {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                    }
                }
            }
        }
    }
}
