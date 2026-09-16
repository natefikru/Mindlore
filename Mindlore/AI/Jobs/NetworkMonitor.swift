import Foundation
import Network
import Observation

// Publishes whether the device has a usable network path, so AI queues paused by an offline
// failure resume when the connection returns, even if the app never leaves the screen.
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.natefikru.mindlore.network"))
    }

    deinit {
        monitor.cancel()
    }
}
