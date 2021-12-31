/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

fileprivate let errorDomain = "MessengerMigrationV17ToV18"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedMessageSentToPersistedMessageSentMigrationPolicyV17ToV18]"


final class PersistedMessageSentToPersistedMessageSentMigrationPolicyV17ToV18: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "PersistedMessageSent"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // Get the discussion associtad with the message
        
        guard let discussion = sInstance.value(forKey: "discussion") as? NSManagedObject else {
            let message = "Could not get discussion"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        // Whether we create PersistedMessageSentRecipientInfos or not depends on the nature of the discussion...
                
        if discussion.entity.name == "PersistedOneToOneDiscussion" {
            
            // If the discussion is a OneToOne discussion, we can create the PersistedMessageSentRecipientInfos for this message, since the recipient identity is clear.

            guard let contactIdentity = discussion.value(forKey: "contactIdentity") as? NSManagedObject else {
                let message = "Could not get contactIdentity in OneToOne discussion"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            
            guard let recipientIdentity = contactIdentity.value(forKey: "identity") as? Data else {
                let message = "Could not get identity of a contact identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            
            // Get the message identifier from engine
            
            guard let messageIdentifierFromEngine = sInstance.value(forKey: "messageIdentifierFromEngine") as? Data else {
                let message = "Could not get messageIdentifierFromEngine of a source instance"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            
            // Get the sentTimestamp

            guard let sentTimestamp = sInstance.value(forKey: "sentTimestamp") as? Date else {
                let message = "Could not get sentTimestamp of a source instance"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            
            // Create the PersistedMessageSentRecipientInfos instance
            
            let recipientInfos: NSManagedObject
            do {
                guard let description = NSEntityDescription.entity(forEntityName: "PersistedMessageSentRecipientInfos", in: manager.destinationContext) else {
                    let message = "Invalid entity name: \(entityName)"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                recipientInfos = NSManagedObject(entity: description, insertInto: manager.destinationContext)
            }

            // Set all the values of the PersistedMessageSentRecipientInfos
            
            recipientInfos.setValue(messageIdentifierFromEngine, forKey: "messageIdentifierFromEngine")
            recipientInfos.setValue(recipientIdentity, forKey: "recipientIdentity")
            recipientInfos.setValue(nil, forKey: "timestampDelivered")
            recipientInfos.setValue(nil, forKey: "timestampRead")
            recipientInfos.setValue(sentTimestamp, forKey: "timestampSent")

            recipientInfos.setValue(dInstance, forKey: "messageSent")

        } else {

            /* If the discussion is a group discussion or a locked group discussion, we cannot create one PersistedMessageSentRecipientInfos per contact
             * who received this message since the information of who was in the group at the time the message was sent
             * was not kept until now. We simply discard the sentTimestamp and messageIdentifierFromEngine and set the
             * unsortedRecipientsInfos to an empty set. This requires no line of code ;-) But this `if` statement shall not
             * be removed.
             */
            
            // If the discussion is a oneToOne discussion, the contact has been lost, so we do nothing.
            
        }
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
}
