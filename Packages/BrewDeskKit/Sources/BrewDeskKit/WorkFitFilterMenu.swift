import SwiftUI
import VenueKit

/// UI3 (brewdesk#118): filters leave the canvas for one anchored menu.
/// `WorkFitFilterButton` is the badge that opens it; `WorkFitFilterMenu` is
/// the panel content. Both are reused by every surface that used to carry
/// its own filter UI — the map header's badge (replacing the shelf's chip
/// rail) and the list screen's toolbar (replacing its nine-item `Menu`).
///
/// Presented as a `.popover` with `.presentationCompactAdaptation(.popover)`
/// so it stays a small anchored panel on iPhone instead of ballooning into a
/// full-screen sheet — "anchored from the badge, never covering the list"
/// falls out of that one modifier rather than custom overlay math.
struct WorkFitFilterButton: View {
    @Bindable var model: VenuesModel
    @State private var showMenu = false

    init(model: VenuesModel) {
        self.model = model
    }

    var body: some View {
        Button {
            showMenu = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: WorkFitFilterMenu.activeFilterCount(model) > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                if WorkFitFilterMenu.activeFilterCount(model) > 0 {
                    Text("\(WorkFitFilterMenu.activeFilterCount(model))")
                        .font(BrewDeskFont.label(.caption2))
                        .foregroundStyle(.white)
                        .padding(4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(BrewDeskPalette.roast, in: Circle())
                        .offset(x: 4, y: -2)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel("Filters")
        .accessibilityValue(
            WorkFitFilterMenu.activeFilterCount(model) > 0
                ? "\(WorkFitFilterMenu.activeFilterCount(model)) active"
                : "None active"
        )
        .accessibilityIdentifier("filter-button")
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            WorkFitFilterMenu(model: model)
                .presentationCompactAdaptation(.popover)
        }
        // One light tick per dimension change while the menu is open —
        // matches the shelf's old chip-rail feedback (brewdesk#75).
        .sensoryFeedback(.selection, trigger: model.laptopFriendlyOnly)
        .sensoryFeedback(.selection, trigger: model.minWifi)
        .sensoryFeedback(.selection, trigger: model.minOutlets)
        .sensoryFeedback(.selection, trigger: model.minSeating)
    }
}

/// One choice in a dimension row (Wi-Fi's "OK", Outlets' "Plenty", …).
/// `identifier` doubles as `Identifiable`'s id and the accessibility
/// identifier the segmented button renders with.
private struct FilterOption<Value>: Identifiable {
    let label: LocalizedStringKey
    let value: Value
    let identifier: String
    var id: String { identifier }
}

/// The anchored panel: Laptop friendly toggle, Wi-Fi / Outlets / Seating
/// three-way pickers, the score-tier legend, then Reset. Filters apply live
/// against `model` as each control changes — no separate "Apply" step.
struct WorkFitFilterMenu: View {
    @Bindable var model: VenuesModel

    init(model: VenuesModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $model.laptopFriendlyOnly) {
                Label("Laptop friendly", systemImage: "laptopcomputer")
                    .font(BrewDeskFont.body(.subheadline, weight: .semibold))
            }
            .tint(BrewDeskPalette.roast)
            .accessibilityIdentifier("filter-laptop-friendly")

            dimensionRow(
                title: "Wi-Fi",
                symbol: "wifi",
                options: [
                    FilterOption(label: "Any", value: WifiMinimum?.none, identifier: "filter-wifi-any"),
                    FilterOption(label: "OK", value: WifiMinimum?.some(.ok), identifier: "filter-wifi-ok"),
                    FilterOption(label: "Fast", value: WifiMinimum?.some(.fast), identifier: "filter-wifi-fast"),
                ],
                selection: $model.minWifi
            )

            dimensionRow(
                title: "Outlets",
                symbol: "powerplug.fill",
                options: [
                    FilterOption(label: "Any", value: OutletMinimum?.none, identifier: "filter-outlets-any"),
                    FilterOption(label: "Some", value: OutletMinimum?.some(.some), identifier: "filter-outlets-some"),
                    FilterOption(label: "Plenty", value: OutletMinimum?.some(.plenty), identifier: "filter-outlets-plenty"),
                ],
                selection: $model.minOutlets
            )

            dimensionRow(
                title: "Seating",
                symbol: "chair.lounge",
                options: [
                    FilterOption(label: "Any", value: SeatingMinimum?.none, identifier: "filter-seating-any"),
                    FilterOption(label: "Some", value: SeatingMinimum?.some(.some), identifier: "filter-seating-some"),
                    FilterOption(label: "Plenty", value: SeatingMinimum?.some(.plenty), identifier: "filter-seating-plenty"),
                ],
                selection: $model.minSeating
            )

            Divider()

            scoreLegend

            Divider()

            Button {
                resetFilters()
            } label: {
                Label(resetLabel, systemImage: "arrow.counterclockwise")
                    .font(BrewDeskFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(Self.activeFilterCount(model) > 0 ? BrewDeskPalette.clayText : .secondary)
            }
            .disabled(Self.activeFilterCount(model) == 0)
            .accessibilityIdentifier("filters-reset")
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("work-fit-filter-menu")
    }

    /// One labeled row: an eyebrow + symbol, then a three-way segmented pick
    /// among the row's options. Generic over the filter's optional raw type
    /// so Wi-Fi/Outlets/Seating share one row builder.
    private func dimensionRow<Value: Equatable>(
        title: LocalizedStringKey,
        symbol: String,
        options: [FilterOption<Value>],
        selection: Binding<Value>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(BrewDeskFont.body(.subheadline, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(options) { option in
                    let isSelected = selection.wrappedValue == option.value
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        Text(option.label)
                            .font(.caption.bold())
                            .foregroundStyle(isSelected ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                isSelected ? BrewDeskPalette.roast : Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(option.identifier)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    /// "What the numbers mean" — the same four tiers and colors as
    /// `ScoreBadge`/`VenueScorePin`, spelled out once here since the score
    /// itself no longer carries an inline legend anywhere on Spots.
    private var scoreLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the numbers mean")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            legendRow(tier: .great, range: "75+", label: "great")
            legendRow(tier: .good, range: "60–74", label: "good")
            legendRow(tier: .mixed, range: "45–59", label: "mixed")
            legendRow(tier: .weak, range: "0–44", label: "weak")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filter-score-legend")
    }

    private func legendRow(tier: ScoreTier, range: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tier.color)
                .frame(width: 10, height: 10)
            Text(range)
                .font(BrewDeskFont.label(.caption2))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
        }
    }

    /// "Reset N filters" — N is the same dynamic active count the badge
    /// shows, never hardcoded.
    private var resetLabel: String {
        String(
            format: String(localized: "Reset %lld filters"),
            locale: .current,
            Self.activeFilterCount(model)
        )
    }

    private func resetFilters() {
        model.laptopFriendlyOnly = false
        model.minWifi = nil
        model.minOutlets = nil
        model.minSeating = nil
    }

    /// Active count across the four dimensions this menu owns. Venue-type
    /// filtering (`model.venueType`) is a separate, rarely-shown dimension
    /// (only surfaces once a dataset has more than one type) and stays out
    /// of this count/menu, matching the mockups.
    static func activeFilterCount(_ model: VenuesModel) -> Int {
        [
            model.laptopFriendlyOnly,
            model.minWifi != nil,
            model.minOutlets != nil,
            model.minSeating != nil,
        ].filter { $0 }.count
    }
}
