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
import CoreData
import ObvTypes
import ObvEncoder
import ObvCrypto
import ObvMetaManager

fileprivate let errorDomain = "ObvEngineMigrationV24ToV25"
fileprivate let debugPrintPrefix = "[\(errorDomain)][InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25]"

final class InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25: NSEntityMigrationPolicy {
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "InboxAttachment",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // Get the initial byte count to download
        guard let initialByteCountToDownload = sInstance.value(forKey: "initialByteCountToDownload") as? Int else {
            throw makeError(message: "Could not get the initialByteCountToDownload value")
        }

        // Get the expected chunk length
        guard let expectedChunkLength = sInstance.value(forKey: "expectedChunkLength") as? Int else {
            throw makeError(message: "Could not get the expectedChunkLength value")
        }

        // Get the attachment number
        guard let attachmentNumber = sInstance.value(forKey: "attachmentNumber") as? Int else {
            throw makeError(message: "Could not get the attachmentNumber value")
        }

        // Get the attachment raw owned identity
        guard let rawMessageIdOwnedIdentity = sInstance.value(forKey: "rawMessageIdOwnedIdentity") as? Data else {
            throw makeError(message: "Could not get the rawMessageIdOwnedIdentity value")
        }

        // Get the attachment rawMessageIdUid
        guard let rawMessageIdUid = sInstance.value(forKey: "rawMessageIdUid") as? Data else {
            throw makeError(message: "Could not get the rawMessageIdUid value")
        }
        
        // Compute the chunks values
        let chunkValues = InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.computeEncryptedChunksValues(initialByteCountToDownload: initialByteCountToDownload, encryptedChunkTypicalLength: expectedChunkLength)

        // Create the chunks
        var allChunks = [NSManagedObject]()
        for chunkNumber in 0..<chunkValues.requiredNumberOfChunks {
            
            let ciphertextChunkLength = chunkNumber < chunkValues.requiredNumberOfChunks-1 ? expectedChunkLength : chunkValues.lastEncryptedChunkLength
            
            // Create an instance of the destination object.
            let dChunk: NSManagedObject
            do {
                let entityName = "InboxAttachmentChunk"
                guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                    let message = "Invalid entity name: \(entityName)"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                dChunk = NSManagedObject(entity: description, insertInto: manager.destinationContext)
            }

            // Set all the attributes of the chunk
            dChunk.setValue(attachmentNumber, forKey: "attachmentNumber")
            dChunk.setValue(chunkNumber, forKey: "chunkNumber")
            dChunk.setValue(ciphertextChunkLength, forKey: "ciphertextChunkLength")
            dChunk.setValue(false, forKey: "cleartextChunkWasWrittenToAttachmentFile")
            dChunk.setValue(nil, forKey: "downloadedTimeStamp")
            dChunk.setValue(nil, forKey: "encryptedChunkURL")
            dChunk.setValue(nil, forKey: "rawCleartextChunkLength") // We will deal with this below
            dChunk.setValue(rawMessageIdOwnedIdentity, forKey: "rawMessageIdOwnedIdentity")
            dChunk.setValue(rawMessageIdUid, forKey: "rawMessageIdUid")
            dChunk.setValue(nil, forKey: "signedURL")
            
            dChunk.setValue(dInstance, forKey: "attachment")
            
            allChunks.append(dChunk)
        }
        
        // In case the attachment decryption is available, we can compute the chunks cleartext length and create the attachment file
        
        // Look for the encodedAuthenticatedDecryptionKey
        guard let encodedAuthenticatedDecryptionKey = sInstance.value(forKey: "encodedAuthenticatedDecryptionKey") as? Data? else {
            throw makeError(message: "Could not get the encodedAuthenticatedDecryptionKey value")
        }
        
        if let encodedKey = encodedAuthenticatedDecryptionKey, let key = InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.decodeKey(encodedKeyData: encodedKey) {

            // Set the ciphertextChunkLength of all the chunks and create the attachment file

            var totalCleartextLength = 0
            for chunk in allChunks {
                let ciphertextChunkLength = chunk.value(forKey: "ciphertextChunkLength") as! Int // Was set above
                let cleartextChunkLength = try InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.chunkCleartextLengthFromEncryptedLength(ciphertextChunkLength, whenUsingEncryptionKey: key)
                chunk.setValue(cleartextChunkLength, forKey: "rawCleartextChunkLength")
                totalCleartextLength += cleartextChunkLength
            }
            
            guard let inbox = InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.createAndConfigureInbox() else {
                throw makeError(message: "Could not create/configure inbox")
            }

            guard let messageId = ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid) else {
                throw makeError(message: "Could not create message identifier")
            }
            let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
            
            try createEmptyFileForWritingChunks(withinInbox: inbox, cleartextLength: totalCleartextLength, attachmentId: attachmentId)
            
        }
        
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.

        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
        
}

// MARK: - Utils

extension InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25 {
    
    public static func chunkCleartextLengthFromEncryptedLength(_ encryptedLength: Int, whenUsingEncryptionKey key: AuthenticatedEncryptionKey) throws -> Int {
        let encodedChunkLength = try AuthenticatedEncryption.plaintexLength(forCiphertextLength: encryptedLength, whenDecryptedUnder: key)
        return Chunk.lengthOfInnerData(forLengthOfObvEncodedChunk: encodedChunkLength)!
    }
    
    private static func computeEncryptedChunksValues(initialByteCountToDownload: Int, encryptedChunkTypicalLength: Int) -> (lastEncryptedChunkLength: Int, requiredNumberOfChunks: Int) {
        let requiredNumberOfChunks = 1 + (initialByteCountToDownload-1) / encryptedChunkTypicalLength
        let lastEncryptedChunkLength = initialByteCountToDownload - (requiredNumberOfChunks-1) * encryptedChunkTypicalLength
        return (lastEncryptedChunkLength, requiredNumberOfChunks)
    }

    
    private static func decodeKey(encodedKeyData: Data) -> AuthenticatedEncryptionKey? {
        guard let encodedKey = ObvEncoded(withRawData: encodedKeyData) else { return nil }
        return try! AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
    }
    
    private static func getAttachmentDirectory(withinInbox inbox: URL, messageId: ObvMessageIdentifier) -> URL {
        let directoryName = messageId.directoryNameForMessageAttachments
        return inbox.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func getAttachmentURL(withinInbox inbox: URL, attachmentId: ObvAttachmentIdentifier) -> URL {
        let attachmentFileName = "\(attachmentId.attachmentNumber)"
        let url = InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.getAttachmentDirectory(withinInbox: inbox, messageId: attachmentId.messageId).appendingPathComponent(attachmentFileName)
        return url
    }

    private static func createAttachmentsDirectoryIfRequired(withinInbox inbox: URL, messageId: ObvMessageIdentifier) throws {
        let attachmentsDirectory = getAttachmentDirectory(withinInbox: inbox, messageId: messageId)
        guard !FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return }
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: false)
    }

    private func createEmptyFileForWritingChunks(withinInbox inbox: URL, cleartextLength: Int, attachmentId: ObvAttachmentIdentifier) throws {
        
        let url = InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.getAttachmentURL(withinInbox: inbox, attachmentId: attachmentId)

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                throw makeError(message: "Could not delete previous attachment directory: \(error.localizedDescription)")
            }
        }
        
        try InboxAttachmentToInboxAttachmentMigrationPolicyV24ToV25.createAttachmentsDirectoryIfRequired(withinInbox: inbox, messageId: attachmentId.messageId)
        
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
            throw makeError(message: "Could not create file for writting chunks")
        }
        
        guard let fh = FileHandle(forWritingAtPath: url.path) else { throw makeError(message: "Could get FileHandle") }
        fh.seek(toFileOffset: UInt64(cleartextLength))
        fh.closeFile()
        
    }

    
    private static func createAndConfigureInbox() -> URL? {
        
        let nameOfDirectory = "inbox"
        
        // Create the box
        
        let box = mainContainerURL.appendingPathComponent(nameOfDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            debugPrint(error.localizedDescription)
            return nil
        }
        
        // Configure the box
        
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        do {
            var mutableBox = box
            try mutableBox.setResourceValues(resourceValues)
        } catch let error {
            debugPrint(error.localizedDescription)
            return nil
        }
        
        // Validate the box
        
        do {
            let urlResources = try box.resourceValues(forKeys: Set([.isDirectoryKey, .isWritableKey, .isExcludedFromBackupKey]))
            guard urlResources.isDirectory! else { return nil }
            guard urlResources.isWritable! else { return nil }
            guard urlResources.isExcludedFromBackup! else { return nil }
        } catch let error {
            debugPrint(error.localizedDescription)
            return nil
        }
        
        return box
    }

    
    private static let mainContainerURL: URL = {
        let appGroupIdentifier = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String
        let securityApplicationGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
        return securityApplicationGroupURL.appendingPathComponent("Engine", isDirectory: true)
    }()

}
