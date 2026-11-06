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
import Intents
import ObvAppTypes
import ObvCommunicationInteractor
import ObvUICoreData


extension PersistedDiscussion {

    static func discussionAsINPersonFromDiscussionIdentifier(_ discussionIdentifier: ObvDiscussionIdentifier) async throws -> INPerson? {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<INPerson?, any Error>, context: NSManagedObjectContext) in
            guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: context) else {
                return continuation.resume(returning: nil)
            }
            // Siri-sourced identifiers may point at a discussion whose owned profile has since been hidden.
            guard discussion.ownedIdentity?.isHidden == false else {
                return continuation.resume(returning: nil)
            }
            let discussionINPerson = try discussion.toINPerson(withImage: true)
            return continuation.resume(returning: discussionINPerson)
        }
    }


    /// Resolves a single `INSpeakableString` group name to an `INSpeakableStringResolutionResult`.
    ///
    /// If `groupName.vocabularyIdentifier` already encodes a valid `ObvDiscussionIdentifier` (set by
    /// a prior resolution pass), the discussion title is refreshed from the database and `.success`
    /// is returned immediately. Otherwise a group-discussion search is performed against the spoken
    /// phrase (`.success` on exact match, `.confirmationRequired` on fuzzy, `.disambiguation` on
    /// multiple results, `.unsupported` when nothing is found).
    static func resolveGroupName(_ groupName: INSpeakableString) async -> INSpeakableStringResolutionResult {
        if let vocabularyIdentifier = groupName.vocabularyIdentifier,
           let discussionIdentifier = ObvDiscussionIdentifier(vocabularyIdentifier) {
            let title: String
            do {
                title = try await fetchTitle(for: discussionIdentifier) ?? groupName.spokenPhrase
            } catch {
                title = groupName.spokenPhrase
            }
            return .success(with: INSpeakableString(vocabularyIdentifier: vocabularyIdentifier,
                                                    spokenPhrase: title,
                                                    pronunciationHint: nil))
        }
        return await resolveGroupBySearchQuery(groupName.spokenPhrase)
    }


    private static func resolveGroupBySearchQuery(_ query: String) async -> INSpeakableStringResolutionResult {
        do {
            return try await withCheckedThrowingContextualContinuation { (continuation, context) in
                let discussions = try PersistedDiscussion.searchDiscussions(searchTerm: query, kind: .group, with: context)
                switch discussions.count {
                case ...0:
                    continuation.resume(returning: .unsupported())
                case 1:
                    let discussion = discussions.first!
                    let identifier = try discussion.discussionIdentifier
                    let speakableString = INSpeakableString(vocabularyIdentifier: identifier.description,
                                                           spokenPhrase: discussion.title,
                                                           pronunciationHint: nil)
                    let isExactMatch = discussion.title.caseInsensitiveCompare(query) == .orderedSame
                    continuation.resume(returning: isExactMatch ? .success(with: speakableString) : .confirmationRequired(with: speakableString))
                default:
                    let speakableStrings = discussions.compactMap { discussion -> INSpeakableString? in
                        guard let identifier = try? discussion.discussionIdentifier else { return nil }
                        return INSpeakableString(vocabularyIdentifier: identifier.description,
                                                spokenPhrase: discussion.title,
                                                pronunciationHint: nil)
                    }
                    continuation.resume(returning: speakableStrings.isEmpty ? .unsupported() : .disambiguation(with: speakableStrings))
                }
            }
        } catch {
            return .unsupported()
        }
    }


    private static func fetchTitle(for discussionIdentifier: ObvDiscussionIdentifier) async throws -> String? {
        return try await withCheckedThrowingContextualContinuation { (continuation, context) in
            guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: context) else {
                return continuation.resume(returning: nil)
            }
            // Siri-sourced identifiers may point at a discussion whose owned profile has since been hidden.
            guard discussion.ownedIdentity?.isHidden == false else {
                return continuation.resume(returning: nil)
            }
            continuation.resume(returning: discussion.title)
        }
    }

}
