import Foundation
import Network
import Observation

/// Reconnect signal for cold-start recovery (brewdesk#28): when the network
/// path goes from unsatisfied to satisfied, the discovery root retries a
/// failed load so the user never has to relaunch. The first path update only
/// records the baseline — it never counts as a reconnect — which keeps
/// fixture-driven UI tests deterministic on an always-online simulator.
@Observable
public final class ConnectivityMonitor {
    /// nil until the first path update arrives.
    public private(set) var isOnline: Bool?
    @ObservationIgnored private var monitor: NWPathMonitor?

    public init() {}

    public func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.bamware.brewdesk.connectivity"))
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
