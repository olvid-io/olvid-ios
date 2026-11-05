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
import ObvAppCoreConstants
import ObvAppTypes


/// Persists "mark as read" intents emitted by Siri so the app can honor them on next launch.
///
/// Siri may fire `INSetMessageAttributeIntent(.read)` against a message that lives only in the
/// Notification Service Extension database (no `PersistedMessageReceived` row yet), or that
/// hasn't even reached the NSE database yet (engine fetch path). In both cases the Intents
/// extension cannot directly mark the row as read — it has to record the intent and let the
/// app process it when the message eventually surfaces.
///
/// Storage is an App Group `UserDefaults` suite shared between the Intents extension and the
/// main app. Entries are `(ObvMessageAppIdentifier.description, unix-timestamp)` pairs. The
/// timestamp lets ``pruneEntriesOlderThan(_:referenceDate:)`` drop stale entries that the app
/// never had a chance to consume (sender deleted the message before delivery, etc.).
///
/// **Concurrency.** In-process serialisation is provided by actor isolation. Cross-process
/// atomicity (Intents extension and main app modifying the store concurrently) is not
/// enforced. Both processes use a read-modify-write cycle on `UserDefaults`, so a concurrent
/// write from the other process causes last-writer-wins: the loser's entire snapshot overwrites
/// the winner's, potentially dropping all entries written in the same window (not just one).
/// The window is very short and the write frequency is low in practice, so this is acceptable.
/// All dropped intents are recoverable — the message will simply remain unread until the user
/// explicitly marks it again.
public actor SiriReadIntentStore {

    public static let shared = SiriReadIntentStore()

    private let defaults: UserDefaults
    private let storeKey: String

    /// Default initializer wires the store to the App Group `UserDefaults` suite. `defaults`
    /// and `storeKey` are exposed for tests.
    public init(
        defaults: UserDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)!,
        storeKey: String = "io.olvid.SiriReadIntentStore.entries"
    ) {
        self.defaults = defaults
        self.storeKey = storeKey
    }


    /// Records that Siri asked us to mark `messageAppIdentifier` as read. Overwrites any
    /// previous timestamp so the TTL starts again from the latest intent.
    public func markAsReadBySiri(_ messageAppIdentifier: ObvMessageAppIdentifier, at date: Date = Date.now) {
        var entries = currentEntries()
        entries[messageAppIdentifier.description] = date.timeIntervalSince1970
        defaults.set(entries, forKey: storeKey)
    }


    /// Returns the timestamp at which Siri marked `messageAppIdentifier` as read, if such an
    /// intent is pending in the store; `nil` otherwise. Callers use the timestamp as the read
    /// date when transitioning the message to `.read` on the app side, so the persisted
    /// `dateWhenMessageWasRead` reflects the actual Siri-mark moment rather than the (later)
    /// app-database insert moment.
    public func dateMarkedAsReadBySiri(_ messageAppIdentifier: ObvMessageAppIdentifier) -> Date? {
        guard let timestamp = currentEntries()[messageAppIdentifier.description] else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }


    /// Returns every message identifier currently recorded as read-by-Siri.
    ///
    /// Used by the Intents extension's `INSearchForMessagesIntent` handler to exclude NSE-only
    /// messages that Siri already read aloud (and marked read) but that haven't yet drained into
    /// the app database — without this, a fresh "read my new messages" triggered by a newly
    /// arrived message would re-read them. The window is bounded: an entry exists from the moment
    /// Siri marks the message until ``consume(_:)`` runs at app-drain time, which is exactly when
    /// the message gains a `PersistedMessageReceived` (and the NSE-DB fetch starts excluding it on
    /// its own `wasPersistedInApp` filter). Keys that can no longer be parsed are skipped.
    public func allMarkedAsReadBySiri() -> Set<ObvMessageAppIdentifier> {
        return Set(currentEntries().keys.compactMap { ObvMessageAppIdentifier($0) })
    }


    /// Removes the entry for `messageAppIdentifier`. Call this once the app has successfully
    /// applied the read state to its database (so the same intent isn't re-applied on every
    /// drain pass).
    public func consume(_ messageAppIdentifier: ObvMessageAppIdentifier) {
        var entries = currentEntries()
        guard entries.removeValue(forKey: messageAppIdentifier.description) != nil else { return }
        defaults.set(entries, forKey: storeKey)
    }


    /// Drops entries older than `ttl`. Intended to be called periodically from the app (e.g.
    /// at launch) so the store doesn't grow unbounded when senders delete messages before
    /// delivery or the user uninstalls a contact.
    public func pruneEntriesOlderThan(_ ttl: TimeInterval, referenceDate: Date = Date()) {
        let entries = currentEntries()
        let threshold = referenceDate.timeIntervalSince1970 - ttl
        let kept = entries.filter { $0.value >= threshold }
        guard kept.count != entries.count else { return }
        defaults.set(kept, forKey: storeKey)
    }


    private func currentEntries() -> [String: Double] {
        return (defaults.dictionary(forKey: storeKey) as? [String: Double]) ?? [:]
    }

}
