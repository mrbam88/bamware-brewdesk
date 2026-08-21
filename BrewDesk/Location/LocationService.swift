import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private(set) var location: CLLocation?
    /// Mirrors the system authorization so screens can explain a denied state.
    /// Pinned to `.denied` under `-UITestLocationDenied` (UI tests only).
    private(set) var authorizationStatus: CLAuthorizationStatus

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?
    @ObservationIgnored
    private let forcedDenied: Bool

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        let manager = CLLocationManager()
        let forcedDenied = UITestScenario.isLocationDenied()
        self.manager = manager
        self.forcedDenied = forcedDenied
        self.authorizationStatus = forcedDenied ? .denied : manager.authorizationStatus
        super.init()
        manager.delegate = self
        if !forcedDenied,
           manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            startUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func requestAccess() {
        guard !forcedDenied else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        startUpdates()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, !self.forcedDenied else { return }
            self.authorizationStatus = status
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
