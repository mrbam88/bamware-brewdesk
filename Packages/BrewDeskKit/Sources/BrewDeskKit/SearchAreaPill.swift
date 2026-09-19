import SwiftUI

/// "Search this area" pill (bd#192): floats at the top-center of the map
/// once a pan/zoom has moved the camera far enough that the loaded venue
/// list may no longer cover what's on screen (see
/// `CafeMapScreen.needsSearchAreaPill`). Tapping it re-fetches for the
/// current camera viewport.
///
/// Icon + text carry the state, never color alone (the founder is
/// red-green colorblind) — same convention as `LocateMeButton`.
struct SearchAreaPill: View {
    var isSearching: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BrewDeskPalette.foam)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                Text(isSearching ? "Searching…" : "Search this area")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(BrewDeskPalette.foam)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(BrewDeskPalette.roast, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isSearching)
        .accessibilityIdentifier("map-search-area")
        .accessibilityLabel(isSearching ? "Searching this area" : "Search this area")
        .accessibilityHint("Loads cafés for the area currently shown on the map")
    }
}
