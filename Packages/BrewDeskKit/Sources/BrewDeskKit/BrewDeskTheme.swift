import SwiftUI
import BamwareCore
import BamwareUI

/// BrewDesk on the bamware-ios theme contract: Warm Utilitarian
/// green/sand/sage (brewdesk#98, was espresso + cream).
/// Conforms to BamwareUI.Theme, so shared components (SmartText, …) render
/// the cafe brand without any change to bamware-ios — the whole point of
/// the white-label architecture.
///
/// `isDarkMode` is kept as an explicit stored property (some call sites
/// branch on it directly — e.g. `ObservationFormScreen`'s selected-chip
/// text), but the three colors below no longer re-derive per-mode values
/// inline: they reference `BrewDeskPalette`'s adaptive tokens, which resolve
/// against the current trait environment the same way `isDarkMode` does, so
/// there is one definition of each dark-mode value instead of two that can
/// drift apart.
public struct BrewDeskTheme: Theme {
    public let tenantID = "brewdesk"
    public let isDarkMode: Bool
    public let primaryColor: Color
    public let secondaryColor: Color
    public let backgroundColor: Color
    public let font: Font

    public init(isDarkMode: Bool = false) {
        self.isDarkMode = isDarkMode
        self.primaryColor = BrewDeskPalette.primaryText
        self.secondaryColor = BrewDeskPalette.secondaryText
        self.backgroundColor = BrewDeskPalette.page
        self.font = BrewDeskFont.headline(.body)
    }
}
