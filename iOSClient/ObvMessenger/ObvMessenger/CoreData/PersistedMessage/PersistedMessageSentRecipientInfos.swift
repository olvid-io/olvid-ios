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
import ObvEngine
import ObvCrypto
import os.log

@objc(PersistedMessageSentRecipientInfos)
final class PersistedMessageSentRecipientInfos: NSManagedObject {
    
    private static let entityName = "PersistedMessageSentRecipientInfos"
    private static let messageIdentifierFromEngineKey = "messageIdentifierFromEngine"
    private static let recipientIdentityKey = "recipientIdentity"
    private static let returnReceiptNonceKey = "returnReceiptNonce"
    private static let timestampDeliveredKey = "timestampDelivered"
    private static let ownedIdentityKey = ["messageSent", PersistedMessageSent.discussionKey, PersistedDiscussion.ownedIdentityKey, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageSentRecipientInfos")
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: - Attributes

    @NSManaged private(set) var messageIdentifierFromEngine: Data?
    @NSManaged private var recipientIdentity: Data
    @NSManaged private(set) var returnReceiptKey: Data?
    @NSManaged private var returnReceiptNonce: Data?
    /// Set when the all the attachments have been sent. If the message has no attachment, this is set at the same time `timestampMessageSent` is set.
    @NSManaged private(set) var timestampAllAttachmentsSent: Date?
    @NSManaged private(set) var timestampDelivered: Date?
    @NSManaged private(set) var timestampRead: Date?
    /// Set when the server receives the message (but not the attachments). This timestamp is returned by the server.
    @NSManaged private(set) var timestampMessageSent: Date?
    /// At creation, this contains a list of all the attachment numbers that remain to be sent. When the server confirms the reception of an attachment, we remove its number from this list. When this list is empty, we set the `timestampAllAttachmentsSent` to the device current date.

    // MARK: - Relationships
    
    @NSManaged private(set) var messageSent: PersistedMessageSent

    // MARK: - Computed variables
    
    var recipientCryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: recipientIdentity)
    }
    
    func getRecipient() throws -> PersistedObvContactIdentity? {
        guard let ownedIdentity = self.messageSent.discussion.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it has just been deleted.", log: log, type: .error)
            return nil
        }
        return try PersistedObvContactIdentity.get(cryptoId: recipientCryptoId,
                                                   ownedIdentity: ownedIdentity)
    }
        
    var recipientName: String {
        guard let recipient = try? getRecipient() else { return "-" }
        return recipient.customDisplayName ?? recipient.fullDisplayName
    }
    
    var returnReceiptElements: (nonce: Data, key: Data)? {
        return (self.returnReceiptNonce, self.returnReceiptKey) as? (Data, Data) ?? nil
    }

    /// We consider that a message and its attachments are sent when the message is received by the server (i.e., `timestampMessageSent` is not `nil`)
    /// and the attachments have been fully received by the server (i.e., `timestampAllAttachmentsSent` is not `nil`).
    /// For a message without attachment, the `timestampMessageSent` is sufficient.
    var messageAndAttachmentsAreSent: Bool {
        timestampMessageSent != nil && timestampAllAttachmentsSent != nil
    }

}


// MARK: - Initializer

extension PersistedMessageSentRecipientInfos {
    
    /// Shall *only* be called from within the intialiazer of `PersistedMessageSent`.
    convenience init?(recipientIdentity: Data, messageSent: PersistedMessageSent) {
     
        guard let context = messageSent.managedObjectContext else { return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedMessageSentRecipientInfos.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        do {
            _ = try ObvCryptoId(identity: recipientIdentity)
        } catch {
            return nil
        }
        
        self.messageIdentifierFromEngine = nil
        self.recipientIdentity = recipientIdentity
        self.returnReceiptKey = nil
        self.returnReceiptNonce = nil
        self.timestampDelivered = nil
        self.timestampRead = nil
        self.timestampMessageSent = nil
        self.timestampAllAttachmentsSent = nil
        
        self.messageSent = messageSent
     

    }
    
}


// MARK: - Other methods

extension PersistedMessageSentRecipientInfos {
    
    func setMessageIdentifierFromEngine(to messageIdentifierFromEngine: Data, andReturnReceiptElementsTo elements: (nonce: Data, key: Data)) {
        assert(elements.nonce.count == 16)
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.returnReceiptNonce = elements.nonce
        self.returnReceiptKey = elements.key
        self.messageSent.refreshStatus()
    }

    func setTimestampMessageSent(to timestamp: Date) {
        guard self.timestampMessageSent != timestamp else { return }
        assert(self.timestampMessageSent == nil) // Otherwise, it means of have been sent two distinct sent timestamp, which would be a bug
        self.timestampMessageSent = timestamp
        // If the message has no attachment, we also set timestampAllAttachmentsSent
        if messageSent.fyleMessageJoinWithStatuses.isEmpty {
            self.timestampAllAttachmentsSent = timestamp
        }
        self.messageSent.refreshStatus()
    }


    func setTimestampDelivered(to timestamp: Date) {
        if let currentTimeStamp = self.timestampDelivered {
            guard currentTimeStamp != timestamp else { return }
            self.timestampDelivered = min(timestamp, currentTimeStamp)
        } else {
            self.timestampDelivered = timestamp
        }
        self.messageSent.refreshStatus()
    }


    func setTimestampRead(to timestamp: Date) {
        if let currentTimeStamp = self.timestampRead {
            guard currentTimeStamp != timestamp else { return }
            self.timestampRead = min(timestamp, currentTimeStamp)
        } else {
            self.timestampRead = timestamp
        }
        self.messageSent.refreshStatus()
    }
    
    func setTimestampAllAttachmentsSentIfPossible() {
        guard self.timestampAllAttachmentsSent == nil else { return }
        let allAttachmentsAreComplete = messageSent.fyleMessageJoinWithStatuses.reduce(true) { $0 && ($1.status == .complete) }
        guard allAttachmentsAreComplete else { return }
        self.timestampAllAttachmentsSent = Date()
        debugPrint(allAttachmentsAreComplete)
        self.messageSent.refreshStatus()
    }
}


// MARK: - Convenience DB getters

extension PersistedMessageSentRecipientInfos {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSentRecipientInfos> {
        return NSFetchRequest<PersistedMessageSentRecipientInfos>(entityName: PersistedMessageSentRecipientInfos.entityName)
    }


    static func getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        messageIdentifierFromEngineKey, messageIdentifierFromEngine as CVarArg)
        return try context.fetch(request)
    }

    
    static func getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        messageIdentifierFromEngineKey, messageIdentifierFromEngine as CVarArg,
                                        ownedIdentityKey, ownedCryptoId.getIdentity() as NSData)
        return try context.fetch(request)
    }


    /// This methods returns all the `PersistedMessageSentRecipientInfos` that are still unprocessed, i.e., that have no message identifier from the engine.
    static func getAllUnprocessed(within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSPredicate(format: "%K == nil", messageIdentifierFromEngineKey)
        return try context.fetch(request)
    }

    
    static func getAllUnprocessedForSpecificContact(_ obvContactIdentity: ObvContactIdentity, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == nil", messageIdentifierFromEngineKey),
            NSPredicate(format: "%K == %@", recipientIdentityKey, obvContactIdentity.cryptoId.getIdentity() as NSData),
            NSPredicate(format: "%K == %@", ownedIdentityKey, obvContactIdentity.ownedIdentity.cryptoId.getIdentity() as NSData),
        ])
        return try context.fetch(request)
    }

    
    /// This methods returns all the `PersistedMessageSentRecipientInfos` with the appropriate `nonce` and recipient
    static func get(withNonce nonce: Data, ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Set<PersistedMessageSentRecipientInfos> {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        returnReceiptNonceKey, nonce as NSData,
                                        ownedIdentityKey, ownedIdentity.getIdentity() as NSData)
        return Set(try context.fetch(request))
    }
}
