import Foundation
import UIKit

/// Completion acknowledges one OS event-delivery batch after the coordinator's
/// serial drain. It is not an all-task, all-reader or remote-success receipt.
@MainActor final class ProductBackgroundEventRouter {
    typealias Completion = @MainActor () -> Void
    typealias Restore = @Sendable (String, @escaping BackgroundMediaCoordinator.DidDrain) async -> Bool

    static let shared = ProductBackgroundEventRouter { identifier, observer in
        await ProductBackgroundMediaFactory.shared.restore(identifier: identifier, didDrain: observer)
    }

    private let restore: Restore
    private var handlers: [String: [Completion]] = [:]
    private var ready: [String: [BackgroundMediaDrainObservation]] = [:]
    private var seen = Set<BackgroundMediaDrainObservation>()
    private var opening = Set<String>()

    init(restore: @escaping Restore) { self.restore = restore }

    func handleEvents(identifier: String, completion: @escaping Completion) {
        handlers[identifier, default: []].append(completion)
        completeDrained(identifier)
        beginRestore(identifier)
    }

    var pendingHandlerCount: Int { handlers.values.reduce(0) { $0 + $1.count } }

    func retryPending() {
        for identifier in handlers.keys where handlers[identifier]?.isEmpty == false { beginRestore(identifier) }
    }

    private func beginRestore(_ identifier: String) {
        guard opening.insert(identifier).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await restore(identifier, { [weak self] observation in await self?.eventsDrained(observation) })
            opening.remove(identifier)
        }
    }

    private func eventsDrained(_ observation: BackgroundMediaDrainObservation) {
        guard seen.insert(observation).inserted else { return }
        let identifier = observation.session.identifier.rawValue
        ready[identifier, default: []].append(observation)
        completeDrained(identifier)
    }

    private func completeDrained(_ identifier: String) {
        while ready[identifier]?.isEmpty == false, handlers[identifier]?.isEmpty == false {
            ready[identifier]?.removeFirst()
            guard let completion = handlers[identifier]?.removeFirst() else { return }
            // Remove before invoking: reentrant/duplicate delivery cannot call
            // this handler twice. This entire operation is MainActor isolated.
            completion()
        }
    }
}

@MainActor final class FrameRelayBackgroundAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        ProductBackgroundEventRouter.shared.handleEvents(identifier: identifier) { completionHandler() }
    }
}
