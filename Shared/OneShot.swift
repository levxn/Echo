import Foundation

/// Lets exactly one of several racing callbacks (a result, an error, a timeout) go first.
nonisolated final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    /// True for the first caller, false for everyone after.
    func first() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

nonisolated struct TimedOut: Error, Equatable {}

nonisolated enum Timeout {
    /// Runs `operation`, but gives up after `seconds` and throws `TimedOut`. The operation itself may keep running in the
    /// background (some system calls can't be cancelled); its late result is ignored.
    static func run<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = OneShot()
            Task {
                do {
                    let value = try await operation()
                    if gate.first() { continuation.resume(returning: value) }
                } catch {
                    if gate.first() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.first() { continuation.resume(throwing: TimedOut()) }
            }
        }
    }
}
