import Foundation
import Network

/// The SDK object stays on its private queue; only a small observation crosses
/// the lock. Initial unknown and routes involving an opaque interface fail closed.
nonisolated final class NativePhotoStartNetwork: PhotoSaveStartNetworkPort, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "FrameRelay.photo-start-path")
    private let lock = NSLock()
    private var condition: NetworkCondition = .unknown
    private let didChange: @Sendable () -> Void

    init(didChange: @escaping @Sendable () -> Void = {}) {
        self.didChange = didChange
        monitor.pathUpdateHandler = { [weak self] path in
            let observed: NetworkCondition
            if path.status == .unsatisfied { observed = .offline }
            else if path.status != .satisfied { observed = .unknown }
            else if path.usesInterfaceType(.cellular) { observed = .cellular }
            else if path.usesInterfaceType(.wifi), !path.usesInterfaceType(.other),
                    !path.usesInterfaceType(.wiredEthernet),
                    !path.availableInterfaces.contains(where: { $0.type == .other }) { observed = .wiFi }
            else { observed = .unknown }
            self?.receive(observed)
        }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel() }

    func currentCondition() -> NetworkCondition {
        lock.lock(); defer { lock.unlock() }; return condition
    }
    private func receive(_ value: NetworkCondition) {
        lock.lock()
        let changed = condition != value
        condition = value
        lock.unlock()
        if changed { didChange() }
    }
}
