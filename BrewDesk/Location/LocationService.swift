import CoreLocation
import Observation
import VenueKit

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private(set) var location: CLLocation?
    /// Mirrors the system authorization so screens can explain a denied state.
    /// Pinned to `.denied` under `-UITestLocationDenied`, and to `.notDetermined`
    /// under `-UITestLocationUndetermined` until `requestAccess()` (UI tests only).
    private(set) var authorizationStatus: CLAuthorizationStatus

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?
    @ObservationIgnored
    private let forcedDenied: Bool
    @ObservationIgnored
    private var forcedUndetermined: Bool
    @ObservationIgnored
    private var fixedLocationTickTask: Task<Void, Never>?

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// iOS has never been asked. Only `requestAccess()` can change this — the
    /// system shows its permission alert exactly once, on that call
    /// (brewdesk#149: the intro screen must not be the only caller).
    var isUndetermined: Bool {
        authorizationStatus == .notDetermined
    }

    init(environment: LaunchEnvironment = .current) {
        let manager = CLLocationManager()
        let forcedDenied = environment.locationDenied
        let forcedUndetermined = environment.locationUndetermined && !forcedDenied
        self.manager = manager
        self.forcedDenied = forcedDenied
        self.forcedUndetermined = forcedUndetermined
        self.authorizationStatus = forcedDenied
            ? .denied
            : (forcedUndetermined ? .notDetermined : manager.authorizationStatus)
        super.init()
        manager.delegate = self
        // bd#198: `-brewdesk.uitest-fixed-location` — a deterministic UI-
        // test seam for "the map keeps getting real GPS ticks while the
        // user is looking at an explored viewport". A genuinely simulated
        // fix (`xcrun simctl location`) needs host-side setup before
        // `xcodebuild test` runs (see `MapLocateButtonUITests`'s header,
        // which skips outright when that isn't provisioned) — this flag
        // instead delivers an authorized fix immediately and keeps
        // re-delivering the same coordinate on a timer, so the regression
        // test this ticket adds can run deterministically in CI. Wins over
        // `forcedDenied`/`forcedUndetermined`: no UI test combines them.
        if let fixture = environment.fixedLocation {
            authorizationStatus = .authorizedWhenInUse
            location = CLLocation(latitude: fixture.lat, longitude: fixture.lng)
            startFixedLocationTicking(fixture)
            return
        }
        if !forcedDenied, !forcedUndetermined,
           manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            startUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
        fixedLocationTickTask?.cancel()
    }

    func requestAccess() {
        guard !forcedDenied else { return }
        if forcedUndetermined {
            // UI-test seam: the "user tapped Allow" outcome without SpringBoard.
            forcedUndetermined = false
            authorizationStatus = .authorizedWhenInUse
            return
        }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        startUpdates()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, !self.forcedDenied, !self.forcedUndetermined else { return }
            self.authorizationStatus = status
        }
    }

    /// bd#198: re-publishes the fixture coordinate roughly once a second —
    /// a fresh `CLLocation` (new timestamp) each tick so `Equatable` sees a
    /// change and `onChange(of: locationService.location)` actually fires,
    /// the same way real CoreLocation periodically re-delivers a
    /// stationary fix.
    private func startFixedLocationTicking(_ fixture: FixedLocationFixture) {
        fixedLocationTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.location = CLLocation(latitude: fixture.lat, longitude: fixture.lng)
            }
        }
    }

    private func startUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    try Task.checkCancellation()
                    guard let location = update.location else { continue }
                    self?.location = location
                    break
                }
            } catch is CancellationError {
                // The view or service no longer needs a location update.
            } catch {
                // Union Square remains the deterministic fallback.
            }
            self?.updatesTask = nil
        }
    }
}
