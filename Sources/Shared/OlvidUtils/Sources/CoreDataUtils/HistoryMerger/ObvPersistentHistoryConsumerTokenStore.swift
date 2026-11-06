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


/// Tracks, per persistent-history *consumer* (the main app, the Intents extension, …), how far that
/// consumer has read the App database's persistent history. Backed by an App Group `UserDefaults`
/// suite so separate processes share the same view.
///
/// ## Why this exists
///
/// `NSPersistentHistoryChangeRequest.deleteHistory(...)` permanently drops history transactions.
/// With a single in-process consumer, pruning "everything before the current token" at launch is
/// safe (see ``ObvPersistentHistoryMerger`` for that invariant). But once a *second process* — the
/// Intents extension — also consumes the same history via its own ``ObvPersistentHistoryMerger``,
/// the app's launch-time prune can delete transactions the extension hasn't read yet, so the
/// extension never learns about those writes (e.g. messages the app marked as read). The result is
/// stale data: the extension keeps treating already-read messages as new.
///
/// The fix is the standard multi-consumer pattern: prune only history older than the *furthest-behind
/// live consumer*. Each consumer records the timestamp of the latest transaction it has merged
/// (``recordConsumed(author:consumedDate:activeDate:)``); the pruner takes the minimum across live
/// consumers (``pruneWatermarkDate(activeWithin:now:)``) as the cut-off. The pruning process is not a
/// special case: it simply records its own cursor as "now" first (it is about to restart its own
/// consumer from the current token), so the uniform minimum does not hold itself back.
///
/// ## Liveness (heartbeat + horizon)
///
/// A consumer that is uninstalled or simply never runs again must not pin the watermark forever, or
/// history would grow without bound. Each record carries a `lastActiveDate` heartbeat (updated on
/// every merge cycle, even no-op cycles). The watermark ignores any consumer whose heartbeat is
/// older than the caller-supplied `horizon`. A consumer that wakes up after being ignored may have a
/// cursor pointing into already-pruned history; ``ObvTransactionsMerger`` handles that case by
/// resetting to the current token (it then misses the pruned window — degrading to the pre-fix
/// behaviour, never worse).
///
/// ## Why dates, not tokens
///
/// `NSPersistentHistoryToken` is opaque and not `Comparable`, so a minimum over tokens can't be
/// computed. Persistent-history transactions carry a `timestamp`, and `deleteHistory(before:)`
/// accepts a `Date`. Storing dates makes the watermark a simple `min`, keeps the stored values
/// `Sendable`, and sidesteps archiving the non-`Sendable` token across concurrency boundaries.
///
/// ## Concurrency
///
/// Actor isolation serialises in-process access. Cross-process atomicity is *not* enforced: both
/// processes do a read-modify-write on `UserDefaults`, so a concurrent write is last-writer-wins and
/// may drop the other process's most recent record. This only ever makes a watermark slightly more
/// conservative (older) or briefly drops a heartbeat, both of which are self-healing on the next
/// merge cycle, so it is acceptable here.
public actor ObvPersistentHistoryConsumerTokenStore {

    private let defaults: UserDefaults
    private let storeKey: String

    private static let consumedKey = "consumed"
    private static let activeKey = "active"

    /// Default liveness horizon: a consumer whose heartbeat is older than this is treated as dormant
    /// and ignored by the prune watermark, bounding history growth.
    public static let defaultActiveConsumerHorizon: TimeInterval = 7 * 24 * 60 * 60

    /// - Parameters:
    ///   - defaults: the App Group `UserDefaults` suite shared by all consumer processes.
    ///   - storeKey: the key under which the per-consumer dictionary is stored.
    public init(defaults: UserDefaults,
                storeKey: String = "io.olvid.ObvPersistentHistoryConsumerTokenStore.cursors") {
        self.defaults = defaults
        self.storeKey = storeKey
    }


    /// Records that `author` has merged history up to `consumedDate` and was active at `activeDate`.
    ///
    /// `consumedDate` should be the timestamp of the latest transaction the consumer has merged. It
    /// only moves forward in practice; callers pass their initialization time on first record (the
    /// consumer has effectively merged everything up to its launch). `activeDate` is the heartbeat
    /// and should be updated on every merge cycle, even cycles that merged nothing.
    public func recordConsumed(author: String, consumedDate: Date, activeDate: Date) {
        var entries = currentEntries()
        entries[author] = [
            Self.consumedKey: consumedDate.timeIntervalSince1970,
            Self.activeKey: activeDate.timeIntervalSince1970,
        ]
        defaults.set(entries, forKey: storeKey)
    }


    /// Returns the earliest `consumedDate` among consumers whose heartbeat is within `horizon` of
    /// `now`. Returns `nil` when no such consumer exists, which the pruner interprets as "no live
    /// consumer to protect — prune up to the current token".
    ///
    /// The caller is expected to have already recorded its *own* up-to-date cursor (via
    /// ``recordConsumed(author:consumedDate:activeDate:)`` with `now`) before calling this, so the
    /// minimum is not held back by the pruning process's own stale cursor. There is no special-casing
    /// of any author here.
    public func pruneWatermarkDate(activeWithin horizon: TimeInterval, now: Date) -> Date? {
        let entries = currentEntries()
        let activeThreshold = now.timeIntervalSince1970 - horizon
        let liveConsumedDates: [TimeInterval] = entries.compactMap { (_, value) in
            guard let active = value[Self.activeKey], active >= activeThreshold else { return nil }
            guard let consumed = value[Self.consumedKey] else { return nil }
            return consumed
        }
        guard let earliest = liveConsumedDates.min() else { return nil }
        return Date(timeIntervalSince1970: earliest)
    }


    private func currentEntries() -> [String: [String: Double]] {
        return (defaults.dictionary(forKey: storeKey) as? [String: [String: Double]]) ?? [:]
    }

}
