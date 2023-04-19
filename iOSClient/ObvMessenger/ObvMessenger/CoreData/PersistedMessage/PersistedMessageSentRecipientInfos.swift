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
import ObvTypes
import OlvidUtils

@objc(PersistedMessageSentRecipientInfos)
final class PersistedMessageSentRecipientInfos: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedMessageSentRecipientInfos"
    static let errorDomain = "PersistedMessageSentRecipientInfos"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageSentRecipientInfos")
    
    // MARK: Attributes

    @NSManaged private(set) var couldNotBeSentToServer: Bool // Set to true if the engine could not send message during 30 days
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

    // MARK: Relationships
    
    @NSManaged private(set) var messageSent: PersistedMessageSent
    @NSManaged private(set) var attachmentInfos: Set<PersistedAttachmentSentRecipientInfos>

    // MARK: Computed variables
    
    var recipientCryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: recipientIdentity)
    }
    
    func getRecipient() throws -> PersistedObvContactIdentity? {
        guard let ownedIdentity = self.messageSent.discussion.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it has just been deleted.", log: log, type: .error)
            return nil
        }
        return try PersistedObvContactIdentity.get(cryptoId: recipientCryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any)
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


    // MARK: - Initializer
    
    /// Shall *only* be called from within the intialiazer of `PersistedMessageSent`.
    convenience init(recipientIdentity: Data, messageSent: PersistedMessageSent) throws {
     
        guard let context = messageSent.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedMessageSentRecipientInfos.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        _ = try ObvCryptoId(identity: recipientIdentity)
        
        self.couldNotBeSentToServer = false
        self.messageIdentifierFromEngine = nil
        self.recipientIdentity = recipientIdentity
        self.returnReceiptKey = nil
        self.returnReceiptNonce = nil
        self.timestampDelivered = nil
        self.timestampRead = nil
        self.timestampMessageSent = nil
        self.timestampAllAttachmentsSent = nil
        
        self.messageSent = messageSent
        self.attachmentInfos = Set(messageSent.fyleMessageJoinWithStatuses.compactMap({ try? PersistedAttachmentSentRecipientInfos(index: $0.index, info: self) }))

    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        context.delete(self)
        messageSent.refreshStatus()
    }


    // MARK: - Other methods
    
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
        self.couldNotBeSentToServer = false
        self.messageSent.refreshStatus()
    }


    func setTimestampAllAttachmentsSentIfPossible() {
        guard self.timestampAllAttachmentsSent == nil else { return }
        let allAttachmentsAreComplete = messageSent.fyleMessageJoinWithStatuses.allSatisfy { $0.status == .complete }
        guard allAttachmentsAreComplete else { return }
        self.timestampAllAttachmentsSent = Date()
        self.couldNotBeSentToServer = false
        self.messageSent.refreshStatus()
    }

    
    func setAsCouldNotBeSentToServer() {
        guard timestampMessageSent == nil && timestampRead == nil && timestampDelivered == nil && timestampAllAttachmentsSent == nil else {
            assertionFailure()
            return
        }
        self.couldNotBeSentToServer = true
        self.messageSent.refreshStatus()
    }

    
    func messageWasDeliveredNoLaterThan(_ timestamp: Date, andRead: Bool) {
        self.couldNotBeSentToServer = false
        if let currentTimeStamp = self.timestampDelivered, currentTimeStamp != timestamp {
            self.timestampDelivered = min(timestamp, currentTimeStamp)
        } else {
            self.timestampDelivered = timestamp
        }
        if andRead {
            if let currentTimeStamp = self.timestampRead, currentTimeStamp != timestamp {
                self.timestampRead = min(timestamp, currentTimeStamp)
            } else {
                self.timestampRead = timestamp
            }
        }
    }

    
    func messageAndAttachmentWereDeliveredNoLaterThan(_ timestamp: Date, attachmentNumber: Int, andRead: Bool) {
        self.couldNotBeSentToServer = false
        messageWasDeliveredNoLaterThan(timestamp, andRead: false) // We do not assume that the message was read, even if the attachment was read
        do {
            let attachmentInfosOfDeliveredAttachment = try attachmentInfos.first(where: { $0.index == attachmentNumber }) ?? PersistedAttachmentSentRecipientInfos(index: attachmentNumber, info: self)
            attachmentInfosOfDeliveredAttachment.status = .delivered
            if andRead {
                attachmentInfosOfDeliveredAttachment.status = .read
            }
        } catch {
            assertionFailure()
            // In production, continue anyway
        }
    }


    // MARK: - Convenience DB getters
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case messageIdentifierFromEngine = "messageIdentifierFromEngine"
            case recipientIdentity = "recipientIdentity"
            case returnReceiptNonce = "returnReceiptNonce"
            case timestampDelivered = "timestampDelivered"
            // Relationships
            case messageSent = "messageSent"
            // Others
            static let ownedIdentityIdentity = [
                messageSent.rawValue,
                PersistedMessage.Predicate.Key.discussion.rawValue,
                PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue,
                PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue,
            ].joined(separator: ".")
            static let discussion = [
                messageSent.rawValue,
                PersistedMessage.Predicate.Key.discussion.rawValue,
            ].joined(separator: ".")
        }
        static func withMessageIdentifierFromEngine(equalTo messageIdentifierFromEngine: Data) -> NSPredicate {
            NSPredicate(Key.messageIdentifierFromEngine, EqualToData: messageIdentifierFromEngine)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withRecipientIdentity(_ recipientIdentity: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.recipientIdentity, EqualToData: recipientIdentity.getIdentity())
        }
        static func withReturnReceiptNonce(_ returnReceiptNonce: Data) -> NSPredicate {
            NSPredicate(Key.returnReceiptNonce, EqualToData: returnReceiptNonce)
        }
        static var withNoMessageIdentifierFromEngine: NSPredicate {
            NSPredicate(withNilValueForKey: Key.messageIdentifierFromEngine)
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(Key.discussion, equalTo: discussion)
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSentRecipientInfos> {
        return NSFetchRequest<PersistedMessageSentRecipientInfos>(entityName: PersistedMessageSentRecipientInfos.entityName)
    }


    static func getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withMessageIdentifierFromEngine(equalTo: messageIdentifierFromEngine)
        return try context.fetch(request)
    }

    
    static func getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifierFromEngine(equalTo: messageIdentifierFromEngine),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        return try context.fetch(request)
    }


    /// Returns all the `PersistedMessageSentRecipientInfos` that are still unprocessed, i.e., that have no message identifier from the engine.
    static func getAllUnprocessed(within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withNoMessageIdentifierFromEngine
        return try context.fetch(request)
    }

    
    static func getAllUnprocessedForSpecificContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNoMessageIdentifierFromEngine,
            Predicate.withRecipientIdentity(contactCryptoId),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        return try context.fetch(request)
    }

    
    static func countAllUnprocessedForSpecificContact(contactCryptoId: ObvCryptoId, ownedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = ownedIdentity.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNoMessageIdentifierFromEngine,
            Predicate.withRecipientIdentity(contactCryptoId),
            Predicate.withOwnedCryptoId(ownedIdentity.cryptoId),
        ])
        return try context.count(for: request)
    }

    
    static func getAllUnprocessedForContact(contactCryptoId: ObvCryptoId, forMessagesWithinDiscussion discussion: PersistedDiscussion) throws -> [PersistedMessageSentRecipientInfos] {
        guard let context = discussion.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNoMessageIdentifierFromEngine,
            Predicate.withRecipientIdentity(contactCryptoId),
            Predicate.withinDiscussion(discussion),
        ])
        return try context.fetch(request)
    }

    
    /// Returns all the `PersistedMessageSentRecipientInfos` with the appropriate `nonce` and recipient
    static func get(withNonce nonce: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<PersistedMessageSentRecipientInfos> {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withReturnReceiptNonce(nonce),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        return Set(try context.fetch(request))
    }

}
