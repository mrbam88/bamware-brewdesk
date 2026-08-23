import SwiftUI
import BamwareCore
import BamwareUI

/// BrewDesk on the bamware-ios theme contract: Warm Utilitarian
/// green/sand/sage (brewdesk#98, was espresso + cream).
/// Conforms to BamwareUI.Theme, so shared components (SmartText, …) render
/// the cafe brand without any change to bamware-ios — the whole point of
/// the white-label architecture.
///
/// The three colors below are resolved to CONCRETE values from the explicit
/// `isDarkMode` parameter rather than through `BrewDeskPalette`'s adaptive
/// (`UIColor { traits in … }`-backed) tokens. That's a deliberate reversal
/// of an earlier version of this init that referenced `.primaryText` /
/// `.secondaryText` / `.page` directly: SwiftUI's async render path (iOS 26)
/// can invoke a dynamic `UIColor` provider's closure from a background
/// render thread, and `BrewDeskTheme.primaryColor` ends up driving an
/// ANIMATED fill (the onboarding page-dot indicator's `.animation(...,
/// value: page)`). That combination crashed — `dispatch_assert_queue_fail`
/// inside `UIDynamicProviderColor _resolvedColorWithTraitCollection:`,
/// reproduced by `UIReviewCaptureTests` — because invoking the isolated
/// closure off the main thread trips a Swift 6 actor-isolation check.
/// `BrewDeskPalette.page/surface/…Text` stay adaptive for everywhere else
/// (proven safe in production pre-#98 for non-animated fills/text); a
/// concrete, non-dynamic Color has no closure to invoke off-thread, so it's
/// always safe to animate. The hex values below are the same ones
/// `BrewDeskPalette.primaryText`/`secondaryText`/`page` use for their dark
/// branch — see that file for the ramp/contrast derivation.
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
            ? Color(red: 0.561, green: 0.702, blue: 0.647)   // #8FB3A5 lifted sage
            : BrewDeskPalette.roast
        self.secondaryColor = isDarkMode
            ? Color(red: 0.847, green: 0.800, blue: 0.663)   // #D8CCA9 sand-as-text
            : BrewDeskPalette.muted
        self.backgroundColor = isDarkMode
            ? Color(red: 0.082, green: 0.125, blue: 0.110)   // #15201C
            : BrewDeskPalette.foam
        self.font = BrewDeskFont.headline(.body)
    }
}
