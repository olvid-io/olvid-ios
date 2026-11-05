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

import Testing
import Foundation
import os
@testable import OlvidUtils


/// Tests for `AsyncStream.atMostOneValue(every:)`.
///
/// Serialized, most of them measuring when values arrive: run side by side, they would measure each other's scheduling. The bounds on
/// time are loose on purpose, a loaded machine delaying a value by tens of milliseconds.
@Suite(.serialized)
struct AsyncStreamAtMostOneValueTests {

    private static let interval: TimeInterval = 0.2

    /// A delay a value passed on at once is expected to arrive within.
    private static let atOnce: Duration = .seconds(0.1)


    // MARK: - Helpers

    /// Iterates a stream, recording what it receives and when.
    private final class Consumer<Value: Sendable>: Sendable {

        struct Reception: Sendable {
            let value: Value?
            let at: ContinuousClock.Instant
        }

        private struct Log: Sendable {
            var receptions = [Reception]()
            var finishedAt: ContinuousClock.Instant?
        }

        private let log = OSAllocatedUnfairLock(initialState: Log())
        private let task = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        init(consuming stream: AsyncStream<Value?>) {
            let log = self.log
            let task = Task {
                for await value in stream {
                    log.withLock { $0.receptions.append(Reception(value: value, at: .now)) }
                }
                log.withLock { $0.finishedAt = .now }
            }
            self.task.withLock { $0 = task }
        }

        var receptions: [Reception] { log.withLock { $0.receptions } }
        var values: [Value?] { receptions.map(\.value) }
        var finishedAt: ContinuousClock.Instant? { log.withLock { $0.finishedAt } }

        func cancel() {
            task.withLock { $0 }?.cancel()
        }

    }


    /// Whether `condition` became true within `timeout`.
    private static func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(milliseconds: 2)
        }
        return true
    }


    // MARK: - What passes at once

    @Test func theFirstValuePassesAtOnce() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        let sentAt = ContinuousClock.now
        source.yield(1)

        #expect(await Self.waitUntil { consumer.values.count == 1 })
        #expect(consumer.values == [1])
        let reception = try #require(consumer.receptions.first)
        #expect(reception.at - sentAt < Self.atOnce)
    }


    @Test func aValueArrivingAfterTheIntervalPassesAtOnce() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        source.yield(1)
        #expect(await Self.waitUntil { consumer.values.count == 1 })
        try await Task.sleep(seconds: 1.5 * Self.interval)

        let sentAt = ContinuousClock.now
        source.yield(2)

        #expect(await Self.waitUntil { consumer.values.count == 2 })
        #expect(consumer.values == [1, 2])
        let reception = try #require(consumer.receptions.last)
        #expect(reception.at - sentAt < Self.atOnce)
    }


    @Test func aNilPassesAtOnceAndDiscardsWhatIsHeldBack() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        // Received before what follows is sent, the returned stream keeping only the newest value its consumer has not read.
        source.yield(1)
        #expect(await Self.waitUntil { consumer.values.count == 1 })

        let sentAt = ContinuousClock.now
        source.yield(2)
        source.yield(nil)

        #expect(await Self.waitUntil { consumer.values.count == 2 })
        #expect(consumer.values == [1, nil])
        let reception = try #require(consumer.receptions.last)
        #expect(reception.at - sentAt < Self.atOnce)

        // The 2 held back must never arrive.
        try await Task.sleep(seconds: 2 * Self.interval)
        #expect(consumer.values == [1, nil])
    }


    @Test func aValueAfterANilPassesAtOnce() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        // Each received before the next is sent, the returned stream keeping only the newest value its consumer has not read.
        source.yield(1)
        #expect(await Self.waitUntil { consumer.values.count == 1 })
        source.yield(nil)
        #expect(await Self.waitUntil { consumer.values.count == 2 })

        let sentAt = ContinuousClock.now
        source.yield(2)

        #expect(await Self.waitUntil { consumer.values.count == 3 })
        #expect(consumer.values == [1, nil, 2])
        let reception = try #require(consumer.receptions.last)
        #expect(reception.at - sentAt < Self.atOnce)
    }


    // MARK: - What is held back

    /// 1, 2 and 3 within a fraction of the interval: 1 at once, 2 replaced by 3, and 3 once the interval has elapsed.
    @Test func theNewestValueHeldBackIsPassedOnOnceTheIntervalHasElapsed() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        source.yield(1)
        source.yield(2)
        source.yield(3)

        #expect(await Self.waitUntil { consumer.values.count == 2 })
        #expect(consumer.values == [1, 3])
        let receptions = consumer.receptions
        try #require(receptions.count == 2)
        let gap = receptions[1].at - receptions[0].at
        #expect(gap >= .seconds(0.75 * Self.interval))
        #expect(gap < .seconds(Self.interval + 0.5))

        // Nothing else is held back, so nothing else arrives.
        try await Task.sleep(seconds: 2 * Self.interval)
        #expect(consumer.values == [1, 3])
    }


    /// A value every 5ms for six intervals: the values arrive in order, at most one per interval, and the last one sent arrives.
    @Test func aSustainedStreamPassesAtMostOneValuePerIntervalInOrderAndEndsOnTheLastValue() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        let duration = 6 * Self.interval
        let start = ContinuousClock.now
        var lastSent = 0
        while ContinuousClock.now - start < .seconds(duration) {
            lastSent += 1
            source.yield(lastSent)
            try await Task.sleep(milliseconds: 5)
        }

        #expect(await Self.waitUntil { consumer.values.last == lastSent })
        let values = consumer.values.compactMap { $0 }
        #expect(values.count == consumer.values.count)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        // The first value, one per elapsed interval, and the last one held back.
        #expect(values.count <= Int(duration / Self.interval) + 2)
        #expect(values.count >= Int(duration / Self.interval) / 2)
        let receptions = consumer.receptions
        let gaps = zip(receptions.dropFirst(), receptions).map { $0.at - $1.at }
        #expect(gaps.allSatisfy { $0 >= .seconds(0.5 * Self.interval) })
    }


    // MARK: - The end of the upstream stream

    @Test func whenTheUpstreamStreamFinishesTheValueHeldBackIsPassedOnThenTheStreamFinishes() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel() }

        source.yield(1)
        source.yield(2)
        source.finish()

        #expect(await Self.waitUntil { consumer.finishedAt != nil })
        #expect(consumer.values == [1, 2])
        let receptions = consumer.receptions
        try #require(receptions.count == 2)
        #expect(receptions[1].at - receptions[0].at >= .seconds(0.75 * Self.interval))
    }


    @Test func whenTheUpstreamStreamFinishesWithNothingHeldBackTheStreamFinishesAtOnce() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel() }

        source.yield(1)
        #expect(await Self.waitUntil { consumer.values.count == 1 })

        let finishedAt = ContinuousClock.now
        source.finish()

        #expect(await Self.waitUntil { consumer.finishedAt != nil })
        #expect(consumer.values == [1])
        let consumerFinishedAt = try #require(consumer.finishedAt)
        #expect(consumerFinishedAt - finishedAt < Self.atOnce)
    }


    @Test func anUpstreamStreamThatFinishesEmptyFinishesTheStream() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel() }

        source.finish()

        #expect(await Self.waitUntil { consumer.finishedAt != nil })
        #expect(consumer.values.isEmpty)
    }


    // MARK: - The end of the consumer

    @Test func whenTheConsumerStopsTheUpstreamStreamIsCancelled() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let upstreamWasCancelled = OSAllocatedUnfairLock(initialState: false)
        source.onTermination = { termination in
            if case .cancelled = termination {
                upstreamWasCancelled.withLock { $0 = true }
            }
        }
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))

        source.yield(1)
        #expect(await Self.waitUntil { consumer.values.count == 1 })
        consumer.cancel()

        #expect(await Self.waitUntil { upstreamWasCancelled.withLock { $0 } })
        guard case .terminated = source.yield(2) else {
            Issue.record("The upstream stream still accepts values")
            return
        }
    }


    @Test func whenTheConsumerStopsWhileAValueIsHeldBackTheUpstreamStreamIsCancelled() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let upstreamWasCancelled = OSAllocatedUnfairLock(initialState: false)
        source.onTermination = { termination in
            if case .cancelled = termination {
                upstreamWasCancelled.withLock { $0 = true }
            }
        }
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))

        source.yield(1)
        source.yield(2)
        #expect(await Self.waitUntil { consumer.values.count == 1 })
        consumer.cancel()

        #expect(await Self.waitUntil { upstreamWasCancelled.withLock { $0 } })
        // Past the time the 2 would have been passed on: nothing arrives after the consumer has stopped.
        try await Task.sleep(seconds: 2 * Self.interval)
        #expect(consumer.values == [1])
    }


    /// The returned stream keeps only the newest value its consumer has not read: here the 1 and the nil are both passed on before
    /// anybody reads, and the nil replaces the 1.
    @Test func aConsumerThatFallsBehindIsGivenTheNewestValueOnly() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let throttled = upstream.atMostOneValue(every: Self.interval)
        defer { source.finish() }

        source.yield(1)
        source.yield(nil)
        try await Task.sleep(milliseconds: 50)

        let consumer = Consumer(consuming: throttled)
        defer { consumer.cancel() }

        #expect(await Self.waitUntil { consumer.values.count == 1 })
        #expect(consumer.values == [nil])
        try await Task.sleep(seconds: 2 * Self.interval)
        #expect(consumer.values == [nil])
    }


    // MARK: - Any type

    @Test func theValuesNeedNotBeNumbers() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: String?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: Self.interval))
        defer { consumer.cancel(); source.finish() }

        source.yield("first")
        source.yield("second")
        source.yield("third")

        #expect(await Self.waitUntil { consumer.values.count == 2 })
        #expect(consumer.values == ["first", "third"])
    }


    // MARK: - Efficiency

    /// 100,000 values then a nil, with an interval longer than the test: the consumer is given the first value and the nil, and nothing else.
    @Test func aFloodOfValuesGivesTheConsumerTheFirstValueAndTheNilOnly() async throws {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        let consumer = Consumer(consuming: upstream.atMostOneValue(every: 60))
        defer { consumer.cancel(); source.finish() }

        source.yield(1)
        #expect(await Self.waitUntil { consumer.values.count == 1 })
        for value in 2...100_000 {
            source.yield(value)
        }
        source.yield(nil)

        #expect(await Self.waitUntil(timeout: 10) { consumer.values.count == 2 })
        #expect(consumer.values == [1, nil])
    }


    /// How long a consumer takes to drain `count` values and a nil already waiting in the upstream stream, through the throttle or not.
    private static func timeToDrain(_ count: Int, throughTheThrottle: Bool) async -> Duration {
        let (upstream, source) = AsyncStream.makeStream(of: Int?.self)
        for value in 1...count {
            source.yield(value)
        }
        source.yield(nil)
        let start = ContinuousClock.now
        let stream = throughTheThrottle ? upstream.atMostOneValue(every: 60) : upstream
        for await value in stream where value == nil {
            break
        }
        let elapsed = ContinuousClock.now - start
        source.finish()
        return elapsed
    }


    /// The throttle costs a lock and a reading of the clock per value. Measured against iterating the upstream stream directly, the best
    /// of three runs each, so that one slow run cannot decide it.
    @Test func aValueThroughTheThrottleCostsLittleMoreThanIteratingTheStreamDirectly() async throws {
        let count = 100_000
        var direct = Duration.seconds(60)
        var throttled = Duration.seconds(60)
        for _ in 0..<3 {
            direct = min(direct, await Self.timeToDrain(count, throughTheThrottle: false))
            throttled = min(throttled, await Self.timeToDrain(count, throughTheThrottle: true))
        }
        print("🕰️ atMostOneValue: \(count) values drained in \(throttled) through the throttle, \(direct) directly — \(throttled / count) and \(direct / count) per value")
        #expect(throttled < direct * 3)
    }

}
