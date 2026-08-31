import Foundation
#if canImport(Network)
import Network
#endif

final class ConnectivityMonitor: Sendable {
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private let wasOnline = LockedState(true)

    func start(onReconnect: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [wasOnline] path in
            let online = path.status == .satisfied
            let cameBack = wasOnline.withLock { previous -> Bool in
                let changed = online && !previous
                previous = online
                return changed
            }
            if cameBack {
                onReconnect()
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.buzzkit.connectivity"))
    }
    #else
    func start(onReconnect: @escaping @Sendable () -> Void) {}
    #endif
}
