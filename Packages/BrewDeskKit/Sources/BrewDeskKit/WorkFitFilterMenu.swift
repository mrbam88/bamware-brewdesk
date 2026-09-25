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
        .sensoryFeedback(.selection, trigger: model.selectedVenueTypes)
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

    /// brewdesk#240: adding the "Place type" row grew this panel's
    /// intrinsic height past what fit on screen without reaching down into
    /// the map's bottom shelf — on an anchored `.popover`, content that
    /// tall extends far enough that a drag starting on the shelf grabber
    /// underneath it stops registering as a shelf-resize gesture (found via
    /// `FilterUITests.testFastWifiFilterSeparatesConfirmedFromUnknownAndHidesExcluded`,
    /// which drags the shelf to `.full` with this menu still open — the
    /// established, already-tested "no need to dismiss the popover first"
    /// interaction). Capping the panel at its PRE-#240 height and scrolling
    /// internally keeps the on-screen footprint unchanged regardless of how
    /// many dimension rows it grows to hold.
    private static let maxPanelHeight: CGFloat = 440

    var body: some View {
        ScrollView {
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

                placeTypeRow

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
        }
        .frame(width: 300, alignment: .leading)
        .frame(maxHeight: Self.maxPanelHeight)
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

    /// brewdesk#240: "Place type" — Cafés/Libraries/Parks/Coworking,
    /// multi-select, all four on by default (Bilal's decision on #240: badge
    /// and filter every non-café type rather than hiding it — "this could
    /// be a great new feature"). Each chip is its own independent toggle
    /// (not a segmented single-pick like the dimension rows above), so
    /// deselecting one narrows the list to the rest without an "Any" escape
    /// hatch — reselecting every chip is how a user gets back to "no
    /// filter", exactly like `VenueFilter`'s own "all-selected == no-filter"
    /// rule.
    private static let placeTypeColumns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    private var placeTypeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Place type", systemImage: "mappin.and.ellipse")
                .font(BrewDeskFont.body(.subheadline, weight: .semibold))
            // A 2×2 grid, not a single `HStack` (the dimension rows above
            // use `.frame(maxWidth: .infinity)` because "Any"/"OK"/"Fast"
            // are short; "Coworking" isn't — dividing this 300pt-wide panel
            // four ways across one row squeezed every label onto 2-3
            // wrapped lines) and not a horizontal scroller either (a chip
            // hidden behind a swipe, inside an already-small popover, is a
            // real discoverability miss — a user who never swipes never
            // learns Coworking exists as a filterable type). Two columns at
            // this panel's width comfortably fits every label on one line.
            LazyVGrid(columns: Self.placeTypeColumns, alignment: .leading, spacing: 6) {
                ForEach(VenueTypeBadge.filterableCases, id: \.self) { type in
                    placeTypeChip(type)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filter-place-type-row")
    }

    /// One "Place type" chip. `.isSelected` (not `.isButton` alone) plus an
    /// explicit "Selected"/"Not selected" accessibility value is what makes
    /// this read as a TOGGLE to VoiceOver/XCUITest rather than a plain tap
    /// target — the acceptance criterion in brewdesk#240's test plan ("the
    /// type chips are toggle buttons").
    private func placeTypeChip(_ type: VenueTypeBadge) -> some View {
        let isSelected = model.selectedVenueTypes.contains(type)
        return Button {
            if isSelected {
                model.selectedVenueTypes.remove(type)
            } else {
                model.selectedVenueTypes.insert(type)
            }
        } label: {
            Label(type.displayName, systemImage: type.symbolName)
                .font(.caption.bold())
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(
                    isSelected ? BrewDeskPalette.roast : Color.secondary.opacity(0.10),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-place-type-\(type.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// "What the numbers mean" — the same four tiers and colors as
    /// `ScoreBadge`/`TeardropMarkerView`, spelled out once here since the score
    /// itself no longer carries an inline legend anywhere on Spots.

    /// "What the numbers mean" — bd#241 (spec: "the filter-menu legend
    /// follow[s] the same ramp" as the map pins): swatches now come from
    /// `BrewDeskPalette.markerFill(score:)` — the SAME single-hue,
    /// lightness-only pin ramp `TeardropMarkerView`/demoted dots use —
    /// rather than `ScoreTier.color`'s four DIFFERENT hues (used elsewhere,
    /// e.g. `ScoreBadge`). Each row picks a representative score inside its
    /// own range for the swatch: `markerFill`'s own tiers (`<60`, `60-69`,
    /// `70-79`, `>=80`) don't align 1:1 with these four ranges (`75+`,
    /// `60-74`, `45-59`, `0-44`), so "mixed" (45-59) and "weak" (0-44) both
    /// land in the pin ramp's shared `<60` bucket and render the SAME
    /// swatch color — an accurate reflection of the map (a 50 and a 20
    /// pin already render identically), not a bug in this legend.
    private var scoreLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the numbers mean")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            legendRow(swatchScore: 90, range: "75+", label: "great")
            legendRow(swatchScore: 65, range: "60–74", label: "good")
            legendRow(swatchScore: 50, range: "45–59", label: "mixed")
            legendRow(swatchScore: 20, range: "0–44", label: "weak")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filter-score-legend")
    }

    /// Number + word lead — the dot is a redundant, secondary accent (not
    /// the row's primary differentiator, which is the range + word text)
    /// and `.accessibilityHidden` since VoiceOver already gets everything
    /// the dot conveys from those. `swatchScore` picks which pin-ramp tier
    /// this row's dot renders as — see `scoreLegend`'s own doc comment.
    private func legendRow(swatchScore: Int, range: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Text(range)
                .font(BrewDeskFont.label(.caption2))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
            Spacer(minLength: 0)
            Circle()
                .fill(BrewDeskPalette.markerFill(score: swatchScore))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
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
        model.selectedVenueTypes = Set(VenueTypeBadge.filterableCases)
    }

    /// Active count across the five dimensions this menu owns. brewdesk#240:
    /// "Place type" counts as ONE active filter while narrowed (any chip
    /// deselected) — matching every other dimension's "one row, one count"
    /// contract — not one per deselected chip.
    static func activeFilterCount(_ model: VenuesModel) -> Int {
        [
            model.laptopFriendlyOnly,
            model.minWifi != nil,
            model.minOutlets != nil,
            model.minSeating != nil,
            model.selectedVenueTypes != Set(VenueTypeBadge.filterableCases),
        ].filter { $0 }.count
    }
}
