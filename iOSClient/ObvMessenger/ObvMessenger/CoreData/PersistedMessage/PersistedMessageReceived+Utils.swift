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


// MARK: - Thread safe struct

extension PersistedMessageReceived {
    
    struct Structure {
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageReceived>
        let textBody: String?
        let messageIdentifierFromEngine: Data
        let contact: PersistedObvContactIdentity.Structure
        let attachmentsCount: Int
        let attachementImages: [NotificationAttachmentImage]?

        fileprivate let abstractStructure: PersistedMessage.AbstractStructure
        var isReplyToAnotherMessage: Bool { abstractStructure.isReplyToAnotherMessage }
        var readOnce: Bool { abstractStructure.readOnce }
        var forwarded: Bool { abstractStructure.forwarded }
        var discussionKind: PersistedDiscussion.StructureKind { abstractStructure.discussionKind }
        var timestamp: Date { abstractStructure.timestamp }
    }
    
    func toStruct() throws -> Structure {
        guard let contact = self.contactIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required relationships")
        }
        return Structure(objectPermanentID: self.objectPermanentID,
                         textBody: self.textBody,
                         messageIdentifierFromEngine: self.messageIdentifierFromEngine,
                         contact: try contact.toStruct(),
                         attachmentsCount: fyleMessageJoinWithStatuses.count,
                         attachementImages: fyleMessageJoinWithStatuses.compactMap { $0.attachementImage },
                         abstractStructure: try toAbstractStructure())
    }
    
}
