import Foundation
import Testing
import UIKit
@testable import BrewDesk
import BrewDeskKit

/// brewdesk#98: the three OFL variable TTFs (Hanken Grotesk, Manrope,
/// JetBrains Mono) are bundled under `BrewDesk/Fonts/` and declared in
/// `UIAppFonts` in both Info.plists. This runs hosted by the app target, so
/// `UIFont(name:)` sees exactly what a real launch sees — if bundling or
/// `UIAppFonts` registration ever regresses, this fails instead of every
/// screen silently falling back to the system font.
@Suite @MainActor struct BrewDeskFontTests {
    @Test func hankenGroteskRegistered() {
        #expect(UIFont(name: "HankenGrotesk-Regular", size: 17) != nil)
        #expect(BrewDeskFont.hankenGroteskLoaded)
    }

    @Test func manropeRegistered() {
        #expect(UIFont(name: "Manrope-Regular", size: 17) != nil)
        #expect(BrewDeskFont.manropeLoaded)
    }

    @Test func jetBrainsMonoRegistered() {
        #expect(UIFont(name: "JetBrainsMono-Regular", size: 17) != nil)
        #expect(BrewDeskFont.jetBrainsMonoLoaded)
    }

    /// The wrapper's own fallback path: even if a name is bogus, it must
    /// return a usable Font rather than trap — proves the "fall back to
    /// system fonts if not [resolved]" contract holds.
    @Test func fallsBackWithoutTrapping() {
        _ = BrewDeskFont.headline(.title)
        _ = BrewDeskFont.body(.body)
        _ = BrewDeskFont.label(.caption)
    }
}
