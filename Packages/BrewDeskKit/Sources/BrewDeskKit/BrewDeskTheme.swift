import SwiftUI
import BamwareCore
import BamwareUI

/// BrewDesk on the bamware-ios theme contract: espresso + cream.
/// Conforms to BamwareUI.Theme, so shared components (SmartText, …) render
/// the cafe brand without any change to bamware-ios — the whole point of
/// the white-label architecture.
public struct BrewDeskTheme: Theme {
    public let tenantID = "brewdesk"
    public let isDarkMode: Bool
    public let primaryColor: Color
    public let secondaryColor: Color
    public let backgroundColor: Color
    public let font: Font

    public init(isDarkMode: Bool = false) {
        self.isDarkMode = isDarkMode
        self.primaryColor = isDarkMode
            ? Color(red: 0.87, green: 0.77, blue: 0.64)   // steamed-milk cream
            : BrewDeskPalette.roast
        self.secondaryColor = isDarkMode
            ? Color(red: 0.62, green: 0.56, blue: 0.50)
            : BrewDeskPalette.muted
        self.backgroundColor = isDarkMode
            ? Color(red: 0.11, green: 0.09, blue: 0.08)
            : BrewDeskPalette.oat
        self.font = .system(.body, design: .serif)
    }
}
