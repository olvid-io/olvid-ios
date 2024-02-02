/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import os.log
import ObvEngine
import CoreData
import ObvUICoreData


final class ProcessNewTrustedContactIdentityOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    let obvContactIdentity: ObvContactIdentity
    
    init(obvContactIdentity: ObvContactIdentity) {
        self.obvContactIdentity = obvContactIdentity
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let existingPersistedObvContactIdentity = try PersistedObvContactIdentity.get(persisted: obvContactIdentity.contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context)

            if let existingPersistedObvContactIdentity {
                
                try existingPersistedObvContactIdentity.updateContact(with: obvContactIdentity)
                
            } else {
                
                let contact = try PersistedObvContactIdentity.createPersistedObvContactIdentity(contactIdentity: obvContactIdentity, within: obvContext.context)
                                
                requestSendingOneToOneDiscussionSharedConfiguration(with: contact, within: obvContext)
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    // We had to create a contact, meaning we had to create/unlock a one2one discussion. In that case, we want to (re)send the discussion shared settings to our contact.
    // This allows to make sure those settings are in sync.
    private func requestSendingOneToOneDiscussionSharedConfiguration(with contact: PersistedObvContactIdentity, within obvContext: ObvContext) {
        do {
            // We had to create a contact, meaning we had to create/unlock a one2one discussion. In that case, we want to (re)send the discussion shared settings to our contact.
            // This allows to make sure those settings are in sync.
            let contactIdentifier = try contact.contactIdentifier
            guard let discussionId = try contact.oneToOneDiscussion?.identifier else { return }
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvMessengerInternalNotification.aDiscussionSharedConfigurationIsNeededByContact(
                    contactIdentifier: contactIdentifier,
                    discussionId: discussionId)
                .postOnDispatchQueue()
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

}
