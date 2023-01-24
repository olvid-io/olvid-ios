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
  

import UIKit


/// This actor is used within the discussion screen to track the sensitive (read-once or limited visibility) messages shown to the user.
/// This is required to implement the screen capture detection of those sensitive messages.
@MainActor final class VisibilityTrackerForSensitiveMessages {

    private let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    private var objectIDsOfVisibleMessagesWithLimitedVisibility = Set<TypeSafeManagedObjectID<PersistedMessage>>()

    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.discussionObjectID = discussionObjectID
    }


    func refreshObjectIDsOfVisibleMessagesWithLimitedVisibility(in collectionView: UICollectionView) {
        let newSet = getObjectIDsOfVisibleMessagesWithLimitedVisibility(in: collectionView)
        guard newSet != objectIDsOfVisibleMessagesWithLimitedVisibility else { return }
        objectIDsOfVisibleMessagesWithLimitedVisibility = newSet
        debugPrint("🧯", newSet)
        NewSingleDiscussionNotification.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(discussionObjectID: discussionObjectID, messageObjectIDs: newSet)
            .postOnDispatchQueue()
    }


    private func getObjectIDsOfVisibleMessagesWithLimitedVisibility(in collectionView: UICollectionView) -> Set<TypeSafeManagedObjectID<PersistedMessage>> {
        return getObjectIDsOfVisibleSentMessagesWithLimitedVisibility(in: collectionView)
            .union(getObjectIDsOfVisibleReceivedMessagesWithLimitedVisibility(in: collectionView))
    }


    private func getObjectIDsOfVisibleSentMessagesWithLimitedVisibility(in collectionView: UICollectionView) -> Set<TypeSafeManagedObjectID<PersistedMessage>> {
        let visibleCells = collectionView.visibleCells.compactMap({ $0 as? CellWithPersistedMessageSent })
        let objectIDsOfVisibleMsgsWithLimitedVisibility = Set(visibleCells
            .compactMap({ $0.messageSent })
            .filter({ $0.isEphemeralMessageWithLimitedVisibility })
            .map({ $0.typedObjectID.downcast }))
        return objectIDsOfVisibleMsgsWithLimitedVisibility
    }


    func getObjectIDsOfVisibleReceivedMessagesWithLimitedVisibility(in collectionView: UICollectionView) -> Set<TypeSafeManagedObjectID<PersistedMessage>> {
        let visibleCells = collectionView.visibleCells.compactMap({ $0 as? CellWithPersistedMessageReceived })
        let objectIDsOfVisibleMsgsWithLimitedVisibility = Set(visibleCells
            .compactMap({ $0.messageReceived })
            .filter({ $0.isEphemeralMessageWithUserAction && $0.status == .read })
            .map({ $0.typedObjectID.downcast }))
        return objectIDsOfVisibleMsgsWithLimitedVisibility
    }


}


protocol CellWithPersistedMessageSent {
    var messageSent: PersistedMessageSent? { get }
}


protocol CellWithPersistedMessageReceived {
    var messageReceived: PersistedMessageReceived? { get }
}
