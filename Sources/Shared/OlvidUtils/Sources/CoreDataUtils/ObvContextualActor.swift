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
@preconcurrency import CoreData


// MARK: - ObvContextualExecutor

/// A `SerialExecutor` that routes every Swift concurrency job through
/// `NSManagedObjectContext.perform(_:)`, ensuring that all work enqueued on this
/// executor runs on the context's private queue.
///
/// You rarely need to interact with `ObvContextualExecutor` directly. Its primary
/// use is as the backing executor for actors that conform to
/// ``ObvContextualActorIsolated``.
///
/// ## Thread safety
///
/// `ObvContextualExecutor` is marked `@unchecked Sendable` because
/// `NSManagedObjectContext` does not conform to `Sendable`. The class is safe to
/// send across isolation boundaries because all access to the context is routed
/// through `context.perform(_:)`, which serialises work on the context's own
/// queue. No other code in this class reads or writes context state directly.
///
/// ## isSameExclusiveExecutionContext
///
/// Two `ObvContextualExecutor` instances that wrap the same `NSManagedObjectContext`
/// are considered the same exclusive execution context. This makes
/// `assumeIsolated(_:)` work correctly when two different executor instances happen
/// to wrap identical contexts.
///
/// Note that this check cannot detect the case where code is already running on the
/// context's queue via a different mechanism (for example, from inside `@MainActor`
/// code when the context is a `viewContext`). This is a known limitation of the
/// current Swift executor model.
public final class ObvContextualExecutor: SerialExecutor, @unchecked Sendable {

    public let context: NSManagedObjectContext

    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    // `UnownedJob` satisfies the `Executor` protocol requirement on all supported OS
    // versions (iOS 16+). The Swift runtime bridges it to the newer `ExecutorJob`
    // protocol requirement automatically on iOS 17+, so no second overload is needed.
    //
    // When iOS 16 is dropped, delete this method and uncomment the
    // `consuming ExecutorJob` overload below.
    @available(iOS, introduced: 16.0, deprecated: 17.0, message: "Replace with enqueue(_ job: consuming ExecutorJob) when iOS 16 is dropped")
    public func enqueue(_ job: UnownedJob) {
        let executor = asUnownedSerialExecutor()
        context.perform {
            job.runSynchronously(on: executor)
        }
    }

//    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
//    public func enqueue(_ job: consuming ExecutorJob) {
//        let unownedJob = UnownedJob(job)
//        let executor = asUnownedSerialExecutor()
//        context.perform {
//            unownedJob.runSynchronously(on: executor)
//        }
//    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    public func isSameExclusiveExecutionContext(other: ObvContextualExecutor) -> Bool {
        context === other.context
    }

}


// MARK: - ObvContextualActorIsolated

/// A protocol that binds an `actor` to a specific `NSManagedObjectContext`, ensuring
/// that every method on the actor automatically runs on that context's private queue.
///
/// ## When to use this — and when not to
///
/// This protocol is **not** a replacement for
/// `ContextualOperationWithSpecificReasonForCancel` + `coordinatorsQueue`. That
/// pattern serialises all database writes through a single serial queue, guaranteeing
/// a total ordering on modifications. `ObvContextualActorIsolated` provides no such
/// global guarantee: two actor instances each have their own context and can run
/// concurrently.
///
/// Use `ObvContextualActorIsolated` for **read-only** database queries that are
/// self-contained and have no ordering dependency on concurrent writes — in other
/// words, cases where the old operation pattern would be overkill. A typical example
/// is `MostAppropriateOwnedIdentityHelper`, which queries the database to determine
/// which owned identity to display, without writing anything:
///
/// ```swift
/// actor MostAppropriateOwnedIdentityHelper: ObvContextualActorIsolated {
///
///     nonisolated let obvContextualExecutor: ObvContextualExecutor
///
///     init(context: NSManagedObjectContext) {
///         obvContextualExecutor = ObvContextualExecutor(context: context)
///     }
///
///     func mostAppropriateOwnedCryptoIdToShow() async -> ObvCryptoId? {
///         // `context` is provided by the protocol extension and is safe to use
///         // here because this method always runs on context's private queue.
///         guard let identity = try? PersistedObvOwnedIdentity
///             .getAllNonHiddenOwnedIdentities(within: context).first else { return nil }
///         return identity.cryptoId
///     }
/// }
///
/// // Call site — no operation subclass, no coordinatorsQueue, no boilerplate.
/// let cryptoId = await MostAppropriateOwnedIdentityHelper(
///     context: ObvStack.shared.newBackgroundContext()
/// ).mostAppropriateOwnedCryptoIdToShow()
/// ```
///
/// ## Conformance
///
/// 1. Declare `nonisolated let obvContextualExecutor: ObvContextualExecutor` as a
///    stored property. It must be `nonisolated` so the default `unownedExecutor`
///    implementation in the protocol extension can read it without crossing actor
///    isolation.
/// 2. Initialise `obvContextualExecutor` in `init` by passing the
///    `NSManagedObjectContext` the actor should be bound to.
/// 3. The protocol extension provides `unownedExecutor` (wiring the actor to the
///    executor) and `context` (a convenience accessor for the underlying
///    `NSManagedObjectContext`) for free. No further boilerplate is required.
///
/// ## Notes
///
/// - **`NSManagedObject` sendability**: managed objects are not `Sendable` and
///   cannot cross actor boundaries. Return `NSManagedObjectID` or value-type
///   snapshots when the result needs to be consumed outside the actor.
/// - **Suspension points**: if an actor method `await`s something outside the
///   context's queue (e.g. another actor), it suspends and the context's queue is
///   free to run other work during that suspension. This is safe for reads but means
///   the method is not a single atomic transaction across the suspension point.
/// - **Context lifetime**: pass `ObvStack.shared.newBackgroundContext()` for work
///   that does not need to run on the main thread (the common case). Pass
///   `ObvStack.shared.viewContext` only when the result feeds directly into a
///   `@MainActor` UI component — all actor methods then run on the main thread.
public protocol ObvContextualActorIsolated: Actor {

    /// The executor that binds this actor to its `NSManagedObjectContext`.
    /// Must be declared as `nonisolated let` in the conforming actor.
    nonisolated var obvContextualExecutor: ObvContextualExecutor { get }

}

extension ObvContextualActorIsolated {

    /// Wires this actor to the Core Data context's queue. Provided automatically
    /// by the protocol extension; conforming actors must not override this.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        obvContextualExecutor.asUnownedSerialExecutor()
    }

    /// The `NSManagedObjectContext` this actor is bound to.
    /// Safe to access from any method on the actor because all methods run on
    /// the context's queue.
    public var context: NSManagedObjectContext {
        obvContextualExecutor.context
    }

}
