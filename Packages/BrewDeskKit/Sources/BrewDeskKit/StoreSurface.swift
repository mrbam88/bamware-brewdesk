import Foundation
import VenueKit

/// Store-build surface gate (brewdesk#67).
///
/// The App Store submission binary must be an accountless app that matches
/// the "Data Not Collected" privacy label exactly, so the store build hides:
/// the Account entry (Saved toolbar), the photo report/block actions, and
/// the observation entry card. TestFlight builds keep everything ON.
///
/// Mechanism — a build *configuration* flag, not `#if DEBUG` (both rails
/// build Release):
/// - `STORE_SURFACE_GATED` is a build setting, `NO` in every checked-in
///   configuration. It flows into the merged Info.plist as the
///   `BDStoreSurfaceGated` key (`BrewDesk-Store-Info.plist` for Release,
///   `BrewDesk-Debug-Info.plist` for Debug).
/// - The store submission archive flips it with a one-line override:
///   `xcodebuild … STORE_SURFACE_GATED=YES` (see docs/RELEASING.md).
/// - UI tests force the gated surface with the `-UITestStoreSurfaceGated`
///   launch argument. The argument only ever turns the gate ON — flipping
///   it OFF at runtime is deliberately impossible.
public enum StoreSurface {
    /// Info.plist key carrying the build setting's value ("YES"/"NO").
    public static let infoDictionaryKey = "BDStoreSurfaceGated"
    /// Launch argument that forces the gate ON for UI tests.
    public static let uiTestOverrideArgument = "-UITestStoreSurfaceGated"

    /// True when the store-submission surface gate is active: gated UI
    /// (accounts, report/block, observation entry) must not render.
    public static var isGated: Bool {
        isGated(
            infoValue: Bundle.main.infoDictionary?[infoDictionaryKey],
            storeSurfaceGatedOverride: LaunchEnvironment.current.storeSurfaceGatedOverride
        )
    }

    /// Pure seam for package tests.
    public static func isGated(infoValue: Any?, storeSurfaceGatedOverride: Bool) -> Bool {
        if storeSurfaceGatedOverride { return true }
        switch infoValue {
        case let flag as Bool:
            return flag
        case let flag as String:
            return (flag as NSString).boolValue
        default:
            return false
        }
    }
}
