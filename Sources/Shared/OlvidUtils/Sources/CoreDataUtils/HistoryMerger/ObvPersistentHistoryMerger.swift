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
import CoreData
import OSLog


/// Observes `NSPersistentStoreRemoteChange` on a given persistent store coordinator and drives
/// ``ObvTransactionsMerger`` so writes from other processes (Intents/Notification/Share extensions)
/// land in the target `NSManagedObjectContext`.
///
/// Uses `NSPersistentStoreRemoteChange` (Apple's *Consuming relevant store changes* pattern) rather
/// than a custom Darwin notification. Notifications are filtered to the coordinator passed at init
/// so that unrelated stores don't trigger spurious merges.
public final class ObvPersistentHistoryMerger: @unchecked Sendable {

    private var notificationToken: NSObjectProtocol?
    private let historyMerger: ObvTransactionsMerger

    /// - Parameter tokenStore: shared store recording how far each consumer has read history, so the
    ///   App's launch-time prune (``pruneHistory(persistentStoreCoordinator:transactionAuthor:tokenStore:activeConsumerHorizon:logSubsystem:)``)
    ///   won't delete history any live consumer (this process included) still needs.
    public init(backgroundContext: NSManagedObjectContext,
                logSubsystem: String,
                localTransactionAuthor: String,
                contextCreator: any ObvContextCreator,
                persistentStoreCoordinator: NSPersistentStoreCoordinator,
                tokenStore: ObvPersistentHistoryConsumerTokenStore) {

        let logger = Logger(subsystem: logSubsystem, category: "ObvPersistentHistoryMerger")

        let historyMerger = ObvTransactionsMerger(
            targetContext: backgroundContext,
            localTransactionAuthor: localTransactionAuthor,
            logSubsystem: logSubsystem,
            contextCreator: contextCreator,
            lastSeenToken: persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil),
            tokenStore: tokenStore)
        self.historyMerger = historyMerger

        // Register this consumer's cursor immediately so the prune sees it before the first remote
        // change — closing the window where a launch-time prune could delete history this
        // newly-built consumer still needs.
        Task {
            await historyMerger.recordInitialHeartbeat()
        }

        logger.info("🔀 Subscribing to NSPersistentStoreRemoteChange for coordinator \(ObjectIdentifier(persistentStoreCoordinator).debugDescription, privacy: .public)")
        // Subscribe with `object: nil` to receive notifications from any coordinator, then
        // filter inside the closure. Specifying the coordinator as `object` would miss the
        // notification if Core Data posts it with a different sender (e.g. the store).
        self.notificationToken = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.object as AnyObject?) === persistentStoreCoordinator else {
                return
            }
            Task {
                await historyMerger.mergeNewTransactions()
            }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }


    /// Consumes any persistent-history transactions written since the last merge, then returns. Use
    /// this in a short-lived consumer (e.g. the Intents extension) right before reading the database,
    /// to close the race where the `NSPersistentStoreRemoteChange` notification for the App's latest
    /// write hasn't been delivered yet: relying on the notification alone, a fetch in
    /// `handle(intent:)` could run against a stale row cache and re-surface already-read messages.
    public func mergePendingTransactionsAndWait() async {
        await historyMerger.mergeNewTransactions()
    }


    /// Deletes persistent-history transactions older than the furthest-behind *live* consumer, so no
    /// process loses history it still needs.
    ///
    /// ## Multi-consumer watermark
    ///
    /// The App database's history is read by more than one process: the main app and the Intents
    /// extension each run their own ``ObvPersistentHistoryMerger``. Pruning "everything before the
    /// current token" would delete transactions a dormant-but-live extension hasn't merged yet,
    /// leaving it with stale data (already-read messages re-surfacing as new). Instead we prune only
    /// before `min(consumedDate)` across consumers whose heartbeat is within `activeConsumerHorizon`
    /// (see ``ObvPersistentHistoryConsumerTokenStore``). A consumer dormant past the horizon is
    /// ignored, bounding history growth; if it later wakes with a now-pruned cursor,
    /// ``ObvTransactionsMerger`` resets it to the current token.
    ///
    /// The pruning process first records its *own* cursor as `now` (it is about to restart its
    /// consumer from the current token), so the uniform minimum is never held back by its own stale
    /// cursor — there is no special-cased author. When no consumer is live, falls back to the current
    /// token.
    ///
    /// ## Invariant — must run BEFORE this process constructs its own ``ObvPersistentHistoryMerger``
    ///
    /// A merger snapshots `currentPersistentHistoryToken(fromStores: nil)` at init and next fetches
    /// `fetchHistory(after:)` from it. Running the prune at app launch, before `ObvDataSources` (and
    /// any CarPlay equivalent) constructs its merger, guarantees this process has no in-flight
    /// consumer whose token could fall inside the just-pruned range. (Other *processes* are protected
    /// by the watermark above.) FRC initial loads read current state from SQLite directly, not from
    /// history, so they are unaffected. **Do not** move this call into a merger's `init` or any flow
    /// that can run after `ObvDataSources` is built.
    ///
    /// Operates on a private-queue context bound to `persistentStoreCoordinator` and runs
    /// synchronously via `performAndWait` so the prune completes before the caller returns.
    /// Failures are logged but not thrown — a pruning hiccup must not break launch.
    public static func pruneHistory(persistentStoreCoordinator: NSPersistentStoreCoordinator,
                                    transactionAuthor: String,
                                    tokenStore: ObvPersistentHistoryConsumerTokenStore,
                                    activeConsumerHorizon: TimeInterval = ObvPersistentHistoryConsumerTokenStore.defaultActiveConsumerHorizon,
                                    logSubsystem: String) async {

        let logger = Logger(subsystem: logSubsystem, category: "ObvPersistentHistoryMerger")

        // Truthfully refresh our own cursor first: we are about to restart our consumer from the
        // current token, so our previous-session cursor must not hold back the watermark.
        let now = Date.now
        await tokenStore.recordConsumed(author: transactionAuthor, consumedDate: now, activeDate: now)
        let watermark = await tokenStore.pruneWatermarkDate(activeWithin: activeConsumerHorizon, now: now)

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        context.transactionAuthor = transactionAuthor

        // Read the token inside the block: NSPersistentHistoryToken is not Sendable, so capturing it
        // across the @Sendable performAndWait boundary warns under Swift 6.
        context.performAndWait {
            let deleteRequest: NSPersistentHistoryChangeRequest
            if let watermark {
                logger.info("🔀 Pruning history before live-consumer watermark \(watermark, privacy: .public)")
                deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: watermark)
            } else if let token = persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil) {
                logger.info("🔀 No live consumer — pruning history before current token")
                deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: token)
            } else {
                logger.info("🔀 No history token yet — nothing to prune")
                return
            }
            do {
                _ = try context.execute(deleteRequest)
                try context.save()
                logger.info("🔀 Pruned history")
            } catch {
                logger.fault("🔀 Failed to prune history: \(error.localizedDescription, privacy: .public)")
            }
        }

    }

}
