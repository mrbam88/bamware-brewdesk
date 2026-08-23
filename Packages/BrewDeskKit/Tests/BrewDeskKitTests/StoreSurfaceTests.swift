import Foundation
import Testing

@testable import BrewDeskKit

/// Store-build surface gate (brewdesk#67): the pure decision seam.
/// `StoreSurface.isGated` = Info.plist `BDStoreSurfaceGated` (fed by the
/// `STORE_SURFACE_GATED` build setting) OR the UI-test override argument.
@Suite struct StoreSurfaceTests {
    @Test func defaultIsUngated() {
        // No plist key, no argument — TestFlight/dev behavior: everything ON.
        #expect(StoreSurface.isGated(infoValue: nil, storeSurfaceGatedOverride: false) == false)
    }

    @Test func buildSettingYESGates() {
        // STORE_SURFACE_GATED=YES lands in the plist as the string "YES".
        #expect(StoreSurface.isGated(infoValue: "YES", storeSurfaceGatedOverride: false))
    }

    @Test func buildSettingNOStaysUngated() {
        // The checked-in default: STORE_SURFACE_GATED = NO in both configs.
        #expect(StoreSurface.isGated(infoValue: "NO", storeSurfaceGatedOverride: false) == false)
    }

    @Test func emptySubstitutionStaysUngated() {
        // An undefined build setting substitutes to "" — must not gate.
        #expect(StoreSurface.isGated(infoValue: "", storeSurfaceGatedOverride: false) == false)
    }

    @Test func booleanPlistValuesAreHonored() {
        #expect(StoreSurface.isGated(infoValue: true, storeSurfaceGatedOverride: false))
        #expect(StoreSurface.isGated(infoValue: false, storeSurfaceGatedOverride: false) == false)
    }

    @Test func uiTestArgumentForcesGateOn() {
        #expect(StoreSurface.isGated(
            infoValue: "NO",
            storeSurfaceGatedOverride: true
        ))
    }

    @Test func uiTestArgumentNeverForcesGateOff() {
        // The override is one-directional: a gated store build cannot be
        // un-gated at runtime.
        #expect(StoreSurface.isGated(
            infoValue: "YES",
            storeSurfaceGatedOverride: false
        ))
    }

    @Test func liveAccessorIsUngatedInTests() {
        // The test host has no BDStoreSurfaceGated key and no override
        // argument, so the real accessor reports ungated.
        #expect(StoreSurface.isGated == false)
    }
}
