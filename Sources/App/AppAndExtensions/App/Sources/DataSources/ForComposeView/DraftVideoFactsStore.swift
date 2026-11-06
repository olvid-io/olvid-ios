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
import ObvMediaTranscoding
import ObvUICoreData
import OlvidUtils


/// What the size menu needs to know about each video of a draft to estimate the sizes that were not exported.
///
/// A clip is read once per launch, the first time the composition bar's model is built with it, and what was read is kept in memory,
/// keyed by the clip's sha256. Nothing is stored in the database: the facts of a file never change, and reading them costs the clip's
/// header only.
final class DraftVideoFactsStore: Sendable {

    static let shared = DraftVideoFactsStore()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DraftVideoFactsStore")

    enum WhatWasRead: Sendable {
        case facts(ObvVideoTranscoder.ClipFacts)
        /// AVFoundation cannot read the clip. Such a clip is never exported, and each of its sizes uses the file of a larger one.
        case nothing
    }

    private struct State {
        var whatWasReadForSha256 = [Data: WhatWasRead]()
        /// The clips being read, each with every caller waiting for it. Not only the one that started the read: a stream started again
        /// during the read would otherwise never be told.
        var callersWaitingForSha256 = [Data: [@Sendable () -> Void]]()
    }

    /// Read from managed object contexts' queues and from the main thread, written from the tasks reading the clips.
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}


    /// What was read from this clip, or nil when it has not been read yet.
    func whatWasRead(fromClipWithSha256 sha256: Data) -> WhatWasRead? {
        state.withLock { $0.whatWasReadForSha256[sha256] }
    }


    /// Reads the clip in the background, unless it was read already, and calls `whenRead` once the result is recorded. A clip being read
    /// is not read twice: the caller waits for the read in flight.
    ///
    /// Cheap enough to call on every rebuild of the composition bar's model.
    func readIfNeeded(clipWithSha256 sha256: Data, attachedAs joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, whenRead: @escaping @Sendable () -> Void) {

        let mustBeRead = state.withLock { state in
            guard state.whatWasReadForSha256[sha256] == nil else { return false }
            let aReadIsInFlight = state.callersWaitingForSha256[sha256] != nil
            state.callersWaitingForSha256[sha256, default: []].append(whenRead)
            return !aReadIsInFlight
        }

        guard mustBeRead else { return }

        Task(priority: .utility) {
            let whatWasRead = await Self.read(clipAttachedAs: joinObjectID)
            let callersWaiting = state.withLock { state in
                state.whatWasReadForSha256[sha256] = whatWasRead
                return state.callersWaitingForSha256.removeValue(forKey: sha256) ?? []
            }
            guard whatWasRead != nil else { return }
            callersWaiting.forEach { $0() }
        }

    }


    /// Nil when there is no hardlink to read the clip through. Nothing is recorded then, so the next rebuild of the model tries again.
    private static func read(clipAttachedAs joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) async -> WhatWasRead? {

        // Through a hardlink, because AVFoundation cannot read a `Fyle`, whose name has no extension.
        let context = ObvStack.shared.newBackgroundContext()
        guard let url = await DraftVideoVariantsMaker.hardlinkURLOfTheAttachedFile(ofJoin: joinObjectID, within: context) else {
            return nil
        }

        let started = Date.now
        let facts = await ObvVideoTranscoder.facts(ofVideoAt: url)
        let milliseconds = Int(Date.now.timeIntervalSince(started) * 1_000)

        guard let facts else {
            logger.notice("🎬 A clip of the draft cannot be read (\(milliseconds, privacy: .public) ms), so the size menu shows each size at the weight of the file it would use")
            return .nothing
        }

        logger.notice("🎬 Read a clip of the draft for the size menu in \(milliseconds, privacy: .public) ms: \(facts.durationInSeconds, privacy: .public) s, \(facts.channelsOfTheSound, privacy: .public) sound channel(s)")
        return .facts(facts)

    }

}
