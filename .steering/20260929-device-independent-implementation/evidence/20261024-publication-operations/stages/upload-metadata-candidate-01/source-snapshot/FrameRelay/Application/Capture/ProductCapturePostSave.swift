import Foundation

/// Owns completed originals independently of the current capture or screen visit.
@MainActor
final class ProductCapturePostSave {
    private struct Job {
        let original: CaptureOriginalReference
        let needsBinding: Bool
    }

    private let bindOriginal: @Sendable (CaptureOriginalReference) async -> Bool
    private let didSave: @MainActor @Sendable () async -> Void
    private var accepted: Set<CaptureOriginalReference> = []
    private var queue: [Job] = []
    private var drainTask: Task<Void, Never>?

    init(bindOriginal: @escaping @Sendable (CaptureOriginalReference) async -> Bool,
         didSave: @escaping @MainActor @Sendable () async -> Void) {
        self.bindOriginal = bindOriginal
        self.didSave = didSave
    }

    func enqueue(_ original: CaptureOriginalReference, needsBinding: Bool) {
        guard accepted.insert(original).inserted else { return }
        queue.append(.init(original: original, needsBinding: needsBinding))
        guard drainTask == nil else { return }
        // Retain this owner until every queued original is handled. Navigation and
        // capture cancellation do not cancel this task or its persistent work.
        drainTask = Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            if job.needsBinding { _ = await bindOriginal(job.original) }
            // Failed binding remains unbound in the store and visible as requiring
            // reconciliation. It never becomes the next capture's issue.
            await didSave()
            accepted.remove(job.original)
        }
        drainTask = nil
    }
}
