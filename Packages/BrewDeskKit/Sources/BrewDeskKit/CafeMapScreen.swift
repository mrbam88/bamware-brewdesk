import MapKit
import SwiftUI
import VenueKit

public struct CafeMapScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable private var model: VenuesModel
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var selected: Venue?
    @State private var position: MapCameraPosition

    public init(model: VenuesModel, savedVenues: SavedVenuesStore) {
        self.model = model
        self.savedVenues = savedVenues
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
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 4)
                        .background(
                            selected?.id == venue.id ? AnyShapeStyle(venue.scoreTier.color) : AnyShapeStyle(.regularMaterial),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood)")
                    .accessibilityValue(selected?.id == venue.id ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected?.id == venue.id ? .isSelected : [])
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
                VenueDetailScreen(venue: venue, savedVenues: savedVenues)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.centerLat) {
            position = .region(Self.region(lat: model.centerLat, lng: model.centerLng))
        }
        .onChange(of: model.centerLng) {
            position = .region(Self.region(lat: model.centerLat, lng: model.centerLng))
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
                Button("Retry") { model.retry() }
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
                    .onSubmit { model.submitSearch() }
                if !model.searchQuery.isEmpty {
                    Button {
                        model.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .brewDeskGlass(in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            HStack {
                Text(localizedWorkCafeCount(model.venues.count))
                    .font(.caption.bold())
                Spacer()
                Text("Scores show Work Fit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            DatasetStatStrip(model: model)

            if model.isOutsideCoverage {
                Label("You're outside NYC — showing our NYC coverage.", systemImage: "mappin.slash")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .brewDeskGlass(in: Capsule())
                    .accessibilityIdentifier("coverage-banner")
            }
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
                    }
                    filterChip(
                        title: model.minWifi == .fast ? "Fast Wi-Fi" : "Wi-Fi",
                        symbol: "wifi",
                        selected: model.minWifi != nil
                    ) {
                        model.cycleWifiMinimum()
                    }
                    filterChip(
                        title: model.minOutlets == .plenty ? "Plenty of outlets" : "Outlets",
                        symbol: "powerplug.fill",
                        selected: model.minOutlets != nil
                    ) {
                        model.cycleOutletMinimum()
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
                            .accessibilityLabel(
                                "\(venue.name), Work Fit \(venue.workScore), \(venue.neighborhood)"
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 126)
            }
        }
        .padding(.vertical, 10)
        .brewDeskGlass(in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.15), radius: 14, y: -3)
    }

    private func filterChip(
        title: LocalizedStringKey,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(selected ? BrewDeskPalette.roast : Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "On" : "Off")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(venue.neighborhood)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(localizedAttributeValue(venue.attributes.wifi.value), systemImage: "wifi")
                    Label(localizedAttributeValue(venue.attributes.outlets.value), systemImage: "powerplug")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                ProvenanceStamp(attributes: venue.attributes)
            }
        }
        .padding(10)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 330 : 285, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .animation(reduceMotion ? nil : .snappy, value: selected?.id)
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
