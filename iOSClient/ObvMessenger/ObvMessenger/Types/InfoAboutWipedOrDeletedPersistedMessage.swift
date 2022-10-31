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
    let discussionID: TypeSafeManagedObjectID<PersistedDiscussion>
    let messageID: TypeSafeManagedObjectID<PersistedMessage>


    /// Sends either a `persistedMessagesWereWiped` or a `persistedMessagesWereDeleted` notification for each wiped or deleted message associated to the `infos`.
    static func notifyThatMessagesWereWipedOrDeleted(_ infos: [InfoAboutWipedOrDeletedPersistedMessage]) {
        var discussionToWipeMessages = [TypeSafeManagedObjectID<PersistedDiscussion>: [TypeSafeManagedObjectID<PersistedMessage>]]()
        var discussionToDeletedMessages = [TypeSafeManagedObjectID<PersistedDiscussion>: [TypeSafeManagedObjectID<PersistedMessage>]]()
        for info in infos {
            switch info.kind {
            case .wiped:
                let messages = discussionToWipeMessages[info.discussionID] ?? []
                discussionToWipeMessages[info.discussionID] = messages + [info.messageID]
            case .deleted:
                let messages = discussionToDeletedMessages[info.discussionID] ?? []
                discussionToDeletedMessages[info.discussionID] = messages + [info.messageID]
            }
        }

        for (discussionID, messageIDs) in discussionToWipeMessages {
            ObvMessengerCoreDataNotification.persistedMessagesWereWiped(discussionUriRepresentation: discussionID.uriRepresentation(), messageUriRepresentations: Set(messageIDs.map({ $0.uriRepresentation()})))
                .postOnDispatchQueue()
        }

        for (discussionID, messageIDs) in discussionToDeletedMessages {
            ObvMessengerCoreDataNotification.persistedMessagesWereDeleted(discussionUriRepresentation: discussionID.uriRepresentation(), messageUriRepresentations: Set(messageIDs.map({ $0.uriRepresentation()})))
                .postOnDispatchQueue()
        }

    }


    /// After deleting or wiping a message, we usually want to refresh the view context to make sure the deletion is reflected at the UI level. This helper methods allows to refresh the view context to do just that.
    static func refresh(viewContext: NSManagedObjectContext, _ infos: [InfoAboutWipedOrDeletedPersistedMessage]) {
        viewContext.perform {
            for messageID in infos.map({ $0.messageID }) {
                guard let message = try? PersistedMessage.get(with: messageID, within: viewContext) else { continue }
                viewContext.refresh(message, mergeChanges: false)
            }
            for discussionID in Set(infos.map({ $0.discussionID })) {
                guard let discussion = try? PersistedDiscussion.get(objectID: discussionID, within: viewContext) else { continue }
                viewContext.refresh(discussion, mergeChanges: false)
            }
        }

    }
}
