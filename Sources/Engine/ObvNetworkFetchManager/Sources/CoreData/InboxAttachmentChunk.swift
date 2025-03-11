/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils

@objc(InboxAttachmentChunk)
final class InboxAttachmentChunk: NSManagedObject, ObvManagedObject {
        
    // MARK: Internal constants
    
    private static let entityName = "InboxAttachmentChunk"
    private static let attachmentKey = "attachment"
    private static let cleartextChunkWasWrittenToAttachmentFileKey = "cleartextChunkWasWrittenToAttachmentFile"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    private static let rawMessageIdUidKey = "rawMessageIdUid"
    private static let attachmentNumberKey = "attachmentNumber"

    private static let errorDomain = "InboxAttachmentChunk"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

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
    
    weak var obvContext: ObvContext?
    
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
        guard let obvContext = attachment.obvContext else { return nil }
        guard let attachmentId = attachment.attachmentId else { assertionFailure(); return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: InboxAttachmentChunk.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.attachmentId = attachmentId
        self.chunkNumber = chunkNumber
        self.cleartextChunkWasWrittenToAttachmentFile = false
        self.ciphertextChunkLength = ciphertextChunkLength
        self.cleartextChunkLength = nil
        self.signedURL = nil
        self.attachment = attachment
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
        guard self.cleartextChunkLength == nil else { throw InboxAttachmentChunk.makeError(message: "Cleartext chunk length already set")}
        let cleartextChunkLength = try Chunk.cleartextLengthFromEncryptedLength(self.ciphertextChunkLength, whenUsingEncryptionKey: key)
        self.cleartextChunkLength = cleartextChunkLength
        return cleartextChunkLength
    }
    
}


// MARK: - Convenience DB getters

extension InboxAttachmentChunk {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<InboxAttachmentChunk> {
        return NSFetchRequest<InboxAttachmentChunk>(entityName: InboxAttachmentChunk.entityName)
    }

    static func deleteAllOrphaned(within obvContext: ObvContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: InboxAttachmentChunk.entityName)
        fetch.predicate = NSPredicate(format: "%K == NIL", attachmentKey)
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try obvContext.execute(request)
    }

    static func getAllMissingAttachmentChunks(ofAttachmentId attachmentId: ObvAttachmentIdentifier, within obvContext: ObvContext) throws -> [InboxAttachmentChunk] {
        let request: NSFetchRequest<InboxAttachmentChunk> = InboxAttachmentChunk.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %d AND %K == FALSE",
                                        rawMessageIdOwnedIdentityKey, attachmentId.messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        rawMessageIdUidKey, attachmentId.messageId.uid.raw as NSData,
                                        attachmentNumberKey, attachmentId.attachmentNumber,
                                        cleartextChunkWasWrittenToAttachmentFileKey)
        return try obvContext.fetch(request)
    }
}
