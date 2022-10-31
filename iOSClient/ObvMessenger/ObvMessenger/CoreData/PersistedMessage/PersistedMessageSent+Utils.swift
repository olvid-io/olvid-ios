/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

extension PersistedMessageSent {

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    /// This method returns the number of outbound messages within the specified discussion that are at least in the `sent` state, and
    /// that occur after the message passed as a parameter.
    /// This method is typically used for displaying count based retention information for a specific message.
    static func countAllSentMessages(after messageObjectID: NSManagedObjectID, discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard let message = try PersistedMessage.get(with: messageObjectID, within: context) else {
            throw makeError(message: "Cannot find message to compare to")
        }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.wasSent,
            Predicate.withLargerSortIndex(than: message)
        ])
        return try context.count(for: request)
    }

    
    /// Called when a sent message with limited visibility reached the end of this visibility (in which case the `requester` is `nil`)
    /// or when a message was globally wiped (in which case the requester is non nil)
    func wipe(requester: RequesterOfMessageDeletion?) throws {
        if let requester = requester {
            try throwIfRequesterIsNotAllowedToDeleteMessage(requester: requester)
        }
        switch requester {
        case .ownedIdentity, .none:
            guard !isLocallyWiped else { return }
        case .contact:
            guard !isRemoteWiped else { return }
        }
        for join in fyleMessageJoinWithStatuses {
            try join.wipe()
        }
        self.deleteBody()
        try? self.reactions.forEach { try $0.delete() }
        switch requester {
        case .ownedIdentity, .none:
            try addMetadata(kind: .wiped, date: Date())
        case .contact(_, let contactCryptoId, _):
            try addMetadata(kind: .remoteWiped(remoteCryptoId: contactCryptoId), date: Date())
        }
        // It makes no sense to keep an existing visibility expiration (if one exists) since we just wiped the message.
        try expirationForSentLimitedVisibility?.delete()
        // It makes no sense to keep unprocessed PersistedMessageSentRecipientInfos since we won't resend this message anymore
        let unprocessedRecipientInfos = unsortedRecipientsInfos.filter({ $0.messageIdentifierFromEngine == nil })
        unprocessedRecipientInfos.forEach({ try? $0.delete() })
    }

    /// If `retainWipedOutboundMessages` is `true`, this method only wipes the message. Otherwise, it deletes it.
    /// For now, this method is always used with a `nil` requester (meaning that no check will be performed before wiping or deleting messages), since it is called on expired sent messages.
    func wipeOrDelete(requester: RequesterOfMessageDeletion?) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        if retainWipedOutboundMessages {
            do {
                let wipeInfo = InfoAboutWipedOrDeletedPersistedMessage(kind: .wiped,
                                                                       discussionID: self.discussion.typedObjectID,
                                                                       messageID: self.typedObjectID.downcast)
                try wipe(requester: requester)
                return wipeInfo
            } catch {
                assertionFailure()
                return try delete(requester: requester)
            }
        } else {
            return try delete(requester: requester)
        }
    }

}
