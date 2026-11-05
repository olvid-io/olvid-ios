/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import os


extension AsyncStream {

    /// The same values, with at most one non-nil value per `interval`.
    ///
    /// - A nil passes at once, and discards any value held back.
    /// - A non-nil value passes at once when nothing has been passed on yet, when the last value passed on is nil, or when `interval` has
    ///   elapsed since the last non-nil value was passed on.
    /// - Otherwise it is held back, replacing any value already held back, and passed on once `interval` has elapsed since the last non-nil
    ///   value was passed on.
    /// - When this stream finishes, a value held back is still passed on when its time comes, and the returned stream finishes after it.
    /// - When the consumer of the returned stream stops iterating it, this stream is cancelled. A returned stream that is never iterated
    ///   keeps this one iterated until it finishes.
    ///
    /// Values are passed on in the order they arrived. The returned stream keeps only the newest value when its consumer falls behind.
    /// Time is measured on `ContinuousClock`, so a change of the system clock has no effect.
    ///
    /// This stream must not be iterated anywhere else.
    public func atMostOneValue<Wrapped: Sendable>(every interval: TimeInterval) -> AsyncStream<Wrapped?> where Element == Wrapped? {
        let (stream, continuation) = AsyncStream<Wrapped?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let throttle = AtMostOneValueThrottle<Wrapped>(interval: .seconds(interval), continuation: continuation)
        // Set before the consumer starts, so that no termination can go unseen.
        continuation.onTermination = { _ in
            throttle.stop()
        }
        let upstream = self
        let consumer = Task {
            for await value in upstream {
                throttle.receive(value)
            }
            throttle.upstreamHasFinished()
        }
        throttle.setConsumer(consumer)
        return stream
    }

}


/// The state of ``_Concurrency/AsyncStream/atMostOneValue(every:)``.
///
/// `continuation.yield` is called under the lock, which is what keeps the values in order between the consumer and the timer.
/// `continuation.finish` is not: it calls `onTermination`, which takes the lock.
private final class AtMostOneValueThrottle<Wrapped: Sendable>: Sendable {

    private struct State: Sendable {

        /// When the last non-nil value was passed on. Nil when nothing has been passed on, or when the last value passed on is nil.
        var lastNonNilValuePassedOnAt: ContinuousClock.Instant?

        /// The newest value held back. Never nil while `timer` is set, and nil otherwise.
        var heldBack: Wrapped?

        /// Passes on `heldBack` when its time comes.
        var timer: Task<Void, Never>?

        /// Tells the current timer from one that was discarded after it woke up.
        var timerGeneration = 0

        /// Iterates the upstream stream. Cancelled by ``AtMostOneValueThrottle/stop()``, which cancels the upstream stream.
        var consumer: Task<Void, Never>?

        var upstreamHasFinished = false

        var isStopped = false

        mutating func discardWhatIsHeldBack() {
            timer?.cancel()
            timer = nil
            heldBack = nil
        }

    }

    private let interval: Duration
    private let continuation: AsyncStream<Wrapped?>.Continuation
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(interval: Duration, continuation: AsyncStream<Wrapped?>.Continuation) {
        self.interval = interval
        self.continuation = continuation
    }


    /// Given the consumer once it exists. If the returned stream has already terminated, the consumer is cancelled at once.
    func setConsumer(_ consumer: Task<Void, Never>) {
        let isStopped = state.withLock { state in
            if !state.isStopped {
                state.consumer = consumer
            }
            return state.isStopped
        }
        if isStopped {
            consumer.cancel()
        }
    }


    /// Called by the consumer for each value of the upstream stream.
    func receive(_ value: Wrapped?) {
        state.withLock { state in
            guard !state.isStopped else { return }
            // A nil passes at once. What is held back is older than it, so it is discarded.
            guard let value else {
                state.discardWhatIsHeldBack()
                state.lastNonNilValuePassedOnAt = nil
                continuation.yield(nil)
                return
            }
            let now = ContinuousClock.now
            if let lastNonNilValuePassedOnAt = state.lastNonNilValuePassedOnAt, now < lastNonNilValuePassedOnAt + interval {
                // Too soon: held back, replacing any older value. One timer per interval, set by the first value held back.
                state.heldBack = value
                if state.timer == nil {
                    state.timerGeneration += 1
                    state.timer = makeTimer(deadline: lastNonNilValuePassedOnAt + interval, generation: state.timerGeneration)
                }
            } else {
                // First value, first after a nil, or the interval has elapsed. A value still held back here is older than this one: its
                // timer is due but has not taken the lock yet.
                state.discardWhatIsHeldBack()
                state.lastNonNilValuePassedOnAt = now
                continuation.yield(value)
            }
        }
    }


    /// Called by the consumer when the upstream stream has finished, including when it was cancelled.
    func upstreamHasFinished() {
        let finishes = state.withLock { state in
            guard !state.isStopped else { return false }
            guard state.timer == nil else {
                // The timer finishes the stream once it has passed on what is held back.
                state.upstreamHasFinished = true
                return false
            }
            state.isStopped = true
            return true
        }
        if finishes {
            continuation.finish()
        }
    }


    /// Called when the returned stream terminates, whether its consumer stopped iterating it or it finished. Cancelling the consumer
    /// ends its iteration, which cancels the upstream stream.
    func stop() {
        let consumer = state.withLock { state in
            state.isStopped = true
            state.discardWhatIsHeldBack()
            let consumer = state.consumer
            state.consumer = nil
            return consumer
        }
        consumer?.cancel()
    }


    private func makeTimer(deadline: ContinuousClock.Instant, generation: Int) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                // Cancelled by whatever discarded the value held back.
                return
            }
            timerHasFired(generation: generation)
        }
    }


    private func timerHasFired(generation: Int) {
        let finishes = state.withLock { state in
            // A timer discarded while it was waiting for the lock finds no timer, or a newer generation.
            guard !state.isStopped, state.timer != nil, state.timerGeneration == generation else { return false }
            state.timer = nil
            if let heldBack = state.heldBack {
                state.heldBack = nil
                // The next interval starts now, when the value is actually passed on, not at the deadline.
                state.lastNonNilValuePassedOnAt = .now
                continuation.yield(heldBack)
            }
            guard state.upstreamHasFinished else { return false }
            state.isStopped = true
            return true
        }
        if finishes {
            continuation.finish()
        }
    }

}
