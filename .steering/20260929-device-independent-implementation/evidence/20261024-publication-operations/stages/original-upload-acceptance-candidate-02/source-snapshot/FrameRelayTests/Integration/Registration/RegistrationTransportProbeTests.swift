import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct RegistrationTransportProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REGISTRATION_PROBE"] == "1"))
    func testRedirectIsRefusedAndSessionTerminates() async throws {
        let configuration = try RegistrationProbeConfiguration()
        let evidence = try RegistrationProbeEvidence(name: "redirect")
        let observation = RegistrationHTTPObservation()
        let request = probeRequest("redirect", configuration: configuration)
        var rejected = false
        do { _ = try await RegistrationURLSessionRequest.perform(request, observation: observation) }
        catch { rejected = true }
        try #require(rejected)
        try #require(observation.snapshot.redirectsRefused == 1)
        try await assertTerminal(observation, evidence: evidence)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REGISTRATION_PROBE"] == "1"))
    func testOversizeMetadataIsBoundedAndSessionTerminates() async throws {
        let configuration = try RegistrationProbeConfiguration()
        let evidence = try RegistrationProbeEvidence(name: "oversize")
        let observation = RegistrationHTTPObservation()
        var rejected = false
        do { _ = try await RegistrationURLSessionRequest.perform(probeRequest("oversize", configuration: configuration), observation: observation) }
        catch { rejected = true }
        try #require(rejected)
        try #require(observation.snapshot.responseReceived)
        try #require(observation.snapshot.maximumRetainedBytes <= RegistrationWire.maximumResponseBytes)
        try await assertTerminal(observation, evidence: evidence)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REGISTRATION_PROBE"] == "1"))
    func testCancellationAfterResponseTerminatesTaskAndSession() async throws {
        let configuration = try RegistrationProbeConfiguration()
        let evidence = try RegistrationProbeEvidence(name: "cancellation")
        let observation = RegistrationHTTPObservation()
        let task = Task { @MainActor in
            try await RegistrationURLSessionRequest.perform(probeRequest("slow", configuration: configuration), observation: observation)
        }
        let limit = ContinuousClock.now.advanced(by: .seconds(4))
        while !observation.snapshot.responseReceived && ContinuousClock.now < limit {
            try await Task.sleep(for: .milliseconds(10))
        }
        let responseStarted = observation.snapshot.responseReceived
        let stillRunning = observation.snapshot.taskCompletions == 0
        task.cancel()
        var rejected = false
        do { _ = try await task.value } catch { rejected = true }
        try #require(responseStarted && stillRunning)
        try #require(rejected)
        try evidence.record("cancelled-after-response", values: ["responseStarted": 1, "taskWasRunning": 1])
        try await assertTerminal(observation, evidence: evidence)
    }
    private func probeRequest(_ path: String, configuration: RegistrationProbeConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.connection.endpoint.origin.appendingPathComponent("__s22c_probe__/" + path))
        request.setValue("Bearer " + configuration.bearer, forHTTPHeaderField: "Authorization")
        return request
    }
    private func assertTerminal(_ observation: RegistrationHTTPObservation, evidence: RegistrationProbeEvidence) async throws {
        let snapshot = observation.snapshot
        try #require(snapshot.taskCompletions == 1 && snapshot.sessionInvalidations == 1 && snapshot.continuationResumes == 1)
        let until = ContinuousClock.now.advanced(by: .milliseconds(300))
        while ContinuousClock.now < until {
            try await Task.sleep(for: .milliseconds(20))
            try #require(observation.snapshot == snapshot)
        }
        try evidence.record("terminal-and-stable", values: [
            "taskCompletions": snapshot.taskCompletions, "sessionInvalidations": snapshot.sessionInvalidations,
            "continuationResumes": snapshot.continuationResumes, "redirectsRefused": snapshot.redirectsRefused,
            "maximumRetainedBytes": snapshot.maximumRetainedBytes, "stableObservationMilliseconds": 300])
    }
}
