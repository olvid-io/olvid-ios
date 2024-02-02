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
import ObvTypes
import ObvEncoder
import ObvCrypto
import ObvMetaManager
import os.log

fileprivate let errorDomain = "ObvEngineMigrationV21ToV23"
fileprivate let debugPrintPrefix = "[\(errorDomain)][OutboxAttachmentToOutboxAttachmentMigrationPolicyV21ToV23]"

final class OutboxAttachmentToOutboxAttachmentMigrationPolicyV21ToV23: NSEntityMigrationPolicy {
    
    private let log = OSLog(subsystem: "io.olvid.messenger", category: "CoreDataStack")
    
    private var numberOfDestinationInstancesCreated = 0

    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {

        os_log("Starting migration of OutboxAttachment entities...", log: log, type: .info)

        let entitiesNames = ["Backup", "BackupKey", "ChannelCreationWithContactDeviceProtocolInstance", "ContactDevice", "ContactGroup", "ContactGroupDetails", "ContactGroupDetailsLatest", "ContactGroupDetailsPublished", "ContactGroupDetailsTrusted", "ContactGroupJoined", "ContactGroupOwned", "ContactIdentity", "ContactIdentityDetails", "ContactIdentityDetailsPublished", "ContactIdentityDetailsTrusted", "InboxAttachment", "InboxMessage", "KeyMaterial", "LinkBetweenProtocolInstances", "MessageHeader", "ObvObliviousChannel", "OutboxAttachment", "OutboxAttachmentUploadHistory", "OutboxMessage", "OutboxMessageUploadHistory", "OwnedDevice", "OwnedIdentity", "OwnedIdentityDetails", "OwnedIdentityDetailsLatest", "OwnedIdentityDetailsPublished", "OwnedIdentityMaskingUID", "PendingDeleteFromServer", "PendingGroupMember", "PendingServerQuery", "PersistedEngineDialog", "PersistedTrustOrigin", "ProtocolInstance", "ProtocolInstanceWaitingForTrustLevelIncrease", "Provision", "ReceivedMessage", "RegisteredPushNotification", "ServerSession"]
        
        for name in entitiesNames {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: name)
            let count: Int
            do {
                count = try manager.sourceContext.count(for: fetchRequest)
            } catch {
                os_log("Could not count the number of %{public}@ entities", log: log, type: .fault, name)
                continue
            }
            os_log("There are %{public}d %{public}@ entities to migrate", log: log, type: .info, count, name)
        }
        
        // Displaying information about each provision
        do {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Provision")
            let provisions: [NSManagedObject]
            do {
                provisions = try manager.sourceContext.fetch(fetchRequest)
            } catch {
                os_log("Could not fetch provisions: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            for provision in provisions {
                
                os_log("--- Displaying information about a provision ---", log: log, type: .info)
                
                // We display information about the current provision
                guard let obliviousChannel = provision.value(forKey: "obliviousChannel") as? NSManagedObject else {
                    os_log("Could not get obliviousChannel of the provision", log: log, type: .fault)
                    continue
                }
                guard let remoteDeviceUid = obliviousChannel.value(forKey: "remoteDeviceUid") as? UID else {
                    os_log("Could not get remoteDeviceUid of the channel", log: log, type: .fault)
                    continue
                }
                os_log("remoteDeviceUid: %{public}@", log: log, type: .info, remoteDeviceUid.debugDescription)
                guard let fullRatchetingCount = provision.value(forKey: "fullRatchetingCount") as? Int else {
                    os_log("Could not get full ratching count of the provision", log: log, type: .fault)
                    continue
                }
                os_log("fullRatchetingCount: %{public}d", log: log, type: .info, fullRatchetingCount)
                guard let selfRatchetingCount = provision.value(forKey: "selfRatchetingCount") as? Int else {
                    os_log("Could not get self ratching count of the provision", log: log, type: .fault)
                    continue
                }
                os_log("selfRatchetingCount: %{public}d", log: log, type: .info, selfRatchetingCount)
                
                // We display information about the KeyMaterial of the provision
                guard let receiveKeys = provision.value(forKey: "receiveKeys") as? Set<NSManagedObject> else {
                    os_log("Could not get receiveKeys of the provision", log: log, type: .fault)
                    continue
                }
                let numberOfExpiringKeys = receiveKeys.filter({ $0.value(forKey: "expirationTimestamp") != nil }).count
                let numberOfNotExpiringKeys = receiveKeys.filter({ $0.value(forKey: "expirationTimestamp") == nil }).count
                os_log("Number of receiveKeys: %{public}d - %{public}d expiring and %{public}d not expiring", log: log, type: .info, receiveKeys.count, numberOfExpiringKeys, numberOfNotExpiringKeys)

            }
        }

    }

    override func end(_ mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        os_log("Finishing migration of OutboxAttachment entities...", log: log, type: .info)
    }
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        os_log("Creating an OutboxAttachment instance. Number of instances created so far: %{public}d", log: log, type: .info, numberOfDestinationInstancesCreated)
        defer {
            numberOfDestinationInstancesCreated += 1
            os_log("Done with the creation of an OutboxAttachment instance. Number of instances created so far: %{public}d", log: log, type: .info, numberOfDestinationInstancesCreated)
        }

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "OutboxAttachment",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // The main reason we define a custom migration policy for OutboxAttachment instances is to create associated OutboxAttachmentChunk instances.
        // We do so now.
                
        // Step 1: Determine the number, size, etc. of the chunks for this attachment.

        guard let attachmentLength = sInstance.value(forKey: "attachmentLength") as? Int else {
            throw makeError(message: "Could not get the attachmentLength value")
        }

        guard let encodedAuthenticatedEncryptionKey = sInstance.value(forKey: "encodedAuthenticatedEncryptionKey") as? Data else {
            throw makeError(message: "Could not get the encodedAuthenticatedEncryptionKey value")
        }

        let authenticatedEncryptionKey = try! AuthenticatedEncryptionKeyDecoder.decode(ObvEncoded(withRawData: encodedAuthenticatedEncryptionKey)!)
        
        let chunksValues = UtilsForMigrationV21ToV23.computeChunksValues(fromAttachmentLength: attachmentLength, whenUsingEncryptionKey: authenticatedEncryptionKey)
        
        // Step 2: Initialize an OutboxAttachmentChunk instance for each chunk
        
        for chunkNumber in 0..<chunksValues.requiredNumberOfChunks {

            let ciphertextChunkLength = chunkNumber == chunksValues.requiredNumberOfChunks-1 ? chunksValues.lastEncryptedChunkLength : chunksValues.encryptedChunkTypicalLength
            let cleartextChunkLength = chunkNumber == chunksValues.requiredNumberOfChunks-1 ? chunksValues.lastCleartextChunkLength : chunksValues.cleartextChunkTypicalLength
            
            // Step 2a : Initialize the NSManagedObject
            
            let chunkInstance: NSManagedObject
            do {
                let outboxAttachmentChunkEntityName = "OutboxAttachmentChunk"
                guard let description = NSEntityDescription.entity(forEntityName: outboxAttachmentChunkEntityName, in: manager.destinationContext) else {
                    let message = "Invalid entity name: \(outboxAttachmentChunkEntityName)"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                chunkInstance = NSManagedObject(entity: description, insertInto: manager.destinationContext)
            }

            // Step 2b : Set all the required variables

            do {
                guard let attachmentNumber = sInstance.value(forKey: "attachmentNumber") as? Int else {
                    let message = "Could not read attachmentNumber from attachment"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                chunkInstance.setValue(attachmentNumber, forKey: "attachmentNumber")
            }
            chunkInstance.setValue(chunkNumber, forKey: "chunkNumber")
            chunkInstance.setValue(ciphertextChunkLength, forKey: "ciphertextChunkLength")
            chunkInstance.setValue(cleartextChunkLength, forKey: "cleartextChunkLength")
            do {
                guard let rawMessageIdOwnedIdentity = sInstance.value(forKey: "rawMessageIdOwnedIdentity") as? Data else {
                    let message = "Could not read rawMessageIdOwnedIdentity from attachment"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                guard let rawMessageIdUid = sInstance.value(forKey: "rawMessageIdUid") as? Data else {
                    let message = "Could not read rawMessageIdUid from attachment"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                guard ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid) != nil else {
                    let message = "Either rawMessageIdOwnedIdentity or rawMessageIdUid is not appropriate"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                chunkInstance.setValue(rawMessageIdOwnedIdentity, forKey: "rawMessageIdOwnedIdentity")
                chunkInstance.setValue(rawMessageIdUid, forKey: "rawMessageIdUid")
            }
            
            // Step 2c : Set the association

            chunkInstance.setValue(dInstance, forKey: "attachment")
            
        }

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.

        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
