/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
  

import UIKit
import ObvUICoreData


/// This actor is used within the discussion screen to track the sensitive (read-once or limited visibility) messages shown to the user.
/// This is required to implement the screen capture detection of those sensitive messages.
@MainActor final class VisibilityTrackerForSensitiveMessages {

    private let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    private var permanentIDsOfVisibleMessagesWithLimitedVisibility = Set<ObvManagedObjectPermanentID<PersistedMessage>>()
    
    weak var delegate: VisibilityTrackerForSensitiveMessagesDelegate?

    init(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        self.discussionPermanentID = discussionPermanentID
    }


    func refreshObjectIDsOfVisibleMessagesWithLimitedVisibility(in collectionView: UICollectionView) {
        let newSet = getPermanentIDsOfVisibleMessagesWithLimitedVisibility(in: collectionView)
        guard newSet != permanentIDsOfVisibleMessagesWithLimitedVisibility else { return }
        permanentIDsOfVisibleMessagesWithLimitedVisibility = newSet
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            try? await delegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(self, discussionPermanentID: discussionPermanentID, messagePermanentIDs: newSet)
        }
    }


    private func getPermanentIDsOfVisibleMessagesWithLimitedVisibility(in collectionView: UICollectionView) -> Set<ObvManagedObjectPermanentID<PersistedMessage>> {
        return getPermanentIDsOfVisibleSentMessagesWithLimitedVisibility(in: collectionView)
            .union(getPermanentIDsOfVisibleReceivedMessagesWithLimitedVisibility(in: collectionView))
    }


    private func getPermanentIDsOfVisibleSentMessagesWithLimitedVisibility(in collectionView: UICollectionView) -> Set<ObvManagedObjectPermanentID<PersistedMessage>> {
        let visibleCells = collectionView.visibleCells.compactMap({ $0 as? CellWithPersistedMessageSent })
        let permanentIDsOfVisibleMsgsWithLimitedVisibility = Set(visibleCells
            .compactMap({ $0.messageSent })
            .filter({ $0.isEphemeralMessageWithLimitedVisibility })
            .map({ $0.messagePermanentID }))
        return permanentIDsOfVisibleMsgsWithLimitedVisibility
    }


    func getPermanentIDsOfVisibleReceivedMessagesWithLimitedVisibility(in collectionView: UICollectionView) -> Set<ObvManagedObjectPermanentID<PersistedMessage>> {
        let visibleCells = collectionView.visibleCells.compactMap({ $0 as? CellWithPersistedMessageReceived })
        let permanentIDsOfVisibleMsgsWithLimitedVisibility = Set(visibleCells
            .compactMap({ $0.messageReceived })
            .filter({ $0.isEphemeralMessageWithUserAction && $0.status == .read })
            .map({ $0.messagePermanentID }))
        return permanentIDsOfVisibleMsgsWithLimitedVisibility
    }


}


protocol CellWithPersistedMessageSent {
    var messageSent: PersistedMessageSent? { get }
}


protocol CellWithPersistedMessageReceived {
    var messageReceived: PersistedMessageReceived? { get }
}


protocol VisibilityTrackerForSensitiveMessagesDelegate: AnyObject {
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ visibilityTrackerForSensitiveMessages: VisibilityTrackerForSensitiveMessages, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws
}
