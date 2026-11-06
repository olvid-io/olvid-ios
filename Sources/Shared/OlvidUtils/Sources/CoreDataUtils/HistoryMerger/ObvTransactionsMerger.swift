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
import OSLog


/// Merges Core Data writes performed by other processes (Intents/Notification/Share extensions)
/// into a target `NSManagedObjectContext` using persistent history tracking.
///
/// Designed to run in response to `NSPersistentStoreRemoteChange` (Apple's documented pattern in
/// *Consuming relevant store changes*).
///
/// Per call:
/// 1. Fetch persistent history transactions written since the last seen token, on a fresh
///    background context to avoid blocking the caller.
/// 2. Drop transactions authored by `localTransactionAuthor` — our own in-process saves are
///    already merged via `automaticallyMergesChangesFromParent`.
/// 3. For each changed object ID, fetch it on a second fresh background context. This forces Core
///    Data to read from SQLite into the in-process row cache, replacing the stale snapshot that the
///    store coordinator hands operation contexts at creation time. (`mergeChanges(fromContextDidSave:)`
///    + `setQueryGenerationFrom(.current)` were insufficient here — they do not trigger a real SQL
///    fetch, so the row cache stays stale and target keeps reading pre-write values.)
/// 4. On `target`: fetch each object again (now reading from the warm cache) and call
///    `refresh(_:mergeChanges:)` to stamp the fresh values into target's registered objects.
final actor ObvTransactionsMerger {

    private let logger: Logger
    private let targetContext: NSManagedObjectContext
    private let localTransactionAuthor: String
    private var lastSeenToken: NSPersistentHistoryToken?
    private let contextCreator: any ObvContextCreator

    /// Persists how far this consumer has merged so the App's launch-time prune knows not to delete
    /// history this process still needs.
    private let tokenStore: ObvPersistentHistoryConsumerTokenStore

    /// Timestamp of the latest transaction this consumer has merged. Mirrors ``lastSeenToken`` as a
    /// `Date` because the prune watermark is computed over comparable dates, not opaque tokens.
    /// Seeded to construction time: a freshly-built merger has effectively consumed everything up to
    /// now (it starts from the current token), so nothing older than this needs preserving for it.
    private var lastConsumedDate: Date

    /// Captures the coordinator's current history token at init so the first ``mergeNewTransactions()``
    /// call only sees transactions committed after this point. Initial-load consistency is handled
    /// by the FRC's first fetch, which reads from SQLite and populates the row cache.
    init(targetContext: NSManagedObjectContext,
         localTransactionAuthor: String,
         logSubsystem: String,
         contextCreator: any ObvContextCreator,
         lastSeenToken: NSPersistentHistoryToken?,
         tokenStore: ObvPersistentHistoryConsumerTokenStore) {
        self.logger = Logger(subsystem: logSubsystem, category: "ObvTransactionsMerger")
        self.targetContext = targetContext
        self.localTransactionAuthor = localTransactionAuthor
        self.contextCreator = contextCreator
        self.lastSeenToken = lastSeenToken
        self.tokenStore = tokenStore
        self.lastConsumedDate = Date.now
    }


    /// Registers this consumer's cursor in the shared token store without doing any merging. Called
    /// once at construction so the prune sees this consumer immediately, even before its first remote
    /// change — closing the window where a launch-time prune could delete history this newly-built
    /// consumer still needs.
    func recordInitialHeartbeat() async {
        await persistCursor()
    }


    /// Writes the current cursor (`lastConsumedDate`) and a fresh heartbeat to the shared store.
    private func persistCursor() async {
        await tokenStore.recordConsumed(author: localTransactionAuthor, consumedDate: lastConsumedDate, activeDate: Date.now)
    }


    /// Advances the in-memory cursor (``lastSeenToken`` / ``lastConsumedDate``) to the latest
    /// transaction seen in `result`, then persists it. Shared by the "no foreign transactions" and
    /// "merge complete" paths, which advance identically.
    private func advanceCursor(from result: ForeignTransactionsFetchResult, initialToken: NSPersistentHistoryToken?) async {
        self.lastSeenToken = result.advancedToken ?? initialToken
        if let advancedDate = result.advancedDate {
            self.lastConsumedDate = advancedDate
        }
        await self.persistCursor()
    }
    
    private var currentMergeTask: Task<Void, Never>?

    /// Fetches transactions since ``lastSeenToken`` and applies foreign ones to ``targetContext``.
    /// The token advances to the latest transaction seen even when no foreign transaction needed
    /// merging, so we don't re-fetch the same window on every notification.
    ///
    /// Concurrent callers are serialized with a one-deep queue:
    /// - All callers wait for the running task to finish (`await currentMergeTask?.value`).
    /// - The task clears `currentMergeTask` via `defer` before its `.value` becomes observable,
    ///   so every resuming caller sees nil on the immediately following check.
    /// - Exactly one caller — the first to run on the actor — observes nil and becomes "in charge":
    ///   it creates the next task and awaits it.
    /// - The remaining callers find the new task already set and simply await it, then return.
    func mergeNewTransactions() async {
        self.logger.info("🔀 mergeNewTransactions triggered")
        await currentMergeTask?.value
        // After the running task cleared itself, check whether another concurrent caller
        // already became "in charge" and started a new task. If so, just await it and return.
        if let currentMergeTask {
            await currentMergeTask.value
        } else {
            // We are in charge: start the next merge.
            let task = mergeNewTransactionsTask()
            currentMergeTask = task
            await task.value
        }
    }

    
    private func mergeNewTransactionsTask() -> Task<Void, Never> {
        return Task {
            self.logger.info("🔀🔀 Running mergeNewTransactionsTask")
            defer {
                // Clear before .value becomes observable so all waiters in mergeNewTransactions()
                // see nil and exactly one becomes "in charge" of the next merge.
                self.currentMergeTask = nil
                self.logger.info("🔀🔀 Did run mergeNewTransactionsTask")
            }

            let initialToken = self.lastSeenToken
            let author = self.localTransactionAuthor
            let target = self.targetContext

            let foreignTransactionsFetchResult: ForeignTransactionsFetchResult
            do {
                foreignTransactionsFetchResult = try await fetchForeignTransactions(
                    after: initialToken,
                    excludingAuthor: author)
            } catch {
                self.logger.fault("🔀🔀 Failed to fetch persistent history: \(error.localizedDescription, privacy: .public)")
                // Still refresh the heartbeat so a transient fetch error doesn't make a live consumer
                // look dormant to the prune.
                await self.persistCursor()
                return
            }

            self.logger.info("🔀🔀 Fetched \(foreignTransactionsFetchResult.totalCount, privacy: .public) transaction(s), \(foreignTransactionsFetchResult.foreignTransactions.count, privacy: .public) foreign (excluding author '\(author, privacy: .public)')")

            if foreignTransactionsFetchResult.tokenWasExpired {
                self.logger.fault("🔀🔀 Stored cursor was pruned away — resetting to the current token")
                self.lastConsumedDate = Date.now
            }

            guard !foreignTransactionsFetchResult.foreignTransactions.isEmpty else {
                await self.advanceCursor(from: foreignTransactionsFetchResult, initialToken: initialToken)
                self.logger.info("🔀🔀 No foreign transactions to merge — token advanced")
                return
            }

            let changedObjectIDs = foreignTransactionsFetchResult.foreignTransactions.compactMap({ $0.changes }).flatMap({$0}).map({$0.changedObjectID})
            self.logger.info("🔀🔀 \(foreignTransactionsFetchResult.foreignTransactions.count, privacy: .public) foreign transaction(s) → \(changedObjectIDs.count, privacy: .public) changed object(s) to merge")

            self.logger.info("🔀🔀 Warming row cache …")
            do {
                try await refreshPersistentStore(objectIDs: changedObjectIDs)
            } catch {
                self.logger.fault("🔀🔀 Failed to warm row cache: \(error.localizedDescription, privacy: .public)")
                // Refresh the heartbeat without advancing the cursor: the next notification retries
                // this same window, but a transient failure shouldn't make us look dormant.
                await self.persistCursor()
                return
            }
            self.logger.info("🔀🔀 Row cache warmed")

            for objectID in changedObjectIDs {
                await target.perform {
                    do {
                        if let object = try Self.forceFetchObject(objectID: objectID, within: target) {
                            target.refresh(object, mergeChanges: true)
                            self.logger.info("🔀🔀 Refreshed \(objectID.entity.name ?? "unknown", privacy: .public) in target context")
                        } else {
                            self.logger.info("🔀🔀 Object \(objectID.entity.name ?? "unknown", privacy: .public) not found in store (deleted?) — skipped")
                        }
                    } catch {
                        self.logger.fault("🔀🔀 Failed to refresh object in target context: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            await self.advanceCursor(from: foreignTransactionsFetchResult, initialToken: initialToken)
            self.logger.info("🔀🔀 Merge complete — token advanced")
        }
    }
    
    
    private func refreshPersistentStore(objectIDs: [NSManagedObjectID]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            contextCreator.performBackgroundTask { context in
                do {
                    for objectID in objectIDs {
                        _ = try Self.forceFetchObject(objectID: objectID, within: context)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private static func forceFetchObject(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> NSManagedObject? {
        guard let entityName = objectID.entity.name else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "SELF == %@", objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    /// Fetches persistent history transactions written after `token`, dropping those authored by
    /// `author`. Returns the surviving foreign transactions, the total number of transactions seen
    /// (for logging), and the latest token seen.
    private func fetchForeignTransactions(
        after token: NSPersistentHistoryToken?,
        excludingAuthor author: String
    ) async throws -> ForeignTransactionsFetchResult {
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ForeignTransactionsFetchResult, any Error>) in
            contextCreator.performBackgroundTask { context in
                do {

                    var foreignTransactions: [NSPersistentHistoryTransaction] = []

                    let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
                    guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                          let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                        return continuation.resume(returning: .init(foreignTransactions: [], totalCount: 0, advancedToken: token, advancedDate: nil, tokenWasExpired: false))
                    }
                    let totalCount = transactions.count
                    let latestToken = transactions.last?.token ?? token
                    let latestDate = transactions.last?.timestamp
                    for transaction in transactions where transaction.author != author {
                        foreignTransactions.append(transaction)
                    }

                    return continuation.resume(returning: .init(foreignTransactions: foreignTransactions, totalCount: totalCount, advancedToken: latestToken, advancedDate: latestDate, tokenWasExpired: false))

                } catch let error as NSError where error.code == NSPersistentHistoryTokenExpiredError {
                    // The App pruned history past our stored cursor while we were dormant (see
                    // ObvPersistentHistoryConsumerTokenStore). The pruned window is unrecoverable;
                    // reset to the current token so future fetches succeed. We miss the pruned
                    // changes — degrading to the pre-fix behaviour, never worse.
                    let currentToken = context.persistentStoreCoordinator?.currentPersistentHistoryToken(fromStores: nil)
                    return continuation.resume(returning: .init(foreignTransactions: [], totalCount: 0, advancedToken: currentToken, advancedDate: nil, tokenWasExpired: true))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }

    }

}


private struct ForeignTransactionsFetchResult: Sendable {

    let foreignTransactions: [NSPersistentHistoryTransaction]
    let totalCount: Int
    let advancedToken: NSPersistentHistoryToken?
    /// Timestamp of the latest transaction seen in this fetch (any author), used to advance the
    /// consumer's persisted cursor. `nil` when no transaction was seen.
    let advancedDate: Date?
    /// `true` when the stored cursor token had been pruned away and the fetch was restarted from the
    /// current token. The caller treats this as "reset" rather than a normal advance.
    let tokenWasExpired: Bool

}
