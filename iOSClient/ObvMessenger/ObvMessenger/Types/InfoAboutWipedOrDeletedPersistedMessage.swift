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

enum WipedOrDeleted {
    case wiped
    case deleted
}

/// Informations computed by ``PersistedMessage.wipe()`` or ``PersistedMessage.delete`` and used by ``InfoAboutWipedOrDeletedPersistedMessage.refresh`` to refresh view context or  ``InfoAboutWipedOrDeletedPersistedMessage.notify`` to post notification about deleted or wiped messages.
/// We did not do it in each didSave to avoid to posting too many notifications.
struct InfoAboutWipedOrDeletedPersistedMessage {
    
    let kind: WipedOrDeleted
    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>

    
    /// Sends either a `persistedMessagesWereWiped` or a `persistedMessagesWereDeleted` notification for each wiped or deleted message associated to the `infos`.
    static func notifyThatMessagesWereWipedOrDeleted(_ infos: [InfoAboutWipedOrDeletedPersistedMessage]) {
        var discussionToWipeMessages = [ObvManagedObjectPermanentID<PersistedDiscussion>: [ObvManagedObjectPermanentID<PersistedMessage>]]()
        var discussionToDeletedMessages = [ObvManagedObjectPermanentID<PersistedDiscussion>: [ObvManagedObjectPermanentID<PersistedMessage>]]()
        for info in infos {
            switch info.kind {
            case .wiped:
                let messages = discussionToWipeMessages[info.discussionPermanentID] ?? []
                discussionToWipeMessages[info.discussionPermanentID] = messages + [info.messagePermanentID]
            case .deleted:
                let messages = discussionToDeletedMessages[info.discussionPermanentID] ?? []
                discussionToDeletedMessages[info.discussionPermanentID] = messages + [info.messagePermanentID]
            }
        }

        for (discussionPermanentID, messagePermanentIDs) in discussionToWipeMessages {
            ObvMessengerCoreDataNotification.persistedMessagesWereWiped(discussionPermanentID: discussionPermanentID, messagePermanentIDs: Set(messagePermanentIDs))
                .postOnDispatchQueue()
        }

        for (discussionPermanentID, messagePermanentIDs) in discussionToDeletedMessages {
            ObvMessengerCoreDataNotification.persistedMessagesWereDeleted(discussionPermanentID: discussionPermanentID, messagePermanentIDs: Set(messagePermanentIDs))
                .postOnDispatchQueue()
        }

    }


    /// After deleting or wiping a message, we usually want to refresh the view context to make sure the deletion is reflected at the UI level. This helper methods allows to refresh the view context to do just that.
    static func refresh(viewContext: NSManagedObjectContext, _ infos: [InfoAboutWipedOrDeletedPersistedMessage]) {
        viewContext.perform {
            for messagePermanentID in infos.map({ $0.messagePermanentID }) {
                guard let message = try? PersistedMessage.getManagedObject(withPermanentID: messagePermanentID, within: viewContext) else { continue }
                viewContext.refresh(message, mergeChanges: false)
            }
            for discussionPermanentID in Set(infos.map({ $0.discussionPermanentID })) {
                guard let discussion = try? PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: viewContext) else { continue }
                viewContext.refresh(discussion, mergeChanges: false)
            }
        }

    }
}
