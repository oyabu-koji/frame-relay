import Foundation

nonisolated enum BackgroundMediaRecoveryDisposition: Equatable, Sendable {
    case exact, terminalRecorded
    case createAttachGap, missingTask, duplicateDescription, numericIdentifierReused
    case unknownTask, kindMismatch, unconfirmedJournal
}

nonisolated struct BackgroundMediaRecoveredTask: Equatable, Sendable {
    let intent: BackgroundMediaTaskID?
    let observation: BackgroundMediaTaskObservation?
    let disposition: BackgroundMediaRecoveryDisposition
}

nonisolated struct BackgroundMediaRecoveryReport: Equatable, Sendable {
    let session: BackgroundMediaSessionIdentity
    let tasks: [BackgroundMediaRecoveredTask]
}

/// Enumeration is an observation, never authority to adopt an unattached task,
/// recreate a copy, resend, or release a reader. Even a unique description does
/// not close the durable create/attach gap.
actor BackgroundMediaRecovery {
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity

    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) {
        self.store = store; self.identity = identity
    }

    func reconcile(_ identity: BackgroundMediaSessionIdentity,
                   session: any BackgroundMediaSessionPort) async -> BackendOutcome<BackgroundMediaRecoveryReport> {
        guard case .succeeded(let observed) = await session.enumerate(),
              observed.allSatisfy({ $0.session == identity }),
              case .loaded(let snapshot) = await store.load(), snapshot.storeIdentity == self.identity else {
            return .unknown
        }
        let states = snapshot.backgroundTasks.filter { $0.intent.session == identity }
        let descriptions = Dictionary(grouping: observed.filter { $0.taskDescription != nil }, by: { $0.taskDescription! })
        let numbers = Dictionary(grouping: observed, by: \.taskIdentifier)
        var results: [BackgroundMediaRecoveredTask] = []
        var matched = Set<Int>()
        for state in states {
            let candidates = descriptions[state.intent.taskDescription] ?? []
            let observation = state.binding.flatMap { binding in
                observed.first { $0.taskIdentifier == binding.taskIdentifier }
            } ?? candidates.first
            let disposition: BackgroundMediaRecoveryDisposition
            var confirmed = !state.events.isEmpty
            for event in state.events {
                guard case .committed(let receipt) = await store.lookupCommit(event.mutation),
                      receipt == event.commit else { confirmed = false; break }
            }
            if !confirmed { disposition = .unconfirmedJournal }
            else if candidates.count > 1 { disposition = .duplicateDescription }
            else if let binding = state.binding {
                let sameNumber = numbers[binding.taskIdentifier] ?? []
                if sameNumber.count > 1 || (sameNumber.first != nil
                    && sameNumber.first?.taskDescription != binding.taskDescription) {
                    disposition = .numericIdentifierReused
                } else if let task = sameNumber.first {
                    matched.insert(task.taskIdentifier)
                    let expectedKind: BackgroundMediaTaskKind
                    switch state.intent.source {
                    case .upload, .uploadChunk: expectedKind = .upload
                    case .download: expectedKind = .download
                    }
                    disposition = task.kind == expectedKind ? .exact : .kindMismatch
                } else if state.terminal != nil { disposition = .terminalRecorded }
                else { disposition = .missingTask }
            } else { disposition = .createAttachGap }
            results.append(.init(intent: state.intent.id, observation: observation, disposition: disposition))
        }
        for observation in observed where !matched.contains(observation.taskIdentifier) {
            results.append(.init(intent: nil, observation: observation, disposition: .unknownTask))
        }
        return .succeeded(.init(session: identity, tasks: results))
    }
}
