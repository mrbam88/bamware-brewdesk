import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    init() {
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            startUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func requestAccess() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        startUpdates()
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
