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
import OSLog
import ObvAppCoreConstants
import ObvUICoreData
import OlvidUtils


/// How far the export of each of the draft's clips has got.
///
/// Written by `DraftVideoVariantsMaker`, from its actor. A composition-bar tile reads ``fractionCompleted(forJoin:)`` when it is built and
/// follows ``progressUpdates(forJoin:)`` after that. Tiles sit in a `LazyHStack` and are rebuilt when scrolled back into view, so the value
/// must be readable at any time: a queued clip reports 0 only once.
///
/// Also holds how far the draft as a whole has got, which the composition bar shows while a send waits for the exports, the tiles
/// being too small to say it for the whole draft.
final class DraftVideoExportProgressStore: @unchecked Sendable {

    static let shared = DraftVideoExportProgressStore()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DraftVideoExportProgressStore")

    private struct State {
        var joins = Channels<TypeSafeManagedObjectID<PersistedDraftFyleJoin>>()
        var drafts = Channels<TypeSafeManagedObjectID<PersistedDraft>>()
    }

    /// A fraction per key, and the streams following each key.
    private struct Channels<Key: Hashable> {

        var fractionForKey = [Key: Double]()
        var continuationsForKey = [Key: [UUID: AsyncStream<Double?>.Continuation]]()

        /// Records the fraction, a nil removing it, and returns the streams to yield it to.
        mutating func record(_ fractionCompleted: Double?, for key: Key) -> [AsyncStream<Double?>.Continuation] {
            if let fractionCompleted {
                fractionForKey[key] = fractionCompleted
            } else {
                fractionForKey.removeValue(forKey: key)
            }
            return Array((continuationsForKey[key] ?? [:]).values)
        }

        mutating func add(_ continuation: AsyncStream<Double?>.Continuation, id: UUID, for key: Key) {
            continuationsForKey[key, default: [:]][id] = continuation
        }

        mutating func removeContinuation(id: UUID, for key: Key) {
            continuationsForKey[key]?[id] = nil
            if continuationsForKey[key]?.isEmpty == true {
                continuationsForKey.removeValue(forKey: key)
            }
        }

    }

    /// Written from the maker's actor, read from the main actor and from managed object contexts' queues.
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}


    // MARK: - Each attachment

    /// How far the export of this attachment has got, or nil when nothing is being exported for it.
    func fractionCompleted(forJoin joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) -> Double? {
        state.withLock { $0.joins.fractionForKey[joinObjectID] }
    }


    /// Records how far an attachment's export has got and yields it to the streams following that attachment. A nil removes the entry: the
    /// maker reports nil when nothing is being exported for the attachment, whether the export finished, failed or was abandoned.
    func record(_ fractionCompleted: Double?, forJoin joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        let continuations = state.withLock { $0.joins.record(fractionCompleted, for: joinObjectID) }
        continuations.forEach { $0.yield(fractionCompleted) }
    }


    /// The progress of this attachment's export: the current value, then every change.
    ///
    /// Each call returns a new stream, which ends when its consumer stops iterating it. A nil means nothing is being exported and does not
    /// end the stream: the attachment is exported again if the reader changes size.
    func progressUpdates(forJoin joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) -> AsyncStream<Double?> {
        let (stream, continuation) = AsyncStream.makeStream(of: Double?.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.joins.removeContinuation(id: id, for: joinObjectID) }
        }
        // Registered and seeded under the lock, so that no write falls between the two.
        state.withLock {
            $0.joins.add(continuation, id: id, for: joinObjectID)
            continuation.yield($0.joins.fractionForKey[joinObjectID])
        }
        return stream
    }


    // MARK: - The whole draft

    /// Records how far the exports of a draft's pass have got, between 0 and 1, and yields it to the streams following that draft. A nil
    /// means the pass has no export left to run, whether it finished, failed or was cancelled.
    func record(_ fractionCompleted: Double?, forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        let continuations = state.withLock { $0.drafts.record(fractionCompleted, for: draftObjectID) }
        continuations.forEach { $0.yield(fractionCompleted) }
    }


    /// How far the exports of this draft have got: the current value, then every change. Same contract as ``progressUpdates(forJoin:)``.
    func progressUpdates(forDraft draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) -> AsyncStream<Double?> {
        let (stream, continuation) = AsyncStream.makeStream(of: Double?.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.drafts.removeContinuation(id: id, for: draftObjectID) }
        }
        state.withLock {
            $0.drafts.add(continuation, id: id, for: draftObjectID)
            continuation.yield($0.drafts.fractionForKey[draftObjectID])
        }
        return stream
    }

}
