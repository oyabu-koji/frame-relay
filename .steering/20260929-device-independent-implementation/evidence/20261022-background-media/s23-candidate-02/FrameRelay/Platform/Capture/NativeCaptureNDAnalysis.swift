import CoreVideo
import Foundation

/// One in-flight and one replaceable pending input, separate from capture/writer queues.
nonisolated final class NativeCaptureNDAnalysis: @unchecked Sendable {
    private struct Input {
        let buffer: CVPixelBuffer
        let instruction: NativeCaptureNDInstruction
        let sequence: UInt64
        let observedAt: TimeInterval
    }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "FrameRelay.NDAnalysis", qos: .utility)
    private let policy: CaptureNDPolicy
    private let output: @Sendable (CaptureNDResult) -> Void
    private var pending: Input?
    private var running = false
    private var stopped = false
    private var sequence: UInt64 = 0
    private var lastSubmitted = -Double.infinity
    init(policy: CaptureNDPolicy, output: @escaping @Sendable (CaptureNDResult) -> Void) {
        self.policy = policy; self.output = output
    }
    func submit(_ buffer: CVPixelBuffer, instruction: NativeCaptureNDInstruction, observedAt: TimeInterval) {
        lock.lock()
        guard !stopped, policy.isValid, observedAt.isFinite, observedAt - lastSubmitted >= policy.minimumFrameInterval else { lock.unlock(); return }
        lastSubmitted = observedAt; sequence += 1
        pending = Input(buffer: buffer, instruction: instruction, sequence: sequence, observedAt: observedAt)
        let start = !running; running = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }
    func stop() { lock.lock(); stopped = true; pending = nil; lock.unlock() }
    private func drain() {
        while true {
            lock.lock()
            guard !stopped, let input = pending else { running = false; lock.unlock(); return }
            pending = nil; lock.unlock()
            let result = autoreleasepool { NativeCaptureNDPixels.evaluate(input.buffer, instruction: input.instruction,
                policy: policy, sequence: input.sequence, observedAt: input.observedAt) }
            lock.lock(); let publish = !stopped; lock.unlock()
            if publish { output(result) }
        }
    }
}
