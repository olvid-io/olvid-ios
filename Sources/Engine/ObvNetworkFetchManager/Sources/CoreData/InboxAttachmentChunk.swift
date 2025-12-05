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
import OSLog
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager

@objc(InboxAttachmentChunk)
final class InboxAttachmentChunk: NSManagedObject {
        
    // MARK: Internal constants
    
    private static let entityName = "InboxAttachmentChunk"

    // MARK: Attributes

    @NSManaged private(set) var attachmentNumber: Int
    @NSManaged private(set) var chunkNumber: Int
    @NSManaged private(set) var ciphertextChunkLength: Int
    @NSManaged private(set) var cleartextChunkWasWrittenToAttachmentFile: Bool
    @NSManaged private var rawCleartextChunkLength: NSNumber? // Known as soon as the decryption key is known
    @NSManaged private var rawMessageIdOwnedIdentity: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawMessageIdUid: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged var signedURL: URL?

    // MARK: Relationships

    @NSManaged private(set) var attachment: InboxAttachment?

    // MARK: Variables
    
    // Known as soon as the decryption key is known
    private(set) var cleartextChunkLength: Int? {
        get { rawCleartextChunkLength?.intValue }
        set { rawCleartextChunkLength = newValue == nil ? nil : newValue! as NSNumber }
    }

    /// This identifier is expected to be non nil, unless this `InboxAttachmentChunk` was deleted on another thread.
    private(set) var messageId: ObvMessageIdentifier? {
        get {
            guard let rawMessageIdOwnedIdentity = self.rawMessageIdOwnedIdentity else { return nil }
            guard let rawMessageIdUid = self.rawMessageIdUid else { return nil }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid)
        }
        set {
            guard let newValue else { assertionFailure("We should not be setting a nil value"); return }
            self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity()
            self.rawMessageIdUid = newValue.uid.raw
        }
    }

    /// This identifier is expected to be non nil, unless this `InboxAttachmentChunk` was deleted on another thread.
    private(set) var attachmentId: ObvAttachmentIdentifier? {
        get {
            guard let messageId = self.messageId else { return nil }
            return ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: self.attachmentNumber)
        }
        set {
            guard let newValue else { assertionFailure("We should not be setting a nil value"); return }
            self.messageId = newValue.messageId
            self.attachmentNumber = newValue.attachmentNumber
        }
    }

    // MARK: Initializer

    convenience init?(attachment: InboxAttachment, chunkNumber: Int, ciphertextChunkLength: Int) {
        guard let context = attachment.managedObjectContext else { assertionFailure(); return nil }
        guard let attachmentId = attachment.attachmentId else { assertionFailure(); return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: InboxAttachmentChunk.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.attachmentId = attachmentId
        self.chunkNumber = chunkNumber
        self.cleartextChunkWasWrittenToAttachmentFile = false
        self.ciphertextChunkLength = ciphertextChunkLength
        self.cleartextChunkLength = nil
        self.signedURL = nil
        self.attachment = attachment
    }

    
    func deleteInboxAttachmentChunk() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        self.resetDownload()
        context.delete(self)
    }
    
}


// MARK: - Other stuff

extension InboxAttachmentChunk {
        
    func resetDownload() {
        guard self.cleartextChunkWasWrittenToAttachmentFile else { return }
        self.cleartextChunkWasWrittenToAttachmentFile = false
    }
    
    func setCleartextChunkWasWrittenToAttachmentFile() {
        guard !cleartextChunkWasWrittenToAttachmentFile else { return }
        cleartextChunkWasWrittenToAttachmentFile = true
    }

    func setCleartextChunkLengthForDecryptionKey(_ key: AuthenticatedEncryptionKey) throws -> Int {
        guard self.cleartextChunkLength == nil else { throw ObvError.cleartextChunkLengthAlreadySet }
        let cleartextChunkLength = try Chunk.cleartextLengthFromEncryptedLength(self.ciphertextChunkLength, whenUsingEncryptionKey: key)
        self.cleartextChunkLength = cleartextChunkLength
        return cleartextChunkLength
    }
    
}


// MARK: - Convenience DB getters

extension InboxAttachmentChunk {
    
    struct Predicate {
        
        enum Key: String {
            // Attributes
            case attachmentNumber = "attachmentNumber"
            case chunkNumber = "chunkNumber"
            case ciphertextChunkLength = "ciphertextChunkLength"
            case cleartextChunkWasWrittenToAttachmentFile = "cleartextChunkWasWrittenToAttachmentFile"
            case rawCleartextChunkLength = "rawCleartextChunkLength"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case signedURL = "signedURL"
            // Relationships
            case attachment = "attachment"
        }
        
        static var withNoAttachment: NSPredicate {
            NSPredicate(withNilValueForKey: Key.attachment)
        }
        
        static func withMessageId(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: messageId.ownedCryptoIdentity.getIdentity()),
                NSPredicate(Key.rawMessageIdUid, EqualToData: messageId.uid.raw),
            ])
        }
        
        static func withAttachmentId(_ attachmentId: ObvAttachmentIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withMessageId(attachmentId.messageId),
                NSPredicate(Key.attachmentNumber, EqualToInt: attachmentId.attachmentNumber),
            ])
        }
        
        static func cleartextChunkWasWrittenToAttachmentFile(is bool: Bool) -> NSPredicate {
            NSPredicate(Key.cleartextChunkWasWrittenToAttachmentFile, is: bool)
        }
        
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<InboxAttachmentChunk> {
        return NSFetchRequest<InboxAttachmentChunk>(entityName: InboxAttachmentChunk.entityName)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: InboxAttachmentChunk.entityName)
        fetch.predicate = Predicate.withNoAttachment
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }

    static func getAllMissingAttachmentChunks(ofAttachmentId attachmentId: ObvAttachmentIdentifier, within context: NSManagedObjectContext) throws -> [InboxAttachmentChunk] {
        let request: NSFetchRequest<InboxAttachmentChunk> = InboxAttachmentChunk.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withAttachmentId(attachmentId),
            Predicate.cleartextChunkWasWrittenToAttachmentFile(is: false),
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
}


// MARK: - Errors

extension InboxAttachmentChunk {
    
    enum ObvError: Error {
        case noContext
        case cleartextChunkLengthAlreadySet
    }
    
}
