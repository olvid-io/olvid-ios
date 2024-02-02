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
import os.log
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils

@objc(OutboxAttachmentChunk)
final class OutboxAttachmentChunk: NSManagedObject, ObvManagedObject {
        
    // MARK: Internal constants
    
    private static let entityName = "OutboxAttachmentChunk"
    private static let acknowledgedTimeStampKey = "acknowledgedTimeStamp"
    private static let attachmentNumberKey = "attachmentNumber"
    private static let chunkNumberKey = "chunkNumber"
    private static let ciphertextChunkLengthKey = "ciphertextChunkLength"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    private static let rawMessageIdUidKey = "rawMessageIdUid"
    private static let attachmentKey = "attachment"
    
    private static let errorDomain = "OutboxAttachmentChunk"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Attributes
    
    @NSManaged private(set) var acknowledgedTimeStamp: Date?
    @NSManaged private(set) var attachmentNumber: Int
    @NSManaged private(set) var chunkNumber: Int
    @NSManaged private(set) var ciphertextChunkLength: Int
    @NSManaged private(set) var cleartextChunkLength: Int
    @NSManaged var encryptedChunkURL: URL?
    @NSManaged private var rawAcknowledgerAppType: NSNumber?
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data
    @NSManaged var signedURL: URL?
    
    // MARK: Relationships

    @NSManaged private(set) var attachment: OutboxAttachment?
    
    // MARK: Variables
    
    var obvContext: ObvContext?

    private(set) var acknowledgerAppType: AppType? {
        get {
            if let raw = rawAcknowledgerAppType {
                return AppType(rawValue: Int(truncating: raw))
            } else {
                return nil
            }
        }
        set {
            if let raw = newValue?.rawValue {
                self.rawAcknowledgerAppType = raw as NSNumber
            } else {
                self.rawAcknowledgerAppType = nil
            }
        }
    }

    private(set) var messageId: ObvMessageIdentifier {
        get { return ObvMessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    private(set) var attachmentId: ObvAttachmentIdentifier {
        get { return ObvAttachmentIdentifier(messageId: self.messageId, attachmentNumber: self.attachmentNumber) }
        set { self.messageId = newValue.messageId; self.attachmentNumber = newValue.attachmentNumber }
    }
    
    var isAcknowledged: Bool { acknowledgedTimeStamp != nil }
    
    // MARK: Initializer

    convenience init?(attachment: OutboxAttachment, chunkNumber: Int, ciphertextChunkLength: Int, cleartextChunkLength: Int) {
        guard let obvContext = attachment.obvContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: OutboxAttachmentChunk.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.acknowledgedTimeStamp = nil
        self.attachmentId = attachment.attachmentId
        self.chunkNumber = chunkNumber
        self.encryptedChunkURL = nil
        self.ciphertextChunkLength = ciphertextChunkLength
        self.cleartextChunkLength = cleartextChunkLength
        self.acknowledgerAppType = nil
        self.signedURL = nil
        self.attachment = attachment
    }
}


// MARK: - Other stuff

extension OutboxAttachmentChunk {
        
    func setAcknowledged(by appType: AppType) {
        self.acknowledgedTimeStamp = Date()
        self.acknowledgerAppType = appType
        if let url = encryptedChunkURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func unacknowledge() {
        self.acknowledgedTimeStamp = nil
        self.acknowledgerAppType = nil
        if let url = encryptedChunkURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}


// MARK: - Convenience DB getters

extension OutboxAttachmentChunk {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<OutboxAttachmentChunk> {
        return NSFetchRequest<OutboxAttachmentChunk>(entityName: OutboxAttachmentChunk.entityName)
    }

    static func getAllOrphanedOutboxAttachmentChunk(with obvContext: ObvContext) throws -> [OutboxAttachmentChunk] {
        let request: NSFetchRequest<OutboxAttachmentChunk> = OutboxAttachmentChunk.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", attachmentKey)
        return try obvContext.fetch(request)
    }

    /// This method uses aggregate functions to return the current uploaded byte count for a given `OutboxAttachment` instance.
    static func getCurrentUploadedByteCountOfAttachment(_ attachment: OutboxAttachment) throws -> Int {
        guard let context = attachment.managedObjectContext else { throw OutboxAttachmentChunk.makeError(message: "Context is not set") }
        // Create an expression description that will allow to aggregate the values of the ciphertextChunkLength column
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "uploadedByteCount"
        expressionDescription.expression = NSExpression(format: "@sum.\(ciphertextChunkLengthKey)")
        expressionDescription.expressionResultType = .integer64AttributeType
        // Create a predicate that will restrict to the given attachment and filter out incomplete chunks
        let predicate = NSPredicate(format: "%K == %@ AND %K != NIL",
                                    attachmentKey, attachment,
                                    acknowledgedTimeStampKey)
        // Create the fetch request
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [expressionDescription]
        // Fetch
        guard let results = try context.fetch(request).first as? [String: Int] else { throw makeError(message: "Could cast fetched result") }
        guard let uploadedByteCount = results["uploadedByteCount"] else { throw makeError(message: "Could not get uploadedByteCount") }
        return uploadedByteCount
    }
}
