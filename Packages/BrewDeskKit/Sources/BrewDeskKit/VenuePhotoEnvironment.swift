import SwiftUI
import VenueKit

/// Optional-first photo service injection: screens read it from the SwiftUI
/// environment; nil (the default) means no photo UI renders anywhere.
private struct VenuePhotoServiceKey: EnvironmentKey {
    static let defaultValue: (any VenuePhotoServing)? = nil
}

/// UI-test seam: when set, `ImportSavedScreen` imports this file as soon as it
/// appears, bypassing the system document picker. nil (the default) = no-op.
private struct TakeoutImportAutorunURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

/// True when location permission is denied or restricted. The app already
/// serves NYC coverage in that case; screens only add a banner explaining why.
private struct LocationDeniedKey: EnvironmentKey {
    static let defaultValue = false
}

/// True when the system has never been asked for location (`.notDetermined`)
/// and the intro screen is behind us — e.g. the user chose "Use Union Square
/// instead", or reset the permission in Settings to "Ask Next Time". Screens
/// offer one in-app way to ask (brewdesk#149); `requestLocationAccess` is the
/// action that asks. nil action = no affordance renders.
private struct LocationUndeterminedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct RequestLocationAccessKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    public var venuePhotoService: (any VenuePhotoServing)? {
        get { self[VenuePhotoServiceKey.self] }
        set { self[VenuePhotoServiceKey.self] = newValue }
    }

    public var takeoutImportAutorunURL: URL? {
        get { self[TakeoutImportAutorunURLKey.self] }
        set { self[TakeoutImportAutorunURLKey.self] = newValue }
    }

    public var locationDenied: Bool {
        get { self[LocationDeniedKey.self] }
        set { self[LocationDeniedKey.self] = newValue }
    }

    public var locationUndetermined: Bool {
        get { self[LocationUndeterminedKey.self] }
        set { self[LocationUndeterminedKey.self] = newValue }
    }

    public var requestLocationAccess: (@MainActor () -> Void)? {
        get { self[RequestLocationAccessKey.self] }
        set { self[RequestLocationAccessKey.self] = newValue }
    }
}
