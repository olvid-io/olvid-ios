/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import OlvidUtils
import ObvServerInterface
import ObvCrypto


final class ProcessMessagesThatWereDeletedFromServerOrMarkedAsListedOnServerOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory]
    private let inbox: URL

    init(ownedCryptoIdentity: ObvCryptoIdentity, messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], inbox: URL) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.messageUIDsAndCategories = messageUIDsAndCategories
        self.inbox = inbox
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        for messageUIDAndCategory in messageUIDsAndCategories {
            let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedCryptoIdentity, uid: messageUIDAndCategory.messageUID)
            let category = messageUIDAndCategory.category
            switch category {
            case .requestDeletion:
                do {
                    let attachmentsDirectory = try InboxMessage.deleteMessage(messageId: messageId, inbox: inbox, within: obvContext.context)
                    if let attachmentsDirectory {
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            guard FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return }
                            try? FileManager.default.removeItem(at: attachmentsDirectory)
                        }
                    }
                } catch {
                    assertionFailure()
                    // In production, continue anyway
                }
            case .markAsListed:
                do {
                    try InboxMessage.markAsListedOnServer(messageId: messageId, within: obvContext.context)
                } catch {
                    assertionFailure()
                    // In production, continue anyway
                }
            }
        }
    }
    
}
