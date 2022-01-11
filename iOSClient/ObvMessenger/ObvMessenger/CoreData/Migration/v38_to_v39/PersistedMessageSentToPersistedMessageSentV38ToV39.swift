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
import os.log

fileprivate let errorDomain = "MessengerMigrationV38ToV39"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedMessageSentToPersistedMessageSentV38ToV39]"


final class PersistedMessageSentToPersistedMessageSentV38ToV39: NSEntityMigrationPolicy {

    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageSentToPersistedMessageSentV38ToV39")
    
    private let userInfoKey = "replyToValuesForPersistedMessageSent"
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        do {

            let entityName = "PersistedMessageSent"
            let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
            
            // The migration manager eventually needs to know the connection between the source object, the newly created destination object, and the mapping.
            
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // If there is a rawReplyToJSON in the source message, we parse it and store the values for later

            if let sRawReplyToJSON = sInstance.value(forKey: "rawReplyToJSON") as? Data {
                
                dInstance.setValue(true, forKey: "isReplyToAnotherMessage")
                
                let decoder = JSONDecoder()
                let sReplyToJSON: UtilsForAppMigrationV38ToV39.MessageReferenceJSONForMigration
                do {
                    sReplyToJSON = try decoder.decode(UtilsForAppMigrationV38ToV39.MessageReferenceJSONForMigration.self, from: sRawReplyToJSON)
                } catch {
                    assertionFailure()
                    return
                }
                
                try manager.destinationContext.obtainPermanentIDs(for: [dInstance])
                var userInfo = manager.userInfo ?? [AnyHashable: Any]()
                var replyToValuesForMessage = userInfo[userInfoKey] as? [NSManagedObjectID: (senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data)] ?? [NSManagedObjectID: (senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data)]()
                assert(!replyToValuesForMessage.keys.contains(dInstance.objectID))
                replyToValuesForMessage[dInstance.objectID] = (sReplyToJSON.senderSequenceNumber, sReplyToJSON.senderThreadIdentifier, sReplyToJSON.senderIdentifier)
                userInfo[userInfoKey] = replyToValuesForMessage
                manager.userInfo = userInfo
                
            }
            
        } catch {
            os_log("Failed to migrate a PersistedMessageSent: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }

    }
    
    
    
    override func end(_ mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        // This method is called once for this entity, after all relationships of all entities have been re-created.
        
        debugPrint("\(debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) starts")
        defer {
            debugPrint("\(debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) ends")
        }
        
        // We recover all the messages stored in the userInfo dictionary. They correspond to the messages that are replies to another message.
        
        guard let userInfo = manager.userInfo else { return }
        guard let replyToValuesForMessage = userInfo[userInfoKey] as? [NSManagedObjectID: (senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data)] else { return }
        
        for (messageObjectID, replyToValues) in replyToValuesForMessage {
            
            let reply: NSManagedObject?
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "PersistedMessageSent")
                request.predicate = NSPredicate(format: "SELF == %@", messageObjectID)
                request.fetchLimit = 1
                reply = try manager.destinationContext.fetch(request).first
            }
            guard let reply = reply else { assertionFailure(); continue }
            guard let discussion = reply.value(forKey: "discussion") as? NSManagedObject else { continue }
            
            // Look for the message the 'reply' replies to
            
            let repliedToMessage = try UtilsForAppMigrationV38ToV39.getRepliedToMessage(discussion: discussion, replyToValues: replyToValues, manager: manager)

            // If the repliedToMessage is found, we use it to update the reply.
            // If we can't find it, we do nothing (for a sent message, it means that the replied to message was deleted).

            if let repliedToMessage = repliedToMessage {
                reply.setValue(repliedToMessage, forKey: "rawMessageRepliedTo")
            }            
            
        }

    }

}
