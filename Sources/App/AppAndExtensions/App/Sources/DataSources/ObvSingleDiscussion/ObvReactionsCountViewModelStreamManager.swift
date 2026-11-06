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
import ObvSingleDiscussion
import ObvUICoreData
import OlvidUtils


/// Follows the reactions made on one message, folded into emoji-and-count pairs.
///
/// **Two fetched results controllers**, because a reaction is one of two entities that share no common fetchable one: the reader's own reaction is a
/// `PersistedMessageReactionSent`, of which there is at most one, and everybody else's are `PersistedMessageReactionReceived`.
///
/// It is a file of its own, and not nested in the data source that first needed it, because **two screens want the same stream**: the sheet listing who reacted, and
/// — since step 20a — the chip under a message in the SwiftUI discussion. A copy in each would be two answers to one question.
final class ObvReactionsCountViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleDiscussion.ObvReactionsCountViewModel, PersistedMessageReactionSent, PersistedMessageReactionReceived>, @unchecked Sendable {

    init(messageIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.MessageIdentifier, context: NSManagedObjectContext) throws {
        let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
        switch messageIdentifier {
        case .objectID(let objectID):
            messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
        case .forPreview:
            assertionFailure()
            throw ObvError.unexpectedMessageIdentifierType
        }
        let frc1 = PersistedMessageReactionSent.getFetchedResultsControllerForSentReactionOnMessage(
            messageObjectID: messageObjectID,
            within: context)
        let frc2 = PersistedMessageReactionReceived.getFetchedResultsControllerForReceivedReactionOnMessage(
            messageObjectID: messageObjectID,
            within: context)
        super.init(frc1: frc1, frc2: frc2)
    }


    override func createModel(fetchedObjects1: [PersistedMessageReactionSent], fetchedObjects2: [PersistedMessageReactionReceived]) throws -> ObvReactionsCountViewModel {

        let reactionsSent = fetchedObjects1
        let reactionsReceived = fetchedObjects2

        var reactions = [Character]()
        if let reactionSent = reactionsSent.first, let emoji = reactionSent.emoji, let reaction = emoji.first {
            reactions.append(reaction)
        }
        reactions.append(contentsOf: reactionsReceived.compactMap({ reactionReceived in
            guard let emoji = reactionReceived.emoji, let reaction = emoji.first else { return nil }
            return reaction

        }))

        var countForReaction = [Character: Int]()
        for reaction in reactions {
            var count = countForReaction[reaction, default: 0]
            count += 1
            countForReaction[reaction] = count
        }

        let reactionsAndCount: [ObvReactionsCountViewModel.ReactionAndCount] = countForReaction.map { (reaction, count) in
            return ObvReactionsCountViewModel.ReactionAndCount(emoji: reaction, count: count)
        }

        return .init(reactionsAndCount: reactionsAndCount)
    }


    enum ObvError: Error {
        case unexpectedMessageIdentifierType
    }

}
