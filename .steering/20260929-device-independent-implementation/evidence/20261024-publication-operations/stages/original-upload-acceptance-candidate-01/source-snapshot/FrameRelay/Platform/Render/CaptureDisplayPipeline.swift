import CoreVideo
import Foundation

/// One retained processing input plus one replaceable pending input, with a
/// separate display queue. This is not connected to production capture/writers.
/// @unchecked is confined to this owner: every mutable field is locked, retained
/// input buffers are immutable by producer contract, and draw runs on one queue.
nonisolated final class CaptureDisplayPipeline: @unchecked Sendable {
    typealias Draw = @Sendable (CVPixelBuffer, CaptureDisplayRenderer.InputOrigin, CaptureDisplayContext, UInt64, CaptureDisplayTransform) throws -> CaptureDisplayFrame
    private struct Input {
        let buffer: CVPixelBuffer
        let origin: CaptureDisplayRenderer.InputOrigin
        let context: CaptureDisplayContext
        let sequence: UInt64
        let epoch: UInt64
    }
    // Publication and stop/activation share this lock. Recursive locking permits
    // the output callback to stop its own pipeline, without a post-stop callback.
    private let lock = NSRecursiveLock()
    private let queue = DispatchQueue(label: "FrameRelay.CaptureDisplay", qos: .userInitiated)
    private let transform: CaptureDisplayTransform
    private let draw: Draw
    private let output: @Sendable (Result<CaptureDisplayFrame, CaptureDisplayError>) -> Void
    private var context: CaptureDisplayContext
    private var epoch: UInt64 = 0
    private var highestSubmitted: UInt64 = 0
    private var highestPublished: UInt64 = 0
    private var pending: Input?
    private var running = false
    private var stopped = false

    init(context: CaptureDisplayContext, transform: CaptureDisplayTransform, draw: Draw? = nil,
         output: @escaping @Sendable (Result<CaptureDisplayFrame, CaptureDisplayError>) -> Void) {
        self.context = context; self.transform = transform; self.output = output
        let renderer = CaptureDisplayRenderer()
        self.draw = draw ?? { try renderer.render($0, origin: $1, context: $2, sequence: $3, transform: $4) }
    }

    /// The caller transfers a retained immutable view, never a mutable ownership
    /// claim. Replaced pending buffers are immediately released. Sequence starts
    /// at one and is monotonic within the supplied display context.
    @discardableResult
    func submit(_ buffer: CVPixelBuffer, origin: CaptureDisplayRenderer.InputOrigin,
                context: CaptureDisplayContext, sequence: UInt64) -> CaptureDisplayError? {
        lock.lock()
        guard !stopped else { lock.unlock(); return .stopped }
        guard self.context == context else { lock.unlock(); return .staleContext }
        guard origin == .captureOriginal else { lock.unlock(); return .alreadyConverted }
        guard sequence > highestSubmitted else { lock.unlock(); return .outOfOrder }
        highestSubmitted = sequence
        pending = .init(buffer: buffer, origin: origin, context: context, sequence: sequence, epoch: epoch)
        let start = !running; running = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
        return nil
    }

    /// Even an activation with the same context invalidates a processing result.
    /// High-water sequence is retained when that context is unchanged.
    func activate(context: CaptureDisplayContext) {
        lock.lock(); defer { lock.unlock() }
        if self.context != context { highestSubmitted = 0; highestPublished = 0 }
        self.context = context; epoch &+= 1; pending = nil; stopped = false
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true; epoch &+= 1; pending = nil
    }

    private func drain() {
        while true {
            lock.lock()
            guard !stopped, let input = pending else { running = false; lock.unlock(); return }
            pending = nil; lock.unlock()
            let result: Result<CaptureDisplayFrame, CaptureDisplayError> = autoreleasepool {
                do { return .success(try draw(input.buffer, input.origin, input.context, input.sequence, transform)) }
                catch let error as CaptureDisplayError { return .failure(error) }
                catch { return .failure(.renderFailed) }
            }
            lock.lock()
            if !stopped, input.epoch == epoch, input.context == context, input.sequence > highestPublished {
                switch result {
                case .success(let frame) where frame.context != input.context || frame.sequence != input.sequence
                    || frame.transformID != transform.identifier || frame.transformVersion != transform.version || frame.transformSHA256 != transform.sha256:
                    break
                default:
                    highestPublished = input.sequence
                    output(result)
                }
            }
            lock.unlock()
        }
    }
}
