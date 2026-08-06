import MapKit
import SwiftUI
import VenueKit

public struct CafeMapScreen: View {
    @Bindable private var model: VenuesModel
    @State private var selected: Venue?
    @State private var position: MapCameraPosition

    public init(model: VenuesModel) {
        self.model = model
        self._position = State(initialValue: .region(Self.region(lat: model.centerLat, lng: model.centerLng)))
    }

    public var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(model.venues.prefix(40)) { venue in
                Annotation("", coordinate: coordinate(of: venue)) {
                    Button {
                        selected = venue
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.caption2)
                            Text("\(venue.workScore)")
                                .font(.caption.monospacedDigit().bold())
                        }
                        .foregroundStyle(selected?.id == venue.id ? .white : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selected?.id == venue.id ? AnyShapeStyle(venue.scoreTier.color) : AnyShapeStyle(.regularMaterial),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(venue.name), Work Fit \(venue.workScore)")
                }
            }
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .top) { searchHeader }
        .safeAreaInset(edge: .bottom) { discoveryShelf }
        .overlay { loadStatus }
        .sheet(item: $selected) { venue in
            NavigationStack {
                VenueDetailScreen(venue: venue)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.centerLat) { _, latitude in
            position = .region(Self.region(lat: latitude, lng: model.centerLng))
        }
    }

    @ViewBuilder
    private var loadStatus: some View {
        switch model.phase {
        case .loading where model.venues.isEmpty:
            ProgressView("Finding work-friendly cafes…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        case .failed:
            ContentUnavailableView {
                Label("Cafe service unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Retry") { reload() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
        default:
            EmptyView()
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cafes", text: $model.searchQuery)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.load() } }
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                        Task { await model.load() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            HStack {
                Text("\(model.venues.count) work cafes")
                    .font(.caption.bold())
                Spacer()
                Text("Scores show Work Fit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var discoveryShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: "Laptop friendly",
                        symbol: "laptopcomputer",
                        selected: model.laptopFriendlyOnly
                    ) {
                        model.laptopFriendlyOnly.toggle()
                        reload()
                    }
                    filterChip(
                        title: model.minWifi == "fast" ? "Fast Wi-Fi" : "Wi-Fi",
                        symbol: "wifi",
                        selected: model.minWifi != nil
                    ) {
                        model.minWifi = model.minWifi == nil ? "ok" : model.minWifi == "ok" ? "fast" : nil
                        reload()
                    }
                    filterChip(
                        title: model.minOutlets == "plenty" ? "Plenty of outlets" : "Outlets",
                        symbol: "powerplug.fill",
                        selected: model.minOutlets != nil
                    ) {
                        model.minOutlets = model.minOutlets == nil ? "some" : model.minOutlets == "some" ? "plenty" : nil
                        reload()
                    }
                }
                .padding(.horizontal, 16)
            }

            if model.venues.isEmpty {
                ContentUnavailableView(
                    "No cafes in this view",
                    systemImage: "cup.and.saucer",
                    description: Text("Clear a filter or try another search.")
                )
                .frame(height: 130)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.venues.prefix(12)) { venue in
                            Button {
                                selected = venue
                                position = .region(
                                    MKCoordinateRegion(
                                        center: coordinate(of: venue),
                                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                                    )
                                )
                            } label: {
                                venueCard(venue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 126)
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThickMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.15), radius: 14, y: -3)
    }

    private func filterChip(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(selected ? Color.brown : Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func venueCard(_ venue: Venue) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(venue.scoreTier.color.opacity(0.14))
                VStack(spacing: 3) {
                    Text("\(venue.workScore)")
                        .font(.title2.monospacedDigit().bold())
                    Text("WORK FIT")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.5)
                }
                .foregroundStyle(venue.scoreTier.color)
            }
            .frame(width: 72, height: 82)

            VStack(alignment: .leading, spacing: 5) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(venue.neighborhood)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(venue.attributes.wifi.value, systemImage: "wifi")
                    Label(venue.attributes.outlets.value, systemImage: "powerplug")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 285, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func reload() {
        Task { await model.load() }
    }

    private static func region(lat: Double, lng: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
    }

    private func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }
}
