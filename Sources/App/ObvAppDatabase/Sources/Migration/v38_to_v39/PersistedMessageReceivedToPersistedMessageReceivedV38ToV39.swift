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
import ObvAppCoreConstants

fileprivate let errorDomain = "MessengerMigrationV38ToV39"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedMessageReceivedToPersistedMessageReceivedV38ToV39]"


final class PersistedMessageReceivedToPersistedMessageReceivedV38ToV39: NSEntityMigrationPolicy {

    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedMessageReceivedToPersistedMessageReceivedV38ToV39")
    
    private let userInfoKey = "replyToValuesForPersistedMessageReceived"

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        do {

            let entityName = "PersistedMessageReceived"
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
            os_log("Failed to migrate a PersistedMessageReceived: %{public}@", log: log, type: .fault, error.localizedDescription)
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
            
            let reply = manager.destinationContext.object(with: messageObjectID)
            guard let discussion = reply.value(forKey: "discussion") as? NSManagedObject else { assertionFailure(); continue }
            
            // Look for the message the 'reply' replies to
            
            let repliedToMessage = try UtilsForAppMigrationV38ToV39.getRepliedToMessage(discussion: discussion, replyToValues: replyToValues, manager: manager)

            // If the repliedToMessage is found, we use it to update the reply.
            // If we can't find it, we create a `PendingRepliedTo` instance and set the `messageRepliedToIdentifier` relationship of the reply.
            
            if let repliedToMessage = repliedToMessage {
                reply.setValue(repliedToMessage, forKey: "rawMessageRepliedTo")
            } else {
                let pendingRepliedTo: NSManagedObject
                do {
                    let entityDescription = NSEntityDescription.entity(forEntityName: "PendingRepliedTo", in: manager.destinationContext)!
                    pendingRepliedTo = NSManagedObject(entity: entityDescription, insertInto: manager.destinationContext)
                    pendingRepliedTo.setValue(Date(), forKey: "creationDate")
                    pendingRepliedTo.setValue(replyToValues.senderSequenceNumber, forKey: "senderSequenceNumber")
                    pendingRepliedTo.setValue(replyToValues.senderThreadIdentifier, forKey: "senderThreadIdentifier")
                    pendingRepliedTo.setValue(replyToValues.senderIdentifier, forKey: "senderIdentifier")
                }
                reply.setValue(pendingRepliedTo, forKey: "messageRepliedToIdentifier")
            }
            
        }
                
    }

}
