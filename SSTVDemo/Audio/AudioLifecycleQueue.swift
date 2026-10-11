import Foundation

/// Preserve the UI's start/pause/stop order even while a previous activation is pending.
/// Cancelling a caller must not cancel the queued cleanup or let a later start overtake it.
@MainActor
final class AudioLifecycleQueue {
    private var tail: Task<Void, Never>?

    @discardableResult
    func enqueue<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) -> Task<Value, Error> {
        let previous = tail
        let next = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = await next.result }
        return next
    }
}
